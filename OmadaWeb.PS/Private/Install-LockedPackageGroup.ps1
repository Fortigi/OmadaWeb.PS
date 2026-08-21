function Install-LockedPackageGroup {
    [CmdletBinding()]
    PARAM(
        [parameter(Mandatory = $true)]
        [string]$Group,
        [parameter(Mandatory = $true)]
        [string]$PrimaryDllFileName
    )

    # A package and every dependency it needs on .NET Framework are pinned together as one group in
    # the lock file, so the whole closure is downloaded from pinned URLs and hash-verified instead of
    # being resolved from the NuGet dependency graph at runtime. Start-EdgeDriver loads every DLL
    # that lands in this folder, which is why they all have to be verified.
    $Destination = Split-Path $Script:WebDriverPath
    $null = New-Item $Destination -ItemType Directory -Force

    $CheckJsonLibrary = $false

    foreach ($Artifact in (Get-LockedArtifact -Group $Group)) {
        "Retrieving '{0}' version {1}" -f $Artifact.PackageId, $Artifact.Version | Write-Verbose

        $TempFile = Invoke-DownloadFile -ArtifactId $Artifact.Id
        $PackagePath = Expand-DownloadFile -FilePath $TempFile

        try {
            $LibraryFolder = Get-NuGetLibraryFolder -PackagePath $($PackagePath.FullName) -TargetFramework $Artifact.TargetFramework
            Get-ChildItem $($LibraryFolder.FullName) -Filter "*.dll" | Copy-Item -Destination $Destination -Force

            if ($LibraryFolder.Name -eq "netstandard2.0" -and ((Get-ChildItem $($LibraryFolder.FullName) -Filter $PrimaryDllFileName | Measure-Object).Count -gt 0)) {
                $CheckJsonLibrary = $true
            }
        }
        finally {
            Remove-Item $($PackagePath.FullName) -Force -Confirm:$false -Recurse -ErrorAction SilentlyContinue
        }
    }

    return $CheckJsonLibrary
}
