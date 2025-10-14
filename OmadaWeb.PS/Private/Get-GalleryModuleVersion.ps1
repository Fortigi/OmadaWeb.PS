function Get-GalleryModuleVersion {
    [CmdletBinding()]
    param(
        [string]$ModuleName
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
