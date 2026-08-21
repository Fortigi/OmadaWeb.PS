PARAM(
    [string]$SystemDefaultWorkingDirectory,
    [string]$PsGalleryKey,
    [string]$BuildPath,
    [string]$Prerelease = ""
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls13

try {
    "Folder tree for SystemDefaultWorkingDirectory:" | Write-Host
    Get-ChildItem "$SystemDefaultWorkingDirectory" -Recurse | ForEach-Object { Write-Host $_.FullName }
}
catch {
    Write-Host "Failed to retrieve directory tree: $_"
}

try {
    "Publish-Module to PSGallery" | Write-Host
    $SourcePath = "{0}/buildoutput/{1}" -f $SystemDefaultWorkingDirectory, $BuildPath.TrimStart('/')

    if (-not [string]::IsNullOrWhiteSpace($Prerelease)) {
        $ManifestPath = Join-Path -Path $SourcePath -ChildPath ("{0}.psd1" -f (Split-Path -Leaf $BuildPath))
        if (-not (Test-Path -LiteralPath $ManifestPath)) {
            throw "Module manifest '$ManifestPath' not found."
        }

        $ManifestData = Import-PowerShellDataFile -Path $ManifestPath -ErrorAction Stop
        # PSGallery requires exactly 3-part version for pre-release packages (SemVer).
        # Drop the 4th part (run number) — it is already encoded in the Prerelease string
        # (e.g. 'nightly15'), giving a final version like 2026.7.3-nightly15.
        $Parts = "$($ManifestData.ModuleVersion)" -split '\.'
        if ($Parts.Count -eq 4) {
            $ThreePartVersion = '{0}.{1}.{2}' -f $Parts[0], $Parts[1], $Parts[2]
            "Converting version $($ManifestData.ModuleVersion) to 3-part prerelease version $ThreePartVersion" | Write-Host
            Update-ModuleManifest -Path $ManifestPath -ModuleVersion $ThreePartVersion -Prerelease $Prerelease -ErrorAction Stop
        }
        elseif ($Parts.Count -eq 3) {
            "Setting prerelease string '$Prerelease' on $(Split-Path -Leaf $ManifestPath)" | Write-Host
            Update-ModuleManifest -Path $ManifestPath -Prerelease $Prerelease -ErrorAction Stop
        }
        else {
            throw "Unexpected ModuleVersion '$($ManifestData.ModuleVersion)' in '$ManifestPath'."
        }
    }

    Publish-Module -Path $SourcePath -NuGetApiKey "$PsGalleryKey" -Verbose
}
catch {
    Write-Error "Failed to deploy to PowerShell Gallery: $_"
    exit 1
}




