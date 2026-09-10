function Get-DataFromWebView2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $SessionContext,

        [string]$EdgeProfile = "Default",
        [switch]$InPrivate
    )

    # Read before anything can throw, because the finally block below puts it back. The recovery
    # further down turns the account picker on for the session it is repairing, and leaving it on
    # afterwards would make every later sign-in of that session stop and ask - including the ones
    # that are working. Assigning it inside the try would mean a failure in the first statement of
    # that block ended in an unset-variable error from the handler instead of the real one.
    $SelectAccountBeforeRecovery = $SessionContext.SelectAccount

    try {
        "{0} - Invoking data from WebView2" -f $MyInvocation.MyCommand | Write-Verbose

        if (!(Install-WebView2)) {
            "WebView2 Runtime could not be installed! Cannot continue." | Write-Error -ErrorAction "Stop"
        }

        # The blocking WinForm/WebView2 dialog and its event-handler closures cannot see this call
        # stack, so the session driving this login is bridged through this script-scope pointer.
        $Script:CurrentWebView2Session = $SessionContext
        $Script:CurrentWebView2Session.LoginRetryCount = 0

        # One allowance per sign-in, not per PowerShell session: a call made an hour later deserves
        # the same offer of an account picker as this one.
        $Script:CurrentWebView2Session.AccountRecoveryAttempted = $false

        # A new sign-in gets a fresh attempt at autofill, whatever happened during the previous one.
        # Every window opened from here resets it again - see Initialize-WebView2.
        Reset-LoginAutomationState

        # Cleared here rather than in Reset-LoginAutomationState: a refused sign-in closes its own
        # window, and this has to outlive that or the loop below would open the next one.
        $Script:LoginAbortReason = $null

        Add-ReflectionAssembly -Object $Script:WebView2CorePath
        Add-ReflectionAssembly -Object $Script:WebView2WinFormsPath
        Add-ReflectionAssembly -Object "System.Drawing" -Type LoadWithPartialName
        Add-ReflectionAssembly -Object "System.Windows.Forms" -Type LoadWithPartialName
        do {
            try {
                $Script:CurrentWebView2Session.LoginRetryCount++

                if ($Script:StopError) {
                    $Script:CurrentWebView2Session.LoginRetryCount = 0
                    break
                }

                # The previous window closed because the sign-in was refused - by the identity
                # provider, or by Omada itself - and not because it timed out. Another window would
                # travel the same redirect chain and land on the same error page, so stop here and
                # report what that page said.
                if ($null -ne $Script:LoginAbortReason) {
                    # Unless the refusal was about which account signed in, in which case another
                    # window is not the same window: it carries prompt=select_account, so Entra ID
                    # asks instead of choosing, and the person who is already sitting in front of the
                    # browser can pick the account that does work. Test-SignInAccountRecovery holds
                    # the whole rule for when that is worth doing.
                    if (Test-SignInAccountRecovery -Category $Script:LoginAbortReason.Category -UserName $Script:CurrentWebView2Session.UserName -RecoveryAttempted:$Script:CurrentWebView2Session.AccountRecoveryAttempted) {
                        $Tenant = "this tenant"
                        if ($null -ne $Script:LoginAbortReason.Detail -and -not [string]::IsNullOrWhiteSpace($Script:LoginAbortReason.Detail.ResourceTenant)) {
                            $Tenant = "tenant '{0}'" -f $Script:LoginAbortReason.Detail.ResourceTenant
                        }

                        "The account the browser signed in with is not known in {0}. Opening the sign-in window once more, this time asking which account to use - please choose one that exists in that tenant." -f $Tenant | Write-Warning

                        $Script:CurrentWebView2Session.AccountRecoveryAttempted = $true
                        $Script:CurrentWebView2Session.SelectAccount = $true

                        # Deliberately not paired with a browsing-data clear. prompt=select_account
                        # already stops Entra ID answering from the session it holds, and clearing
                        # cookies underneath a sign-in that is starting is what produced AADSTS50058
                        # in the canary (see the note in Tests/E2E/EntraSignInCanary.Tests.ps1). The
                        # cheaper of the two also keeps the user's multi-factor state, so the account
                        # they pick is not made to prove itself from scratch.

                        # Cleared so the drivers stop reading it as "this sign-in is over", and the
                        # count is put back to the first attempt so the new window opens at once
                        # rather than after the two-second pause a timed-out window earns.
                        $Script:LoginAbortReason = $null
                        $Script:CurrentWebView2Session.LoginRetryCount = 1
                    }
                    else {
                        $Script:CurrentWebView2Session.LoginRetryCount = 0
                        break
                    }
                }

                if ($Script:CurrentWebView2Session.LoginRetryCount -gt 3) {
                    "`nLogin try count exceeded! Cannot continue!" | Write-Error -ErrorAction "Stop" -Category AuthenticationError
                }

                "`n{0} - Login try {1} of max {2}" -f $MyInvocation.MyCommand, $Script:CurrentWebView2Session.LoginRetryCount, $Script:MaxLoginRetries | Write-Verbose

                if ($null -eq $Script:CurrentWebView2Session.AuthCookie -or ($Script:CurrentWebView2Session.AuthCookie -is [PSCustomObject] -and ($Script:CurrentWebView2Session.AuthCookie.PsObject.Properties | Measure-Object).Count -eq 0)) {
                    if ($Script:CurrentWebView2Session.LoginRetryCount -le 1) {
                        try {
                            Start-WebView2Login -EdgeProfile $EdgeProfile -InPrivate:$InPrivate
                        }
                        catch {
                            $PSCmdlet.ThrowTerminatingError($PSItem)
                        }
                    }
                    else {
                        "`nWebView2 was unable to complete the process to retrieve a cookie. Re-open WebView2 in 2 seconds!" | Write-Host -ForegroundColor Yellow
                        Start-Sleep -Seconds 2
                        "`n{0} - Login try count: {1}" -f $MyInvocation.MyCommand, $Script:CurrentWebView2Session.LoginRetryCount | Write-Verbose
                        try {
                            Start-WebView2Login -EdgeProfile $EdgeProfile -InPrivate:$InPrivate
                        }
                        catch {
                            $PSCmdlet.ThrowTerminatingError($PSItem)
                        }
                    }
                }
                else {
                    "{0} - Existing authentication cookie found" -f $MyInvocation.MyCommand | Write-Verbose
                }
            }
            catch {
                $PSCmdlet.ThrowTerminatingError($PSItem)
            }
        }
        until(($null -ne $Script:CurrentWebView2Session.AuthCookie -and ($Script:CurrentWebView2Session.AuthCookie -is [PSCustomObject] -and ($Script:CurrentWebView2Session.AuthCookie.PsObject.Properties | Measure-Object).Count -gt 0)) -or $Script:CurrentWebView2Session.LoginRetryCount -ge 3)

        if ($null -ne $Script:CurrentWebView2Session.AuthCookie -and ($Script:CurrentWebView2Session.AuthCookie -is [PSCustomObject] -and ($Script:CurrentWebView2Session.AuthCookie.PsObject.Properties | Measure-Object).Count -gt 0)) {
            $Script:CurrentWebView2Session.LoginRetryCount = 0
        }
        elseif ($null -ne $Script:LoginAbortReason) {
            # "Could not authenticate" is true but useless here: the page named the account, the
            # tenant and the error code, and that is what the user needs to act on.
            $AbortMessage = "Could not authenticate to '{0}': {1}" -f $Script:CurrentWebView2Session.BaseUrl, $Script:LoginAbortReason.Message
            if (-not [string]::IsNullOrWhiteSpace($Script:LoginAbortReason.Reason)) {
                $AbortMessage = "{0} ({1})" -f $AbortMessage, $Script:LoginAbortReason.Reason
            }
            $AbortMessage | Write-Error -ErrorAction "Stop" -Category AuthenticationError
        }
        else {
            "Could not authenticate to '{0}'" -f $Script:CurrentWebView2Session.BaseUrl | Write-Error -ErrorAction "Stop"
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
    finally {
        # The account picker belongs to the recovery, not to the session. Put it back however this
        # call ended - the caller's own -SelectAccount, if they passed one, survives.
        if ($null -ne $SessionContext) {
            $SessionContext.SelectAccount = $SelectAccountBeforeRecovery
        }

        $Script:CurrentWebView2Session = $null
    }
}
