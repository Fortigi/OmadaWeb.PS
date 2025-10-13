function Get-GalleryModuleVersion {
    [CmdletBinding()]
    PARAM(
        [string]$ModuleName
    )

    try {
        "{0} - Getting module version for: {1}" -f $MyInvocation.MyCommand, $ModuleName | Write-Verbose
        $ApiEndpoint = "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='{0}'" -f $ModuleName
        $Response = Invoke-RestMethod -Uri $ApiEndpoint -Method Get -Headers @{
            "Accept" = "application/xml"
        } -ConnectionTimeoutSeconds 1

        if ($null -ne $Response) {
            $LatestVersion = $Response | Sort-Object updated -Descending | Select-Object -First 1
            return $LatestVersion.Properties.version
        }
        else {
            return $null
        }
    }
    catch {
        return $null
    }
}
