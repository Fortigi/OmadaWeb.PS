function Send-WebView2Command {
    <#
    .SYNOPSIS
    Sends a command to the WebView2 helper application.

    .PARAMETER Action
    The action to perform.

    .PARAMETER Parameters
    Parameters for the action.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Action,

        [hashtable]$Parameters = @{}
    )

    try {
        if (-not $Script:WebViewHelperProcess -or $Script:WebViewHelperProcess.HasExited) {
            throw "WebView2 helper process not running"
        }

        $command = @{
            action = $Action
            parameters = $Parameters
        }

        $commandJson = ConvertTo-Json $command -Depth 10 -Compress
        "Sending command: {0}" -f $commandJson | Write-Verbose

        $Script:WebViewHelperProcess.StandardInput.WriteLine($commandJson)
        $Script:WebViewHelperProcess.StandardInput.Flush()

        $responseJson = $Script:WebViewHelperProcess.StandardOutput.ReadLine()
        "Received response: {0}" -f $responseJson | Write-Verbose

        $response = ConvertFrom-Json $responseJson
        return $response
    }
    catch {
        "Failed to send WebView2 command: {0}" -f $_.Exception.Message | Write-Error
        throw
    }
}