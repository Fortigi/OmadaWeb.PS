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
        if (-not $Script:WebView2HelperProcess -or $Script:WebView2HelperProcess.HasExited) {
            throw "WebView2 helper process not running"
        }

        $command = @{
            action = $Action
            parameters = $Parameters
        }

        $commandJson = ConvertTo-Json $command -Depth 10 -Compress
        "Sending command: {0}" -f $commandJson | Write-Verbose

        $Script:WebView2HelperProcess.StandardInput.WriteLine($commandJson)
        $Script:WebView2HelperProcess.StandardInput.Flush()

        $responseJson = $Script:WebView2HelperProcess.StandardOutput.ReadLine()
        "Received response: {0}" -f $responseJson | Write-Verbose

        $response = ConvertFrom-Json $responseJson
        return $response
    }
    catch {
        "Failed to send WebView2 command: {0}" -f $_.Exception.Message | Write-Error
        throw
    }
}