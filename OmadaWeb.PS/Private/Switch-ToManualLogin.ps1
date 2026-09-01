function Switch-ToManualLogin {
    <#
    .SYNOPSIS
        Stops credential autofill, explains why, and leaves the sign-in to the user.

    .DESCRIPTION
        The Microsoft sign-in automation recognizes pages by hardcoded Entra element IDs. Microsoft
        changes that markup without notice, and when it does no scenario matches any more. Failing
        the request at that point would be wrong: the browser window is open and visible, and for
        every tenant that is not on Entra typing the credentials there is the normal sign-in path
        anyway. So a selector break degrades autofill, not login.

        This function is the single place that makes that switch. It clears the flag the WebView2
        timer and the Edge WebDriver poll loop use to decide whether to drive the page, and prints a
        diagnostic naming the state, the selectors that were expected but absent, and the page the
        browser is on - the three things needed to fix the selector table afterwards.

        Not every handover is a selector break, though, and saying so when it is not is worse than
        saying nothing. -Cause names which of three things happened, and only the wording follows
        from it - the switch itself is made the same way in all three cases:

          - UnrecognizedScreen. The page matched no known sign-in step. This is the case the
            function was written for: the markup is the suspect, the missing selectors are the
            evidence, and a bug report is the fix.
          - UnrecognizedCode. Entra ID named an error this module has no entry for. The page was
            read perfectly well, so no selector is to blame, none is reported, and the markup is
            not accused of anything - but the code itself is worth reporting, so the request to do
            so stays. That request is the whole reason this differs from RecognizedCondition.
          - RecognizedCondition. Entra ID named something this module knows and cannot answer on
            the user's behalf, such as a request to pick an account. Nothing is broken, nothing is
            missing, and asking for a bug report would send a user to the issue tracker for a
            normal day at work (issue #76).

        Only the path of the page URL is reported. Sign-in URLs carry client_id, state and nonce
        query parameters, and this text is written to a stream that users routinely capture into
        support logs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$State,

        [AllowNull()]
        [string[]]$MissingElementId,

        [AllowNull()]
        [string[]]$FoundElementId,

        [AllowNull()]
        [string]$Url,

        [AllowNull()]
        [string]$Reason,

        [ValidateSet("UnrecognizedScreen", "UnrecognizedCode", "RecognizedCondition")]
        [string]$Cause = "UnrecognizedScreen"
    )

    if ($Script:ManualLoginFallbackActive) {
        # The timer ticks every 150 ms and the WebDriver loop every 500 ms, so the guard is what
        # keeps this a diagnostic instead of a flood.
        "Manual login fallback is already active - not reporting again" | Write-Verbose
        return $false
    }

    $Script:ManualLoginFallbackActive = $true
    $Script:MicrosoftOnlineLogin = $false
    $Script:LoginSubState = $null
    $Script:LoginTask = $null

    $PageAddress = "unknown"
    if (-not [string]::IsNullOrWhiteSpace($Url)) {
        try {
            $PageAddress = ([System.Uri]::New($Url)).GetLeftPart([System.UriPartial]::Path)
        }
        catch {
            $PageAddress = Protect-LogMessage -Message $Url
        }
    }

    # Not every caller knows which selector is to blame - a script exception carries a reason but no
    # element - so a handover that blames the markup has to say "unknown", not something the reader
    # would act on. When the page reported its own error there is no selector to name at all, and
    # printing "unknown" there invents a failure that did not happen: the line is left out instead.
    $NamedMissingElementId = @($MissingElementId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $MissingText = $null
    if ($NamedMissingElementId.Count -gt 0) {
        $MissingText = $NamedMissingElementId -join ", "
    }
    elseif ($Cause -eq "UnrecognizedScreen") {
        $MissingText = "unknown"
    }

    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add("Automated Microsoft sign-in could not continue - handing control back to you.")
    $Lines.Add("  State            : {0}" -f $State)
    if (-not [string]::IsNullOrWhiteSpace($MissingText)) {
        $Lines.Add("  Missing elements : {0}" -f $MissingText)
    }

    $NamedFoundElementId = @($FoundElementId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($NamedFoundElementId.Count -gt 0) {
        $Lines.Add("  Elements present : {0}" -f ($NamedFoundElementId -join ", "))
    }

    $Lines.Add("  Page URL         : {0}" -f $PageAddress)
    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        $Lines.Add("  Reason           : {0}" -f (Protect-LogMessage -Message $Reason))
    }

    switch ($Cause) {
        "RecognizedCondition" {
            # Entra ID said what it wants and this module knows what that means. Claiming the page
            # had changed would be false, and asking for a bug report would be asking a user to
            # report a sign-in working as designed.
            $Lines.Add("Entra ID asked for something that only you can do. Please sign in yourself in the browser window that is open - nothing about the page is broken, and there is nothing to report.")
        }

        "UnrecognizedCode" {
            # The page was read and understood; it is the code that is new. Blaming the markup would
            # send a reader to the selector table, which is the one place the answer is not - but
            # the code itself is worth reporting, because that is how it gets an entry.
            $Lines.Add("Entra ID reported an error code this module has no entry for. Please sign in yourself in the browser window that is open - only filling in your credentials automatically stopped working, signing in did not. Please report the details above at https://github.com/Fortigi/OmadaWeb.PS/issues.")
        }

        default {
            $Lines.Add("The sign-in page no longer matches what this module knows about it, which usually means Microsoft changed it. Please sign in yourself in the browser window that is open - only filling in your credentials automatically stopped working, signing in did not. Please report the details above at https://github.com/Fortigi/OmadaWeb.PS/issues.")
        }
    }

    ($Lines -join [System.Environment]::NewLine) | Write-Warning

    if (-not [string]::IsNullOrWhiteSpace($Url)) {
        "Switch-ToManualLogin - Full page URL: {0}" -f (Protect-LogMessage -Message $Url) | Write-Verbose
    }

    return $true
}
