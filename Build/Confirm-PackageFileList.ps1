#Requires -Version 5.1

<#
.SYNOPSIS
    Checks that every file the module manifest declares is actually in the built package.
.DESCRIPTION
    The manifest's FileList is a promise about what the package contains, and several things later in
    the pipeline believe it. Update-ModuleManifest - which PushToPsGallery.ps1 runs to stamp a
    prerelease version - validates each entry against the file system and refuses to write the
    manifest when one is missing. nuget pack fails on a <file> pattern that matches nothing.

    Both of those happen minutes after the package was produced, in a different job, with an error
    that describes the manifest rather than the build step that left the file out. This script moves
    that discovery to the moment the package is created.

    It is not a substitute for the tests: it is deliberately cheap and dependency-free so it can run
    at the end of every build, including the ones that skip the test suite.
.PARAMETER PackagePath
    The built module folder to check. Defaults to buildoutput\OmadaWeb.PS next to this script.
.PARAMETER ManifestPath
    The manifest to read FileList from. Defaults to the .psd1 inside PackagePath.
.EXAMPLE
    ./Build/Confirm-PackageFileList.ps1

    Verifies the package in buildoutput and fails when anything the manifest declares is absent.
#>
[CmdletBinding()]
param(
    [parameter(Mandatory = $false)]
    [string]$PackagePath = (Join-Path $PSScriptRoot ".." | Join-Path -ChildPath "buildoutput" | Join-Path -ChildPath "OmadaWeb.PS"),
    [parameter(Mandatory = $false)]
    [string]$ManifestPath
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $PackagePath -PathType Container)) {
    "Package folder '{0}' does not exist, so there is nothing to verify. Run the Build task first." -f $PackagePath | Write-Error -ErrorAction Stop
}

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $PackagePath "OmadaWeb.PS.psd1"
}

if (-not (Test-Path $ManifestPath -PathType Leaf)) {
    "Module manifest '{0}' does not exist." -f $ManifestPath | Write-Error -ErrorAction Stop
}

$Manifest = Import-PowerShellDataFile -Path $ManifestPath
# A manifest without a FileList key yields a single $null entry rather than an empty array, which
# would otherwise be reported as one missing file with a blank name.
$Declared = @($Manifest.FileList | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

if ($Declared.Count -eq 0) {
    # An empty FileList would make this check pass while proving nothing.
    "Module manifest '{0}' declares no FileList, so the package contents cannot be verified." -f $ManifestPath | Write-Error -ErrorAction Stop
}

$Missing = [System.Collections.Generic.List[string]]::new()
foreach ($Entry in $Declared) {
    # FileList entries are relative to the module root, which is the package folder.
    if (-not (Test-Path (Join-Path $PackagePath $Entry) -PathType Leaf)) {
        $Missing.Add($Entry)
    }
}

if ($Missing.Count -gt 0) {
    "The built package '{0}' is missing {1} file(s) its manifest declares in FileList:`r`n  {2}`r`nPublishing this package would fail in Update-ModuleManifest and nuget pack, so the build stops here instead. If these are the bundled WebView2 assemblies, the build step that fetches them did not run or did not complete." -f $PackagePath, $Missing.Count, ($Missing -join "`r`n  ") | Write-Error -ErrorAction Stop
}

"Package contents match the manifest: {0} file(s) declared and present." -f $Declared.Count | Write-Host -ForegroundColor Green
