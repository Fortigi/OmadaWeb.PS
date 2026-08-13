#Requires -Version 5.1

<#
.SYNOPSIS
    Generates a CycloneDX 1.5 Software Bill of Materials for OmadaWeb.PS.
.DESCRIPTION
    OmadaWeb.PS ships no binaries of its own - Selenium, Newtonsoft.Json, System.Text.Json,
    System.Runtime, the Microsoft WebView2 assemblies and msedgedriver.exe are all downloaded to
    %LOCALAPPDATA%\OmadaWeb.PS\Bin the first time they are needed. Those components never pass
    through a package manifest, so nothing else in the toolchain can enumerate them.

    This script reads the declared inventory in Build/Dependencies.psd1 and emits a CycloneDX 1.5
    JSON document describing the module plus each of those components, including source URL and
    license.

    When the components are actually present on disk (-BinPath, which the release pipeline warms up
    before packaging), each installed file is recorded with its resolved version and SHA-256 hash, so
    the SBOM states what was really loaded and not just what was declared. Components whose files are
    absent are still emitted, carrying their VersionStrategy so a reader can see how the version is
    resolved at runtime.
.PARAMETER ModuleVersion
    Version recorded for the OmadaWeb.PS component itself. Defaults to the ModuleVersion in the
    module manifest.
.PARAMETER OutputPath
    File to write the SBOM to. Defaults to OmadaWeb.PS-<version>.cdx.json in the current directory.
.PARAMETER BinPath
    Root folder to look for the downloaded binaries in. Defaults to %LOCALAPPDATA%\OmadaWeb.PS\Bin,
    which is where the module puts them.
.PARAMETER SerialNumber
    Overrides the generated "urn:uuid:..." BOM serial number. Only useful for reproducible tests.
.PARAMETER Timestamp
    Overrides the metadata timestamp. Only useful for reproducible tests.
.EXAMPLE
    ./Build/New-Sbom.ps1 -ModuleVersion '2026.8.13.1' -OutputPath ./OmadaWeb.PS.cdx.json

    Generates the SBOM for a specific release version.
.EXAMPLE
    ./Build/New-Sbom.ps1 -Verbose

    Generates an SBOM for the current working copy and reports which components were resolved from
    disk and which were emitted from the declared inventory alone.
#>
[CmdletBinding()]
param(
    [string]$ModuleVersion,
    [string]$OutputPath,
    [string]$BinPath,
    [string]$DependencyManifestPath = (Join-Path $PSScriptRoot "Dependencies.psd1"),
    [string]$ModuleManifestPath = (Join-Path $PSScriptRoot ".." | Join-Path -ChildPath "OmadaWeb.PS" | Join-Path -ChildPath "OmadaWeb.PS.psd1"),
    [string]$SerialNumber,
    [string]$Timestamp
)

$ErrorActionPreference = "Stop"

$ProjectUrl = "https://github.com/Fortigi/OmadaWeb.PS"

function Get-DefaultBinPath {
    # Mirrors the layout OmadaWeb.PS.psm1 creates: <LocalApplicationData>\OmadaWeb.PS\Bin, with the
    # per-edition (Core/Desktop) and per-architecture folders below it.
    $LocalAppData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($LocalAppData)) {
        return $null
    }
    return (Join-Path $LocalAppData "OmadaWeb.PS" | Join-Path -ChildPath "Bin")
}

function Get-FileHashSha256 {
    param([string]$Path)

    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $Stream = [System.IO.File]::OpenRead($Path)
        try {
            return ([System.BitConverter]::ToString($Sha.ComputeHash($Stream)) -replace "-", "").ToLowerInvariant()
        }
        finally {
            $Stream.Dispose()
        }
    }
    finally {
        $Sha.Dispose()
    }
}

function Get-InstalledComponentFile {
    param(
        [string[]]$FileNames,
        [string]$SearchRoot
    )

    $Found = @()
    if ([string]::IsNullOrWhiteSpace($SearchRoot) -or -not (Test-Path $SearchRoot -PathType Container)) {
        return $Found
    }

    foreach ($FileName in $FileNames) {
        # A component's file can appear more than once under the Bin root (per edition and per
        # architecture); the newest one is the one a fresh session would load.
        $Item = Get-ChildItem -Path $SearchRoot -Filter $FileName -Recurse -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($null -eq $Item) {
            continue
        }
        $Version = $Item.VersionInfo.ProductVersion
        if ([string]::IsNullOrWhiteSpace($Version)) {
            $Version = $Item.VersionInfo.FileVersion
        }
        $Found += [pscustomobject]@{
            Name    = $Item.Name
            Path    = $Item.FullName
            Version = if ([string]::IsNullOrWhiteSpace($Version)) { "" } else { $Version.Trim() }
            Sha256  = Get-FileHashSha256 -Path $Item.FullName
        }
    }
    return $Found
}

