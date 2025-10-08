function Get-WebView2PageInfo {
    <#
    .SYNOPSIS
    Gets current page information from WebView2.
    #>

    [CmdletBinding()]
    param()

    try {
        $response = Send-WebView2Command -Action "getpageinfo"

        if (-not $response.Success) {
            throw "Get page info failed: $($response.Error)"
        }

        # Update script variables
        $Script:WebViewCore.Source = $response.Data.url
        $Script:WebViewCore.DocumentTitle = $response.Data.title

        return $response.Data
    }
    catch {
        "Failed to get WebView2 page info: {0}" -f $_.Exception.Message | Write-Error
        throw
    }
}