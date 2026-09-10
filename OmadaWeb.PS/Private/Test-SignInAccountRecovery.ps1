function Test-SignInAccountRecovery {
    <#
    .SYNOPSIS
        Decides whether a refused sign-in is worth one more window with the account picker on it.

    .DESCRIPTION
        A sign-in refused because the account is not known in the application's tenant is final for
        that account and only for that account. Somebody else - the same person's guest identity in
        that tenant, or a different account entirely - signs in perfectly well, and the browser is
        still open in front of the user when the refusal arrives. Ending the call there is correct
        and useless: it tells a person who is sitting at a browser to go and run the command again.

        So the WebView2 driver is allowed exactly one more attempt, with prompt=select_account on the
        request, and this function is the rule for when that is the right thing to do. It is kept out
        of the driver so it can be read, tested and argued with on its own.

        Four things all have to hold:

          - The refusal is a WrongAccount one. Every other category answers every account the same
            way, so another window is another way of spending somebody's time.
          - No account was named by the caller. -UserName and -Credential are answers to exactly the
            question the picker asks, and re-asking it would override what the caller already said -
            when the account they named is the one the tenant rejected, the picker cannot help.
          - Nothing has been tried yet for this call. One recovery, never two: a second refusal is
            the tenant saying the same thing again, and a browser window that keeps reappearing is
            worse than an error message.
          - Somebody is there to answer. An account picker in a session with no interactive desktop
            is a window nobody will ever click, and the call would hang where it used to fail with a
            message. The check is Environment.UserInteractive, which is false exactly where that is
            true - a service, a session-0 scheduled task.

    .PARAMETER Category
        The refusal category recorded by Stop-OmadaLogin.

    .PARAMETER UserName
        The account the caller named, if any.

    .PARAMETER RecoveryAttempted
        Whether this sign-in has already had its one attempt.

    .PARAMETER UserInteractive
        Whether there is a desktop session to show a picker in. Defaults to the process's own answer;
        it is a parameter so the rule can be tested without one.

    .OUTPUTS
        System.Boolean.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Category,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$UserName,

        [switch]$RecoveryAttempted,

        [bool]$UserInteractive = [System.Environment]::UserInteractive
    )

    if ($Category -ne "WrongAccount") {
        return $false
    }

    if ($RecoveryAttempted) {
        "{0} - The sign-in has already been offered an account picker once, so the refusal stands." -f $MyInvocation.MyCommand | Write-Verbose
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($UserName)) {
        "{0} - The account was named by the caller, so the refusal is about that account and an account picker cannot answer it." -f $MyInvocation.MyCommand | Write-Verbose
        return $false
    }

    if (-not $UserInteractive) {
        "{0} - There is no interactive desktop to show an account picker in, so the refusal stands." -f $MyInvocation.MyCommand | Write-Verbose
        return $false
    }

    return $true
}