function New-LicenseEntry {
    param($Component)

    if (-not [string]::IsNullOrWhiteSpace($Component.LicenseId)) {
        $License = [ordered]@{ id = $Component.LicenseId }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Component.LicenseName)) {
        $License = [ordered]@{ name = $Component.LicenseName }
    }
    else {
        return @()
    }

    if (-not [string]::IsNullOrWhiteSpace($Component.LicenseUrl)) {
        $License["url"] = $Component.LicenseUrl
    }
    return @([ordered]@{ license = $License })
}

function New-Property {
    param([string]$Name, [string]$Value)
    return [ordered]@{ name = $Name; value = $Value }
}

if ([string]::IsNullOrWhiteSpace($ModuleVersion)) {
    $ModuleVersion = (Import-PowerShellDataFile -Path $ModuleManifestPath).ModuleVersion
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Get-Location).Path ("OmadaWeb.PS-{0}.cdx.json" -f $ModuleVersion)
}
if (-not $PSBoundParameters.ContainsKey("BinPath")) {
    $BinPath = Get-DefaultBinPath
}
if ([string]::IsNullOrWhiteSpace($SerialNumber)) {
    $SerialNumber = "urn:uuid:{0}" -f [System.Guid]::NewGuid().ToString()
}
if ([string]::IsNullOrWhiteSpace($Timestamp)) {
    $Timestamp = [System.DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
}

$Inventory = Import-PowerShellDataFile -Path $DependencyManifestPath
if ($null -eq $Inventory.Components -or $Inventory.Components.Count -eq 0) {
    "No components found in '{0}'. The SBOM would be empty." -f $DependencyManifestPath | Write-Error -ErrorAction Stop
}

$RootRef = "pkg:powershellgallery/OmadaWeb.PS@{0}" -f $ModuleVersion
$Components = [System.Collections.Generic.List[object]]::new()
$ComponentRefs = [System.Collections.Generic.List[string]]::new()

foreach ($Declared in $Inventory.Components) {
    foreach ($RequiredKey in @("Name", "Type", "Purl", "Files")) {
        if (-not $Declared.ContainsKey($RequiredKey)) {
            "Component '{0}' in '{1}' is missing the required key '{2}'." -f $Declared.Name, $DependencyManifestPath, $RequiredKey | Write-Error -ErrorAction Stop
        }
    }

    $Installed = @(Get-InstalledComponentFile -FileNames $Declared.Files -SearchRoot $BinPath)

    # Precedence: what is actually on disk beats the declared pin, which beats "unresolved".
    $ResolvedVersion = ($Installed | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Version) } | Select-Object -First 1).Version
    $VersionSource = "resolved-from-installed-binary"
    if ([string]::IsNullOrWhiteSpace($ResolvedVersion)) {
        $ResolvedVersion = $Declared.Version
        $VersionSource = "declared-pin"
    }
    if ([string]::IsNullOrWhiteSpace($ResolvedVersion)) {
        $ResolvedVersion = ""
        $VersionSource = "resolved-at-runtime"
        "Component '{0}' has no pinned version and no version could be read from '{1}'; emitting it without a version." -f $Declared.Name, $BinPath | Write-Verbose
    }
    else {
        "Component '{0}' version '{1}' ({2})." -f $Declared.Name, $ResolvedVersion, $VersionSource | Write-Verbose
    }

    $Purl = $Declared.Purl
    if (-not [string]::IsNullOrWhiteSpace($ResolvedVersion)) {
        $Purl = "{0}@{1}" -f $Declared.Purl, $ResolvedVersion
    }

    $Component = [ordered]@{
        type      = $Declared.Type
        "bom-ref" = $Purl
        name      = $Declared.Name
        purl      = $Purl
        scope     = "required"
    }
    if (-not [string]::IsNullOrWhiteSpace($ResolvedVersion)) {
        $Component["version"] = $ResolvedVersion
    }
    if (-not [string]::IsNullOrWhiteSpace($Declared.Publisher)) {
        $Component["publisher"] = $Declared.Publisher
    }
    if (-not [string]::IsNullOrWhiteSpace($Declared.Description)) {
        $Component["description"] = $Declared.Description
    }

    # @() around the call because returning a one-element array from a function unrolls it, and
    # CycloneDX requires "licenses" to be an array even with a single license.
    $Licenses = @(New-LicenseEntry -Component $Declared)
    if ($Licenses.Count -gt 0) {
        $Component["licenses"] = $Licenses
    }

    # CycloneDX hashes describe the component as a whole, so a single-file component can carry its
    # hash directly. Multi-file components (WebView2) get per-file hashes as properties further
    # down instead, since no single hash would identify the set.
    if ($Installed.Count -eq 1) {
        $Component["hashes"] = @([ordered]@{ alg = "SHA-256"; content = $Installed[0].Sha256 })
    }

    $ExternalReferences = [System.Collections.Generic.List[object]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Declared.Source)) {
        $ExternalReferences.Add([ordered]@{ type = "distribution"; url = $Declared.Source })
    }
    if (-not [string]::IsNullOrWhiteSpace($Declared.Website)) {
        $ExternalReferences.Add([ordered]@{ type = "website"; url = $Declared.Website })
    }
    if ($ExternalReferences.Count -gt 0) {
        $Component["externalReferences"] = $ExternalReferences.ToArray()
    }

    $Properties = [System.Collections.Generic.List[object]]::new()
    $Properties.Add((New-Property -Name "omadaweb:acquisition" -Value "runtime-download"))
    $Properties.Add((New-Property -Name "omadaweb:versionSource" -Value $VersionSource))
    if (-not [string]::IsNullOrWhiteSpace($Declared.VersionStrategy)) {
        $Properties.Add((New-Property -Name "omadaweb:versionStrategy" -Value $Declared.VersionStrategy))
    }
    if (-not [string]::IsNullOrWhiteSpace($Declared.InstalledBy)) {
        $Properties.Add((New-Property -Name "omadaweb:installedBy" -Value $Declared.InstalledBy))
    }
    foreach ($FileName in $Declared.Files) {
        $Properties.Add((New-Property -Name "omadaweb:file" -Value $FileName))
    }
    foreach ($File in $Installed) {
        $Properties.Add((New-Property -Name ("omadaweb:installedFile:{0}" -f $File.Name) -Value ("version={0}; sha256={1}" -f $File.Version, $File.Sha256)))
    }
    $Component["properties"] = $Properties.ToArray()

    $Components.Add($Component)
    $ComponentRefs.Add($Component."bom-ref")
}

