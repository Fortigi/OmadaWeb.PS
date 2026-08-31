#Requires -Version 5.1

<#
.SYNOPSIS
    Checks or refreshes the pinned versions and SHA-256 hashes in OmadaWeb.PS/DependencyLock.psd1.
.DESCRIPTION
    OmadaWeb.PS downloads its binaries at runtime and verifies each one against the pinned SHA-256 in
    OmadaWeb.PS/DependencyLock.psd1 before it is expanded, copied into Bin or loaded. That only holds
    if the lock file stays truthful, which is what this script is for.

    The versions themselves live in the Dependabot manifests under Build/Dependencies. Dependabot
    bumps a version there, this script recomputes the matching URL and hash, and PR validation fails
    for as long as the two disagree.

    A bump touches three files, not one: the version in the Dependabot manifest, the version and
    SHA-256 in the lock file, and the version the SBOM inventory in Build/Dependencies.psd1 reports
    for the same component. This script keeps the second and third in step with the first.

    -Check validates the lock file and reports drift without changing anything. It is what runs in
    CI: schema and formatting, one entry per artefact, versions matching the manifests, every
    -ArtifactId used in the module present in the lock, the SBOM reporting the versions that are
    actually pinned, every member of the System.Text.Json closure covered by an ignore rule in
    .github/dependabot.yml, and - unless -SkipDownload is given - the published bytes still hashing to
    what is pinned.

    -Refresh takes the versions from the manifests, downloads each artefact, and writes back the
    version, URL and hash of anything that moved, plus the matching version in the SBOM inventory.
    Only those values are rewritten, in place, so comments and the descriptive fields are preserved.
.PARAMETER Check
    Report drift and exit non-zero if any is found. Changes nothing.
.PARAMETER Refresh
    Rewrite version, URL and SHA-256 for artefacts whose manifest version has moved, and the version
    of the SBOM component that mirrors each of them.
.PARAMETER SkipDownload
    Skip everything that needs the network, leaving only the offline consistency checks. Only valid
    with -Check.
.PARAMETER LockPath
    Path to the lock file. Defaults to OmadaWeb.PS/DependencyLock.psd1 under -RepositoryRoot.
.PARAMETER InventoryPath
    Path to the SBOM inventory. Defaults to Build/Dependencies.psd1 under -RepositoryRoot.
.PARAMETER DependabotConfigPath
    Path to the Dependabot configuration the ignore policy is read from. Defaults to
    .github/dependabot.yml under -RepositoryRoot.
.PARAMETER RepositoryRoot
    Working tree the manifests, lock file, SBOM inventory and module sources are read from. Defaults
    to the repository this script lives in; the scheduled sweep in dependency-lock-sync.yml points it
    at a second checkout so a trusted copy of this script refreshes a pull request branch.
.EXAMPLE
    ./Build/Update-DependencyLock.ps1 -Check

    Verifies that every pinned artefact still hashes to what the lock file claims.
.EXAMPLE
    ./Build/Update-DependencyLock.ps1 -Refresh

    Picks up the versions from Build/Dependencies and refreshes the hashes after a Dependabot bump.
#>
[CmdletBinding(DefaultParameterSetName = "Check")]
param(
    [parameter(Mandatory = $false, ParameterSetName = "Check")]
    [switch]$Check,
    [parameter(Mandatory = $true, ParameterSetName = "Refresh")]
    [switch]$Refresh,
    [parameter(Mandatory = $false, ParameterSetName = "Check")]
    [switch]$SkipDownload,
    [parameter(Mandatory = $false)]
    [string]$LockPath,
    [parameter(Mandatory = $false)]
    [string]$InventoryPath,
    [parameter(Mandatory = $false)]
    [string]$DependabotConfigPath,
    [parameter(Mandatory = $false)]
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot ".." | Convert-Path)
)

$ErrorActionPreference = "Stop"

$Script:IsRefresh = $PSCmdlet.ParameterSetName -eq "Refresh"

