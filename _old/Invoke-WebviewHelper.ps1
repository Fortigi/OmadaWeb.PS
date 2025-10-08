function Invoke-WebView2Navigate {
    <#
    .SYNOPSIS
    Navigates the WebView2 to a specified URL.

    .PARAMETER Url
    The URL to navigate to.

    .PARAMETER WaitForCompletion
    Whether to wait for navigation completion.

    .PARAMETER Timeout
    Timeout in seconds for navigation completion.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [switch]$WaitForCompletion,

        [int]$Timeout = 30
    )

    try {
        # Navigate
        $response = Send-WebView2Command -Action "navigate" -Parameters @{ url = $Url }

        if (-not $response.Success) {
            throw "Navigation failed: $($response.Error)"
        }

        if ($WaitForCompletion) {
            $waitResponse = Send-WebView2Command -Action "waitfornavigation" -Parameters @{ timeout = ($Timeout * 1000) }

            if (-not $waitResponse.Success) {
                throw "Navigation wait failed: $($waitResponse.Error)"
            }

            # Update script variables
            $Script:WebViewCore.Source = $waitResponse.Data.url
            $Script:WebViewCore.DocumentTitle = $waitResponse.Data.title

            return $waitResponse.Data
        }

        return $response.Data
    }
    catch {
        "Failed to navigate WebView2: {0}" -f $_.Exception.Message | Write-Error
        throw
    }
}