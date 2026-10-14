function Test-OmadaStaThread {
    <#
    .SYNOPSIS
        Whether this thread can host a WebView2 browser window.

    .DESCRIPTION
        WebView2 is COM underneath, and the apartment it needs is the single-threaded one. On a
        multi-threaded apartment the very first call into it - CoreWebView2Environment::CreateAsync -
        comes straight back with

            Cannot change thread mode after it is set. (0x80010106 (RPC_E_CHANGED_MODE))

        That is not an exotic state either. A PowerShell console is STA on Windows, but a background
        job is not: Start-Job runs its script in a runspace whose thread is MTA, and so does any
        runspace created without ApartmentState.STA. The sign-in then fails before a window has been
        created, with a message about thread modes and nothing about signing in - the same shape of
        failure the console-handle bug had (issue #79), and found the same way, by the scheduled
        canary reporting it as a changed Microsoft sign-in page when it was nothing of the kind
        (issue #90).

        Only MTA is refused. STA is what the browser needs, and Unknown is what a thread that has not
        yet initialized COM reports - it is free to become STA on the first call, which is exactly
        what the WebView2 call itself will do. Refusing it would fail sign-ins that work today.

    .OUTPUTS
        System.Boolean. False only when this thread is a multi-threaded apartment.

    .EXAMPLE
        if (-not (Test-OmadaStaThread)) { throw "WebView2 cannot be hosted here" }

        The shape the caller uses: the apartment is asked about before the browser is reached for.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param()

    $ApartmentState = [System.Threading.Thread]::CurrentThread.GetApartmentState()
    if ($ApartmentState -eq [System.Threading.ApartmentState]::MTA) {
        "{0} - This thread is a multi-threaded apartment, which cannot host a WebView2 browser." -f $MyInvocation.MyCommand | Write-Verbose
        return $false
    }

    return $true
}