$Sbom = [ordered]@{
    bomFormat    = "CycloneDX"
    specVersion  = "1.5"
    serialNumber = $SerialNumber
    version      = 1
    metadata     = [ordered]@{
        timestamp = $Timestamp
        tools     = [ordered]@{
            components = @(
                [ordered]@{
                    type    = "application"
                    name    = "OmadaWeb.PS New-Sbom.ps1"
                    version = $ModuleVersion
                }
            )
        }
        component = [ordered]@{
            type               = "application"
            "bom-ref"          = $RootRef
            name               = "OmadaWeb.PS"
            version            = $ModuleVersion
            publisher          = "Fortigi"
            description        = "PowerShell module to manage data via Omada web and OData endpoints."
            purl               = $RootRef
            licenses           = @([ordered]@{ license = [ordered]@{ id = "MIT"; url = "{0}/blob/main/LICENSE" -f $ProjectUrl } })
            externalReferences = @(
                [ordered]@{ type = "vcs"; url = $ProjectUrl }
                [ordered]@{ type = "distribution"; url = "https://www.powershellgallery.com/packages/OmadaWeb.PS" }
                [ordered]@{ type = "issue-tracker"; url = "{0}/issues" -f $ProjectUrl }
            )
        }
        supplier  = [ordered]@{
            name = "Fortigi"
            url  = @($ProjectUrl)
        }
    }
    components   = $Components.ToArray()
    dependencies = @(
        [ordered]@{ ref = $RootRef; dependsOn = $ComponentRefs.ToArray() }
    ) + @($ComponentRefs | ForEach-Object { [ordered]@{ ref = $_; dependsOn = @() } })
}

$OutputDirectory = Split-Path $OutputPath -Parent
if (-not [string]::IsNullOrWhiteSpace($OutputDirectory) -and -not (Test-Path $OutputDirectory -PathType Container)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}

$Json = $Sbom | ConvertTo-Json -Depth 12
# Set-Content -Encoding UTF8 writes a BOM on Windows PowerShell 5.1, which some SBOM consumers reject.
[System.IO.File]::WriteAllText($OutputPath, $Json, (New-Object System.Text.UTF8Encoding($false)))

"SBOM written: {0} ({1} components)" -f $OutputPath, $Components.Count | Write-Host -ForegroundColor Green
return $OutputPath
