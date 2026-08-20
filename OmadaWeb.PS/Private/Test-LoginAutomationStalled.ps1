function Test-LoginAutomationStalled {
    <#
    .SYNOPSIS
        Reports whether the sign-in automation has stopped making progress on the current page.

    .DESCRIPTION
        Both login drivers poll: the WebView2 timer every 150 ms, the Edge WebDriver loop every
        500 ms. When the page stops matching any known scenario - or matches one whose actions no
        longer do anything - both simply keep polling, which is the stall this exists to detect.

        Progress is measured by the set of known element IDs on the page. A healthy sign-in moves to
        a different page within seconds, changing that set; the call sites additionally clear
        $Script:UnmatchedPageSince whenever they successfully click something, so a step that submits
        a page whose element IDs happen to be identical to the previous one still counts as progress.

        Waiting for the user to approve a sign-in request in their authenticator app is not a stall,
        which is what -WaitingForApproval is for.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string[]]$ElementId,

        [switch]$WaitingForApproval
    )

    if ($WaitingForApproval) {
        $Script:UnmatchedPageSignature = $null
        $Script:UnmatchedPageSince = $null
        return $false
    }

    $Signature = "<no known elements>"
    if (($ElementId | Measure-Object).Count -gt 0) {
        $Signature = ($ElementId | Sort-Object) -join ","
    }

    if ($Script:UnmatchedPageSignature -ne $Signature -or $null -eq $Script:UnmatchedPageSince) {
        $Script:UnmatchedPageSignature = $Signature
        $Script:UnmatchedPageSince = [DateTime]::Now
        return $false
    }

    $StalledSeconds = ([DateTime]::Now - $Script:UnmatchedPageSince).TotalSeconds
    if ($StalledSeconds -lt $Script:LoginAutomationFallbackTimeout) {
        return $false
    }

    "{0} - No sign-in progress for {1:N0} seconds on a page with elements: {2}" -f $MyInvocation.MyCommand, $StalledSeconds, $Signature | Write-Verbose

    return $true
}
