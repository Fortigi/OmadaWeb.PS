function Test-WebView2NavigationReady {
    [CmdletBinding()]
    PARAM(
        [parameter(Mandatory = $true)]
        $SessionContext,

        [AllowNull()]
        $Source
    )

    # Navigation to the sign-in page is only safe once the WebView2 control is still on its initial
    # blank page and no ClearBrowsingDataAsync call is still in flight for this session. A clear that
    # was never scheduled, or one that already finished or failed, leaves BrowserDataClearPending
    # false, so this is ready immediately in both of those cases - only an in-progress clear blocks it.
    return ($Source -eq "about:blank") -and (-not $SessionContext.BrowserDataClearPending)
}
