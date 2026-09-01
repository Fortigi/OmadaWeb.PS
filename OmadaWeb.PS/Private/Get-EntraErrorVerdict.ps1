function Get-EntraErrorVerdict {
    <#
    .SYNOPSIS
        Turns an Entra ID sign-in error code into a decision about what the automation may do next.

    .DESCRIPTION
        The Entra sign-in page ships its own state in a script block - the object the page calls
        '$Config', also served as ServerData - and that object carries the failure of the last step
        as a number in 'iErrorCode' and as text in 'sErrorCode'. Those numbers are the AADSTS codes
        Microsoft's support articles are indexed by, and unlike the sentence rendered next to them
        they are identical in every language the sign-in page is served in. They are therefore the
        signal this module judges a failed step by, and the rendered message is never read.

        Three answers are possible, and the difference between them matters more than the wording:

          - Stop. The sign-in cannot succeed however many times it is attempted, so the caller hands
            this to Stop-OmadaLogin, which ends the sign-in rather than opening another window. A
            wrong password is deliberately in this group: resubmitting a credential that was just
            refused is precisely what drives an account into Entra ID smart lockout, so the module
            refuses the second attempt instead of making it.
          - Manual. The account has to do something in the browser that no stored credential can do -
            register security information, complete an extra verification step. The window is open
            and the user can finish there, so autofill steps aside through Switch-ToManualLogin
            rather than failing the request.
          - None. There is no error. A healthy page reports iErrorCode 0.

        An error code this function does not recognize is answered with Manual, not with silence:
        the list below is not, and cannot be, exhaustive, so anything unknown fails safe by handing
        the sign-in back to the user with the code named in the diagnostic. IsRecognized says which
        of the two happened, because the two deserve different words: a code that is in the list
        below has a meaning worth stating, while one that is not is worth a bug report. Nothing but
        the caller's wording depends on it - the action is Manual either way.

    .PARAMETER ErrorCode
        The value of iErrorCode, or sErrorCode, as read from the page. Accepts a number, the same
        number as a string, or a string such as 'AADSTS50126' - only the digits are used.

    .OUTPUTS
        PSCustomObject with the members IsError, Code, Numeric, Action, IsTerminal, IsRecognized
        and Reason. Action is one of 'None', 'Stop' or 'Manual'.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ErrorCode
    )

    $Verdict = [pscustomobject]@{
        IsError      = $false
        Code         = $null
        Numeric      = 0
        Action       = "None"
        IsTerminal   = $false
        IsRecognized = $false
        Reason       = $null
    }

    if ([string]::IsNullOrWhiteSpace($ErrorCode)) {
        return $Verdict
    }

    # 'AADSTS50126', '50126' and 50126 all have to arrive at the same number, and a page that reports
    # no failure at all writes 0.
    $DigitMatch = [regex]::Match($ErrorCode, '\d+')
    if (-not $DigitMatch.Success) {
        return $Verdict
    }

    [long]$Numeric = 0
    if (-not [long]::TryParse($DigitMatch.Value, [ref]$Numeric)) {
        return $Verdict
    }

    if ($Numeric -eq 0) {
        return $Verdict
    }

    $Verdict.IsError = $true
    $Verdict.Numeric = $Numeric
    $Verdict.Code = "AADSTS{0}" -f $Numeric

    # Sign-ins that no retry can turn into a success. Each of these ends the sign-in.
    $TerminalReason = @{
        50126 = "The user name or password is wrong. The credential is not sent again, because repeating a refused sign-in is what drives an account into Entra ID smart lockout."
        50053 = "The account is locked, or Entra ID smart lockout is in effect after too many failed sign-in attempts."
        50055 = "The password of this account has expired and has to be changed before the account can sign in again."
        53003 = "A Conditional Access policy blocked this sign-in. Entra ID will refuse it the same way on every attempt, so no further attempts are made."
    }

    # Sign-ins that can still succeed, but only if a person acts in the browser window. Autofill has
    # nothing left to contribute, so it steps aside instead of driving the page.
    $ManualReason = @{
        50072 = "This account has to register security information before it can sign in."
        50074 = "Entra ID requires an additional verification step that cannot be filled in from a stored credential."
        50158 = "An external security challenge has to be completed for this sign-in."
        # Not named in issue #18, but the same family and the same answer: multi-factor
        # authentication is required, or has to be enrolled in, before this account can continue.
        50076 = "Entra ID requires multi-factor authentication for this sign-in."
        50079 = "This account has to enroll in multi-factor authentication before it can sign in."

        # Issue #76. The 1600x family is not a failure of the credential at all: it is Entra ID
        # saying that it cannot settle on an account by itself. Silent single sign-on hits it
        # whenever the browser holds more than one identity, or holds one that the target tenant
        # does not know, and the answer to every one of them is the same - the person at the
        # keyboard picks an account in the window that is already open. They are listed here rather
        # than left to the catch-all below because a documented condition that this module can name
        # should never be reported as one it has never heard of.
        16000  = "Entra ID cannot continue this sign-in without a choice being made: either more than one account is signed in and none of them can be picked automatically, or the account it picked cannot be used for this application. Please choose the account to sign in with in the browser window that is open."
        16001  = "The account this sign-in selected is not one Entra ID accepts for it. Please choose another account in the browser window that is open."
        16002  = "Entra ID could not match this sign-in to any of the sessions the browser already holds. Please choose the account to sign in with in the browser window that is open."
        160021 = "Entra ID found no signed-in session for the account this sign-in asked for. Please sign in with that account in the browser window that is open."
        16003  = "The account that is signed in is not known in the tenant this application belongs to, so single sign-on cannot be used for it. Please sign in with an account of that tenant in the browser window that is open."
    }

    if ($TerminalReason.ContainsKey([int]$Numeric)) {
        $Verdict.Action = "Stop"
        $Verdict.IsTerminal = $true
        $Verdict.IsRecognized = $true
        $Verdict.Reason = $TerminalReason[[int]$Numeric]
        return $Verdict
    }

    if ($ManualReason.ContainsKey([int]$Numeric)) {
        $Verdict.Action = "Manual"
        $Verdict.IsRecognized = $true
        $Verdict.Reason = $ManualReason[[int]$Numeric]
        return $Verdict
    }

    # Unknown, so fail safe rather than guessing. Naming the code is the whole point - it is what
    # turns a support question into a searchable one.
    $Verdict.Action = "Manual"
    $Verdict.Reason = "The sign-in page reported error {0}, which this module does not recognize." -f $Verdict.Code

    return $Verdict
}
