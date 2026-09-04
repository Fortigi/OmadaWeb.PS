function Write-ModuleVersionStatus {
    [CmdletBinding()]
    param(
        [string]$ModuleName,
        [System.Collections.IDictionary]$InstalledModule
    )

    # The update check is channel aware, and the two channels ask different questions. Someone on a
    # stable release wants to know about the next stable release and nothing else - a nightly that
    # happens to be the most recently published package is not an update they can act on, and
    # telling them about it is noise. Someone who deliberately installed a nightly is comparing
    # against nightlies as well, so for them a newer nightly counts, and so does a stable release
    # that has since overtaken the nightly they are running.
    $InstalledVersion = $null
    if ($InstalledModule.Contains("FullVersion")) {
        $InstalledVersion = $InstalledModule["FullVersion"]
    }

    if ([string]::IsNullOrWhiteSpace($InstalledVersion)) {
        $InstalledVersion = "{0}" -f $InstalledModule["Version"]
    }

    $InstalledVersionInfo = ConvertTo-ModuleVersionInfo -Version $InstalledVersion
    if ($null -eq $InstalledVersionInfo) {
        "The installed version '{0}' of '{1}' could not be read as a version. Skipping the update check." -f $InstalledVersion, $ModuleName | Write-Verbose
        return
    }

    $GalleryVersion = Get-GalleryModuleVersion -ModuleName $ModuleName -IncludePrerelease:$InstalledVersionInfo.IsPrerelease

    if (-not $GalleryVersion) {
        "No version of '{0}' could be read from the PowerShell Gallery. Skipping the update check." -f $ModuleName | Write-Verbose
        return
    }

    # A comparison that cannot be made is reported rather than discarded. The block this replaced
    # cast both sides to [System.Version] inside a try whose catch was empty, so a gallery version
    # carrying a prerelease tag threw, took the rest of the check down with it, and left no trace
    # beyond a record in $Error.
    $Comparison = Compare-ModuleVersion -ReferenceVersion $InstalledVersion -DifferenceVersion $GalleryVersion
    if ($null -eq $Comparison) {
        "The installed version {0} of '{1}' could not be compared with the gallery version {2}. Skipping the update check." -f $InstalledVersion, $ModuleName, $GalleryVersion | Write-Verbose
        return
    }

    if ($Comparison -lt 0) {
        "The installed version {0} of '{1}' is outdated. Latest version: {2}. Execute Update-Module {1} to update to the latest version!" -f $InstalledVersion, $ModuleName, $GalleryVersion | Write-Warning
    }
    elseif ($Comparison -eq 0) {
        "The installed version {0} of '{1}' is up-to-date." -f $InstalledVersion, $ModuleName | Write-Verbose
    }
    else {
        "The installed version {0} of '{1}' is newer than the gallery version {2}." -f $InstalledVersion, $ModuleName, $GalleryVersion | Write-Warning
    }
}
