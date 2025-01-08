function Get-GalleryModuleVersion {
    param (
        [string]$ModuleName
    )

    try {
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
