function Invoke-WebView2Command {
    <#
    .SYNOPSIS
    Invoke commands for WebView2 operations.
    #>

    [CmdletBinding()]
    param(
        [scriptblock]$ScriptBlock
    )
    try {
        "{0} - {1}" -f $MyInvocation.MyCommand, (Get-PSCallStack)[1].FunctionName | Write-Verbose

        return $Script:Task.GetAwaiter().OnCompleted($ScriptBlock)
    }
    catch {
        Write-Host "Error in Invoke-WebView2Command: $_" -ForegroundColor Red
        throw
    }
}