# All three files are resolved from -RepositoryRoot unless they are named explicitly, so pointing the
# script at a second working tree - which is how the scheduled sweep in dependency-lock-sync.yml runs
# a trusted copy of this script against a pull request branch - takes one parameter rather than four.
if ([string]::IsNullOrWhiteSpace($LockPath)) {
    $LockPath = Join-Path $RepositoryRoot "OmadaWeb.PS" | Join-Path -ChildPath "DependencyLock.psd1"
}

if ([string]::IsNullOrWhiteSpace($InventoryPath)) {
    $InventoryPath = Join-Path $RepositoryRoot "Build" | Join-Path -ChildPath "Dependencies.psd1"
}

if ([string]::IsNullOrWhiteSpace($DependabotConfigPath)) {
    $DependabotConfigPath = Join-Path $RepositoryRoot ".github" | Join-Path -ChildPath "dependabot.yml"
}

$Problems = [System.Collections.Generic.List[string]]::new()

function Add-Problem {
    param([string]$Message)

    $Problems.Add($Message)
    $Message | Write-Host -ForegroundColor Red
}

function Add-Drift {
    # Drift between a manifest version and what the lock or the SBOM records is a build failure under
    # -Check and the whole point of the run under -Refresh. Reporting it as a problem in both modes
    # would make -Refresh exit non-zero on exactly the bumps it was invoked to resolve, which stops
    # the caller - dependency-lock-sync.yml - from ever reaching its commit step.
    param([string]$Message)

    if ($Script:IsRefresh) {
        $Message | Write-Host -ForegroundColor Yellow
        return
    }

    Add-Problem $Message
}

function Get-ManifestVersion {
    # Reads the PackageReference versions out of a Dependabot manifest. These files are never built,
    # so they are parsed as plain XML rather than through MSBuild.
    param([string]$ManifestPath)

    $Versions = @{}
    if (-not (Test-Path $ManifestPath -PathType Leaf)) {
        Add-Problem ("Dependency manifest '{0}' does not exist." -f $ManifestPath)
        return $Versions
    }

    [xml]$Manifest = Get-Content -Path $ManifestPath -Raw
    foreach ($Reference in $Manifest.Project.ItemGroup.PackageReference) {
        if ($null -eq $Reference) {
            continue
        }
        $Versions[$Reference.Include] = $Reference.Version
    }
    return $Versions
}

function Remove-YamlQuote {
    # YAML scalars may be double-quoted, single-quoted or bare, and all three mean the same string.
    # Reading only one of the forms would turn a harmless reformatting of dependabot.yml into a build
    # failure, so the quotes are stripped rather than matched.
    param([string]$Value)

    $Trimmed = $Value.Trim()
    if ($Trimmed.Length -ge 2) {
        $Quote = $Trimmed[0]
        if (($Quote -eq '"' -or $Quote -eq "'") -and $Trimmed[$Trimmed.Length - 1] -eq $Quote) {
            return $Trimmed.Substring(1, $Trimmed.Length - 2)
        }
    }
    return $Trimmed
}

function Get-IgnoredDependencyName {
    # Collects the dependency-name entries Dependabot is told to ignore for one manifest directory.
    #
    # Parsed by hand rather than with a YAML module: this has to run on Windows PowerShell 5.1 in CI,
    # where no YAML parser ships in the box, and the shape being read is a fixed two-level list this
    # repository writes itself. Only entries under the requested directory are returned, so ignoring
    # a package for Legacy/ does not silently satisfy a check about the main manifest.
    param([string]$ConfigPath, [string]$Directory)

    $Names = @()
    if (-not (Test-Path $ConfigPath -PathType Leaf)) {
        Add-Problem ("Dependabot configuration '{0}' does not exist, so the ignore policy cannot be verified." -f $ConfigPath)
        return $Names
    }

    $InRequestedUpdate = $false
    $InIgnoreList = $false
    foreach ($Line in (Get-Content -Path $ConfigPath)) {
        if ($Line -match '^\s*-\s+package-ecosystem\s*:') {
            # A new update block ends whatever the previous one was saying.
            $InRequestedUpdate = $false
            $InIgnoreList = $false
            continue
        }

        if ($Line -match '^\s*directory\s*:\s*(.+?)\s*$') {
            # A directory line starts a new scope even without an intervening package-ecosystem, so
            # an ignore list already being read ends here.
            $InRequestedUpdate = ((Remove-YamlQuote $Matches[1]) -eq $Directory)
            $InIgnoreList = $false
            continue
        }

        if (-not $InRequestedUpdate) {
            continue
        }

        if ($Line -match '^\s*ignore\s*:\s*$') {
            $InIgnoreList = $true
            continue
        }

        if ($InIgnoreList -and $Line -match '^\s*-\s+dependency-name\s*:\s*(.+?)\s*$') {
            $Names += Remove-YamlQuote $Matches[1]
        }
    }
    return $Names
}

