function Show-EntraApprovalNumber {
    <#
    .SYNOPSIS
        Tells the user which number to match in their authenticator app, and then keeps saying that
        the sign-in is still waiting for them.

    .DESCRIPTION
        Two Entra ID screens show a number the user has to match on their phone: passwordless sign-in
        and Authenticator number match. They are different elements on different screens but the same
        thing to the person in front of them, so both arrive here.

        When Phone Link is running the number is put on the clipboard as well, because the phone can
        then be driven from the same desktop and the value pasted straight into the app.

        The rest of this exists because of what happens next: nothing, for a long time. Approving a
        request takes as long as it takes someone to pick up their phone, unlock it and read - a
        minute is unremarkable and several are possible. The window looks frozen for all of it, which
        is one of the silent stalls issue #18 is about, and it is also why Test-LoginAutomationStalled
        is told not to count this as a page that stopped making progress. So the wait reports itself
        every $Script:MfaWaitReportInterval seconds instead of going quiet - often enough to show
        that something is still happening, rarely enough not to fill the verbose stream from a timer
        that ticks every 150 ms.

    .PARAMETER Number
        The number read off the page.

    .OUTPUTS
        System.Boolean. True when this call showed the number for the first time, false while the
        sign-in is merely still waiting to be approved.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Number
    )

    if ([string]::IsNullOrWhiteSpace($Number)) {
        return $false
    }

    if ($Script:MfaRequestDisplayed) {
        if ($null -eq $Script:MfaWaitLastReported -or ([DateTime]::Now - $Script:MfaWaitLastReported).TotalSeconds -ge $Script:MfaWaitReportInterval) {
            $Script:MfaWaitLastReported = [DateTime]::Now
            "Show-EntraApprovalNumber - Still waiting for sign-in request {0} to be approved" -f $Number | Write-Verbose
        }

        return $false
    }

    $Message = "`nWaiting for you to approve this sign-in request"

    $PhoneLinkActive = (Get-Process | Where-Object { $_.ProcessName -eq "PhoneExperienceHost" } | Measure-Object).Count -gt 0
    if ($PhoneLinkActive) {
        try {
            $Number | Set-Clipboard
            $Message = "{0}: {1} (This value is now in your clipboard so you can paste it into your Authenticator app using PhoneLink)." -f $Message, $Number
        }
        catch {
            # The number is the part that matters; failing to reach the clipboard must not cost the
            # user the one piece of information they need.
            $Message = "{0}: {1} (The clipboard could not be set: {2})." -f $Message, $Number, $_.Exception.Message
        }
    }
    else {
        $Message = "{0}: {1}" -f $Message, $Number
    }

    $Message | Write-Host -ForegroundColor Yellow

    $Script:MfaRequestDisplayed = $true
    $Script:MfaWaitLastReported = [DateTime]::Now

    return $true
}
