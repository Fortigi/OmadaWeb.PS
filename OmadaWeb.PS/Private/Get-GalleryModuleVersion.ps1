function Get-GalleryModuleVersion {
    [CmdletBinding()]
    param(
        [string]$ModuleName,
        [switch]$IncludePrerelease
    )

    try {
        "{0} - Getting module version for: {1}" -f $MyInvocation.MyCommand, $ModuleName | Write-Verbose
        $ApiEndpoint = "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='{0}'" -f $ModuleName
        $Parameters = @{
            Uri             = $ApiEndpoint
            Method          = "Get"
            Headers         = @{
                "Accept" = "application/xml"
            }
            UseBasicParsing = $true
        }
        $TimeoutSec = 1
        if ($PSVersionTable.PSEdition -eq "Core") {
            $Parameters.Add("ConnectionTimeoutSeconds", $TimeoutSec)
        }
        else {
            $Parameters.Add("TimeoutSec", $TimeoutSec)
        }
        $Response = Invoke-RestMethod @Parameters

        if ($null -eq $Response) {
            return $null
        }

        # FindPackagesById() returns every package ever pushed for this id, prereleases included and
        # in no particular order. Picking the entry with the newest Published date - what this used
        # to do - answers the wrong question twice: a republished older package would win, and a
        # nightly published after the last stable release would be handed to a stable installation.
        # So the feed is reduced to the highest version of the requested channel, by comparing
        # versions rather than dates.
        $LatestVersion = $null
        foreach ($Package in $Response) {
            $VersionInfo = ConvertTo-ModuleVersionInfo -Version $Package.Properties.version
            if ($null -eq $VersionInfo) {
                continue
            }

            if ($VersionInfo.IsPrerelease -and -not $IncludePrerelease) {
                continue
            }

            if ($null -eq $LatestVersion -or (Compare-ModuleVersion -ReferenceVersion $LatestVersion -DifferenceVersion $VersionInfo.Original) -lt 0) {
                $LatestVersion = $VersionInfo.Original
            }
        }

        return $LatestVersion
    }
    catch {
        "{0} - Could not read the version of '{1}' from the PowerShell Gallery: {2}" -f $MyInvocation.MyCommand, $ModuleName, $_.Exception.Message | Write-Verbose
        return $null
    }
}