function Get-InventoryComponent {
    # Reads the SBOM inventory, keyed by the lock artefact each component mirrors. Components that
    # name no LockId - the ones whose version is resolved at runtime - are not tracked here.
    param([string]$Path)

    $ByLockId = @{}
    if (-not (Test-Path $Path -PathType Leaf)) {
        Add-Problem ("SBOM inventory '{0}' does not exist." -f $Path)
        return $ByLockId
    }

    $Inventory = Import-PowerShellDataFile -Path $Path
    foreach ($Component in $Inventory.Components) {
        if ([string]::IsNullOrWhiteSpace($Component.LockId)) {
            continue
        }
        $ByLockId[$Component.LockId] = $Component
    }
    return $ByLockId
}

function Set-InventoryVersion {
    # Rewrites the Version of one SBOM component in place, leaving every other line untouched.
    #
    # Components are keyed by LockId, which sits *after* Version in the block, so the most recent
    # Version line is remembered and rewritten once the matching LockId is reached. The @{ that opens
    # each component resets that memory, so a component without a LockId can never have the Version of
    # the block before it rewritten by mistake.
    param(
        [string[]]$Line,
        [string]$LockId,
        [string]$Version
    )

    $VersionIndex = -1
    for ($Index = 0; $Index -lt $Line.Count; $Index++) {
        if ($Line[$Index] -match '^\s*@\{\s*$') {
            $VersionIndex = -1
            continue
        }
        if ($Line[$Index] -match '^(\s*Version\s*=\s*)"[^"]*"\s*$') {
            $VersionIndex = $Index
            continue
        }
        if ($Line[$Index] -match '^\s*LockId\s*=\s*"([^"]+)"\s*$' -and $Matches[1] -eq $LockId) {
            if ($VersionIndex -lt 0) {
                Add-Problem ("SBOM component for lock artefact '{0}' has no Version line to update." -f $LockId)
                continue
            }
            $Line[$VersionIndex] -match '^(\s*Version\s*=\s*)"[^"]*"\s*$' | Out-Null
            $Line[$VersionIndex] = '{0}"{1}"' -f $Matches[1], $Version
        }
    }
    return $Line
}

function Get-FlatContainerUrl {
    param([string]$PackageId, [string]$Version)

    return "https://api.nuget.org/v3-flatcontainer/{0}/{1}/{0}.{1}.nupkg" -f $PackageId.ToLowerInvariant(), $Version.ToLowerInvariant()
}

function Get-RemoteSha256 {
    param([string]$Url)

    $TempFile = [System.IO.Path]::GetTempFileName()
    try {
        $WebClient = New-Object System.Net.WebClient
        try {
            $WebClient.DownloadFile($Url, $TempFile)
        }
        finally {
            $WebClient.Dispose()
        }
        return (Get-FileHash -Path $TempFile -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    finally {
        Remove-Item -Path $TempFile -Force -ErrorAction SilentlyContinue
    }
}

function Set-ArtifactValue {
    # Rewrites Version/Url/Sha256 in place for one artefact, leaving every other line - comments and
    # alignment included - exactly as it was.
    param(
        [string[]]$Line,
        [string]$Id,
        [hashtable]$Value
    )

    $CurrentId = $null
    for ($Index = 0; $Index -lt $Line.Count; $Index++) {
        if ($Line[$Index] -match '^\s*Id\s*=\s*"([^"]+)"\s*$') {
            $CurrentId = $Matches[1]
            continue
        }
        if ($CurrentId -ne $Id) {
            continue
        }
        foreach ($Key in $Value.Keys) {
            if ($Line[$Index] -match ('^(\s*{0}\s*=\s*)"[^"]*"\s*$' -f [regex]::Escape($Key))) {
                $Line[$Index] = '{0}"{1}"' -f $Matches[1], $Value[$Key]
            }
        }
    }
    return $Line
}

if ($SkipDownload -and $PSCmdlet.ParameterSetName -ne "Check") {
    "-SkipDownload is only valid together with -Check." | Write-Error -ErrorAction Stop
}

if (-not (Test-Path $LockPath -PathType Leaf)) {
    "Lock file '{0}' does not exist." -f $LockPath | Write-Error -ErrorAction Stop
}

$Lock = Import-PowerShellDataFile -Path $LockPath
$Artifacts = @($Lock.Artifacts)

"Dependency lock: {0}" -f $LockPath | Write-Host -ForegroundColor Cyan
"Artefacts: {0}" -f $Artifacts.Count | Write-Host

#region offline consistency checks

if ($Lock.SchemaVersion -ne 1) {
    Add-Problem ("Lock file schema version is '{0}', expected 1." -f $Lock.SchemaVersion)
}

$DuplicateIds = $Artifacts | Group-Object { $_.Id } | Where-Object { $_.Count -gt 1 }
foreach ($Duplicate in $DuplicateIds) {
    Add-Problem ("Artefact id '{0}' is listed {1} times; ids must be unique." -f $Duplicate.Name, $Duplicate.Count)
}

$ManifestVersions = @{}
foreach ($Artifact in $Artifacts) {
    foreach ($RequiredKey in @("Id", "Verification", "InstalledBy")) {
        if (-not $Artifact.ContainsKey($RequiredKey) -or [string]::IsNullOrWhiteSpace($Artifact[$RequiredKey])) {
            Add-Problem ("Artefact '{0}' is missing the required key '{1}'." -f $Artifact.Id, $RequiredKey)
        }
    }

    if ($Artifact.Verification -eq "Authenticode") {
        if ([string]::IsNullOrWhiteSpace($Artifact.SubjectPattern)) {
            Add-Problem ("Artefact '{0}' is Authenticode-verified but has no SubjectPattern, so any publisher would pass." -f $Artifact.Id)
        }
        continue
    }

    if ($Artifact.Verification -ne "Sha256") {
        Add-Problem ("Artefact '{0}' has unknown Verification '{1}'; expected 'Sha256' or 'Authenticode'." -f $Artifact.Id, $Artifact.Verification)
        continue
    }

    if ($Artifact.Sha256 -notmatch '^[0-9a-f]{64}$') {
        Add-Problem ("Artefact '{0}' has SHA-256 '{1}', which is not 64 lower-case hex characters." -f $Artifact.Id, $Artifact.Sha256)
    }

    $ExpectedUrl = Get-FlatContainerUrl -PackageId $Artifact.PackageId -Version $Artifact.Version
    if ($Artifact.Url -ne $ExpectedUrl) {
        Add-Problem ("Artefact '{0}' has URL '{1}' but its pinned version implies '{2}'." -f $Artifact.Id, $Artifact.Url, $ExpectedUrl)
    }

    if ([string]::IsNullOrWhiteSpace($Artifact.Manifest)) {
        Add-Problem ("Artefact '{0}' names no Manifest, so no Dependabot manifest tracks it." -f $Artifact.Id)
        continue
    }

    $ManifestPath = Join-Path $RepositoryRoot $Artifact.Manifest
    if (-not $ManifestVersions.ContainsKey($Artifact.Manifest)) {
        $ManifestVersions[$Artifact.Manifest] = Get-ManifestVersion -ManifestPath $ManifestPath
    }
    $Declared = $ManifestVersions[$Artifact.Manifest]

    if (-not $Declared.ContainsKey($Artifact.PackageId)) {
        Add-Problem ("Artefact '{0}' claims to be tracked by '{1}', but that manifest has no PackageReference for '{2}'. Without one it gets no Dependabot alerts." -f $Artifact.Id, $Artifact.Manifest, $Artifact.PackageId)
    }
    elseif ($Declared[$Artifact.PackageId] -ne $Artifact.Version) {
        Add-Drift ("Artefact '{0}' is pinned at version '{1}' but '{2}' declares '{3}'. Run Build/Update-DependencyLock.ps1 -Refresh." -f $Artifact.Id, $Artifact.Version, $Artifact.Manifest, $Declared[$Artifact.PackageId])
    }
}

# Every -ArtifactId the module asks for has to exist here, otherwise that download would fail closed
# at runtime instead of at build time.
$KnownIds = @($Artifacts | ForEach-Object { $_.Id })
$PrivatePath = Join-Path $RepositoryRoot "OmadaWeb.PS" | Join-Path -ChildPath "Private"
foreach ($Source in (Get-ChildItem -Path $PrivatePath -Filter "*.ps1" -File)) {
    $Content = Get-Content -Path $Source.FullName -Raw
    foreach ($Match in ([regex]'-ArtifactId\s+"([^"]+)"').Matches($Content)) {
        $RequestedId = $Match.Groups[1].Value
        if ($KnownIds -notcontains $RequestedId) {
            Add-Problem ("{0} downloads artefact '{1}', which has no entry in the lock file." -f $Source.Name, $RequestedId)
        }
    }
}

foreach ($Artifact in $Artifacts) {
    $InstallerPath = Join-Path $PrivatePath ("{0}.ps1" -f $Artifact.InstalledBy)
    if (-not (Test-Path $InstallerPath -PathType Leaf)) {
        Add-Problem ("Artefact '{0}' names installer '{1}', which does not exist." -f $Artifact.Id, $Artifact.InstalledBy)
    }
}

# The SBOM reports the versions the module actually downloads, so it is a third file that has to move
# with a bump - and the one nothing used to update. Left unchecked it goes stale silently and the
# module ships an inventory that disagrees with what it loads.
$InventoryComponents = Get-InventoryComponent -Path $InventoryPath
foreach ($Artifact in ($Artifacts | Where-Object { $_.Verification -eq "Sha256" })) {
    if (-not $InventoryComponents.ContainsKey($Artifact.Id)) {
        continue
    }

    $Component = $InventoryComponents[$Artifact.Id]
    if ($Component.Version -ne $Artifact.Version) {
        Add-Drift ("Artefact '{0}' is pinned at version '{1}' but the SBOM component '{2}' in '{3}' reports '{4}'. Run Build/Update-DependencyLock.ps1 -Refresh." -f $Artifact.Id, $Artifact.Version, $Component.Name, $InventoryPath, $Component.Version)
    }
}

# Members of the System.Text.Json closure cannot be upgraded one at a time - Assembly.LoadFrom applies
# no binding redirects, so the versions loaded have to be the ones the pinned System.Text.Json
# resolves. .github/dependabot.yml therefore carries an ignore rule for each of them. Asserting that
# here is what stops the two from drifting: adding a closure member to this lock without ignoring it
# fails the build, instead of producing a pull request that can never go green.
$IgnoredNames = Get-IgnoredDependencyName -ConfigPath $DependabotConfigPath -Directory "/Build/Dependencies"
foreach ($Artifact in ($Artifacts | Where-Object { $_.Group -eq "SystemTextJson" })) {
    if ($IgnoredNames -notcontains $Artifact.PackageId) {
        Add-Problem ("Artefact '{0}' belongs to the System.Text.Json closure, but '{1}' has no ignore rule for '{2}'. Dependabot would propose bumping it on its own, which is not an update this module can take." -f $Artifact.Id, $DependabotConfigPath, $Artifact.PackageId)
    }
}

#endregion

#region network checks and refresh

if ($PSCmdlet.ParameterSetName -eq "Refresh") {
    $Line = @(Get-Content -Path $LockPath)

    # A missing inventory was already reported as a problem by the offline checks, which makes the run
    # fail at the end with that message. Reading it unguarded here would pre-empt that with a bare
    # file-not-found instead.
    $InventoryLine = @()
    if (Test-Path $InventoryPath -PathType Leaf) {
        $InventoryLine = @(Get-Content -Path $InventoryPath)
    }

    $Changed = 0
    $InventoryChanged = 0

    foreach ($Artifact in ($Artifacts | Where-Object { $_.Verification -eq "Sha256" })) {
        # The offline checks above already parsed every manifest once, keyed by its relative path.
        $Declared = @{}
        if ($ManifestVersions.ContainsKey($Artifact.Manifest)) {
            $Declared = $ManifestVersions[$Artifact.Manifest]
        }

        $Version = $Artifact.Version
        if ($Declared.ContainsKey($Artifact.PackageId)) {
            $Version = $Declared[$Artifact.PackageId]
        }

        $Url = Get-FlatContainerUrl -PackageId $Artifact.PackageId -Version $Version
        $Sha256 = Get-RemoteSha256 -Url $Url

        # The SBOM can be stale even when the pin is not - it was never refreshed before this - so it
        # is reconciled against the version on every run, not only when the lock file moves.
        if ($InventoryComponents.ContainsKey($Artifact.Id) -and $InventoryComponents[$Artifact.Id].Version -ne $Version) {
            "  {0}: SBOM {1} -> {2}" -f $Artifact.Id, $InventoryComponents[$Artifact.Id].Version, $Version | Write-Host -ForegroundColor Yellow
            $InventoryLine = Set-InventoryVersion -Line $InventoryLine -LockId $Artifact.Id -Version $Version
            $InventoryChanged++
        }

        if ($Version -eq $Artifact.Version -and $Url -eq $Artifact.Url -and $Sha256 -eq $Artifact.Sha256) {
            "  {0} {1} unchanged" -f $Artifact.Id, $Version | Write-Host
            continue
        }

        "  {0}: {1} -> {2}" -f $Artifact.Id, $Artifact.Version, $Version | Write-Host -ForegroundColor Yellow
        "    sha256 {0} -> {1}" -f $Artifact.Sha256, $Sha256 | Write-Host -ForegroundColor Yellow
        $Line = Set-ArtifactValue -Line $Line -Id $Artifact.Id -Value @{
            Version = $Version
            Url     = $Url
            Sha256  = $Sha256
        }
        $Changed++
    }

    # Written without a BOM and with CRLF, matching the rest of the repository.
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    if ($Changed -gt 0) {
        [System.IO.File]::WriteAllText($LockPath, (($Line -join "`r`n") + "`r`n"), $Utf8NoBom)
        "Updated {0} artefact(s) in '{1}'." -f $Changed, $LockPath | Write-Host -ForegroundColor Green
    }

    if ($InventoryChanged -gt 0) {
        [System.IO.File]::WriteAllText($InventoryPath, (($InventoryLine -join "`r`n") + "`r`n"), $Utf8NoBom)
        "Updated {0} component(s) in '{1}'." -f $InventoryChanged, $InventoryPath | Write-Host -ForegroundColor Green
    }

    # Only claim everything agrees when nothing was reported; otherwise this line would sit directly
    # above the failure and contradict it.
    if ($Changed -eq 0 -and $InventoryChanged -eq 0 -and $Problems.Count -eq 0) {
        "No changes; every pin already matches its manifest, its published bytes and the SBOM." | Write-Host -ForegroundColor Green
    }
}
elseif (-not $SkipDownload) {
    foreach ($Artifact in ($Artifacts | Where-Object { $_.Verification -eq "Sha256" })) {
        $Actual = Get-RemoteSha256 -Url $Artifact.Url
        if ($Actual -ne $Artifact.Sha256) {
            Add-Problem ("Artefact '{0}' no longer matches what '{1}' serves.`r`n    Pinned: {2}`r`n    Actual: {3}" -f $Artifact.Id, $Artifact.Url, $Artifact.Sha256, $Actual)
        }
        else {
            "  {0} {1} OK" -f $Artifact.Id, $Artifact.Version | Write-Host
        }
    }
}

#endregion

if ($Problems.Count -gt 0) {
    "" | Write-Host
    "{0} problem(s) found in the dependency lock." -f $Problems.Count | Write-Error -ErrorAction Stop
}

"Dependency lock is consistent." | Write-Host -ForegroundColor Green
