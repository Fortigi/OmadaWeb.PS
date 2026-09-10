[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ModulePath', Justification = 'Used by Import-Module inside the Describe BeforeAll, which the analyzer does not follow into.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The canary password arrives from a GitHub environment secret as an environment variable, which is a plain string by the time this process can see it. Building the PSCredential the module takes is the only thing done with it.')]
param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1'),

    # Which of the three sign-ins to drive. They are separate runs rather than separate assertions in
    # one, because each needs its own browser window and two of them never finish - see the second
    # Describe below.
    [ValidateSet('PasswordAutofill', 'UserNameOnly', 'NoUserName')]
    [string]$Scenario = 'PasswordAutofill'
)

# The scheduled login-flow canary (roadmap E5, issue #33).
#
# WHAT THIS WATCHES
#
# One tier, and deliberately only one: Entra ID credential autofill. That is the module's only
# dependency on Microsoft's sign-in DOM, and Microsoft changes it on its own schedule. Interactive
# sign-in is IdP-agnostic and is not covered here - a tenant on Ping, Okta or ADFS reaches none of
# this code.
#
# So a red canary means "autofill needs a selector update" - a routine change to
# $Script:EntraSignInElementId in OmadaWeb.PS.psm1 - and not "login is broken". Since #52 a selector
# break degrades autofill rather than sign-in: Switch-ToManualLogin turns autofill off and hands the
# window to the user. This test exists to see that happen on a schedule instead of in front of one.
#
# WHAT IT DELIBERATELY DOES NOT WATCH
#
# MFA. An interactive approval cannot be automated, so the canary account is exempted from MFA by an
# explicit Conditional Access policy (see Build/New-EntraCanaryConfiguration.ps1). The MFA screens in
# Resolve-EntraSignInScreen are covered by unit tests against recorded page snapshots, not here.
#
# HOW IT AVOIDS TESTING A COPY OF ITSELF
#
# It drives Invoke-OmadaWebRequest, so the sign-in is worked by the shipping code path -
# Invoke-WebView2MicrosoftLogin over what Get-EntraSignInProbeScript reads and
# Resolve-EntraSignInScreen judges. Tests/E2E/Start-CanaryRelyingParty.ps1 stands in for the Omada
# host on the loopback interface, which is what removes the need for an Omada environment; see the
# header of that file for how the redirect makes the real driver engage.
#
# See docs/entra-canary.md for the tenant setup, the secrets, and what to do when this goes red.

BeforeDiscovery {
    # Read at discovery so the whole file can be skipped as configuration rather than reported as a
    # failure. A developer running the suite locally, and PR Validation, both land here.
    $Script:CanaryTenantId = $Env:OMADAWEBPS_CANARY_TENANT_ID
    $Script:CanaryClientId = $Env:OMADAWEBPS_CANARY_CLIENT_ID
    $Script:CanaryUserName = $Env:OMADAWEBPS_CANARY_USERNAME
    $Script:CanaryPassword = $Env:OMADAWEBPS_CANARY_PASSWORD

    $Script:CanaryConfigured = -not (
        [string]::IsNullOrWhiteSpace($Script:CanaryTenantId) -or
        [string]::IsNullOrWhiteSpace($Script:CanaryClientId) -or
        [string]::IsNullOrWhiteSpace($Script:CanaryUserName) -or
        [string]::IsNullOrWhiteSpace($Script:CanaryPassword)
    )

    # Read at discovery for the same reason as the configuration above: which Describe runs is a
    # property of the run, not something to decide inside one.
    $Script:RunPasswordScenario = $Script:CanaryConfigured -and $Scenario -eq 'PasswordAutofill'
    $Script:RunWaitingScenario = $Script:CanaryConfigured -and $Scenario -in @('UserNameOnly', 'NoUserName')
}

Describe 'Entra ID sign-in canary' -Tag 'E2E' -Skip:(-not $Script:RunPasswordScenario) {

    BeforeAll {
        . (Join-Path $PSScriptRoot 'Start-CanaryRelyingParty.ps1')

        Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
        Import-Module $ModulePath -Force -ErrorAction Stop

        $Port = if ([string]::IsNullOrWhiteSpace($Env:OMADAWEBPS_CANARY_PORT)) { 8400 } else { [int]$Env:OMADAWEBPS_CANARY_PORT }

        $Script:RelyingParty = Start-CanaryRelyingParty -TenantId $Env:OMADAWEBPS_CANARY_TENANT_ID -ClientId $Env:OMADAWEBPS_CANARY_CLIENT_ID -LoginHint $Env:OMADAWEBPS_CANARY_USERNAME -Port $Port

        $SecurePassword = ConvertTo-SecureString -String $Env:OMADAWEBPS_CANARY_PASSWORD -AsPlainText -Force
        $Credential = [System.Management.Automation.PSCredential]::new($Env:OMADAWEBPS_CANARY_USERNAME, $SecurePassword)

        $Script:CanaryWarning = @()
        $Script:CanaryError = $null
        $Script:CanaryResponse = $null

        # Warnings are captured by merging the warning stream into the success stream and sorting the
        # records back out, rather than with -WarningVariable. Switch-ToManualLogin emits its
        # diagnostic from a WinForms timer handler running inside the blocking ShowDialog call, not
        # from Invoke-OmadaWebRequest's own pipeline, and -WarningVariable collects only the latter.
        # A capture that quietly missed it would leave the canary reporting a failure with no reason
        # attached, which is the failure this whole exercise is meant to prevent.
        #
        # -SkipCookieCache is what makes a scheduled run mean anything: a cached cookie would satisfy
        # the request without a sign-in page ever being drawn, so the canary would go green on the
        # strength of yesterday's success. The authorization request also carries prompt=login, so
        # the screens are drawn even if a session somehow survived.
        #
        # -ForceAuthentication is deliberately NOT used, and that is not a shortcut. It makes
        # Start-WebView2Login fire ClearBrowsingDataAsync when the browser initializes, and nothing
        # sequences that clear before the first navigation - the trace of run 33699066012 shows
        # "Browsing data cleared" arriving after "Navigating to". Clearing cookies underneath a
        # sign-in already in flight is a good way to produce exactly what that run got back from
        # Entra: AADSTS50058, "the cookies used to represent the user's session were not sent".
        # The runner starts from a fresh profile every time, so there is nothing here to clear anyway.
        # The stand-in serves plain HTTP on the loopback interface, and PowerShell 7 refuses to send a
        # credential over an unencrypted connection without being told to. Guarded by version rather
        # than passed unconditionally because the parameter does not exist on Windows PowerShell 5.1,
        # which is the same shape Tests/Integration uses for the same reason.
        $UnencryptedAuthParameter = if ($PSVersionTable.PSVersion.Major -ge 6) { @{ AllowUnencryptedAuthentication = $true } } else { @{} }

        try {
            $Output = Invoke-OmadaWebRequest -Uri $Script:RelyingParty.ResourceUrl `
                -AuthenticationType WebView2 `
                -Credential $Credential `
                -SkipCookieCache `
                @UnencryptedAuthParameter `
                -ErrorAction Stop 3>&1

            foreach ($Record in @($Output)) {
                if ($Record -is [System.Management.Automation.WarningRecord]) {
                    $Script:CanaryWarning += $Record.Message
                }
                else {
                    $Script:CanaryResponse = $Record
                }
            }
        }
        catch {
            $Script:CanaryError = $_
        }

        # Third route to the same fact, and the one that cannot be lost in stream plumbing: the flag
        # Switch-ToManualLogin sets in the module's own scope. Read after the fact it is only
        # suggestive - a retry window calls Reset-LoginAutomationState and clears it again - so it is
        # reported rather than asserted on, and the assertions below rest on whether the sign-in
        # actually completed.
        $Script:ManualFallbackFlag = InModuleScope 'OmadaWeb.PS' { $Script:ManualLoginFallbackActive }

        # The diagnostic that names a broken selector: the state, the selectors expected but absent,
        # the ones present, and the page path. Reported verbatim rather than summarized.
        $Script:FallbackWarning = @($Script:CanaryWarning | Where-Object { $_ -match 'Automated Microsoft sign-in' })

        if ($Script:FallbackWarning.Count -gt 0) {
            "::group::Entra sign-in canary diagnostic" | Write-Host
            $Script:FallbackWarning | ForEach-Object { $_ | Write-Host }
            "::endgroup::" | Write-Host

            # Written to a file as well as to the log so the workflow can put it in the issue it
            # files, rather than scraping it back out of its own console output.
            if (-not [string]::IsNullOrWhiteSpace($Env:OMADAWEBPS_CANARY_DIAGNOSTIC_PATH)) {
                $Script:FallbackWarning -join [System.Environment]::NewLine | Set-Content -LiteralPath $Env:OMADAWEBPS_CANARY_DIAGNOSTIC_PATH -Encoding UTF8
            }
        }
    }

    AfterAll {
        Stop-CanaryRelyingParty -RelyingParty $Script:RelyingParty
        Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    }

    It 'Signed in with the credential, without falling back to manual entry' {
        # The assertion the whole canary exists for, and the one that does not depend on catching a
        # warning: nobody is at this browser, so if autofill stops filling fields the sign-in simply
        # never completes. That makes "did the request succeed" the reliable signal, and the captured
        # diagnostic an enrichment of it rather than the thing being tested.
        $Message = if ($null -eq $Script:CanaryError) { "" } else { $Script:CanaryError.Exception.Message }
        $Diagnostic = $Script:FallbackWarning -join [System.Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($Diagnostic) -and $Script:ManualFallbackFlag) {
            $Diagnostic = "The module reported that it had handed the sign-in back to the user, but the diagnostic naming the selector was not captured."
        }

        $Report = (@($Message, $Diagnostic) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [System.Environment]::NewLine

        # The message is chosen from the evidence rather than assuming the most likely cause, because
        # this text is what the alert issue tells a maintainer to go and do.
        #
        # Issue #79 is why. A console-handle bug in Start-WebView2Login made the sign-in fail in 142
        # milliseconds, before a browser window existed - and the alert said Microsoft had changed a
        # page and sent the reader to the selector table. Everything needed to tell those apart had
        # already been collected: a selector break leaves a diagnostic, and a failure that never
        # reached Microsoft leaves RedirectHitCount at zero.
        $Because = if (-not [string]::IsNullOrWhiteSpace($Diagnostic)) {
            "credential autofill fell back to manual sign-in, so Microsoft changed a page this module recognizes by element id. " +
            "Update `$Script:EntraSignInElementId in OmadaWeb.PS/OmadaWeb.PS.psm1 from the diagnostic above (issue #32)"
        }
        elseif ($Script:RelyingParty.RedirectHitCount -eq 0 -and -not [string]::IsNullOrWhiteSpace($Message)) {
            "the sign-in failed before the browser ever came back from Microsoft, so this is NOT a selector break and the selector table is not what needs changing. " +
            "The error above is from this module or from the runner - read it first"
        }
        else {
            "credential autofill did not carry the sign-in through. No fallback diagnostic was captured, so check the error above before assuming the sign-in page changed"
        }

        $Report | Should -BeNullOrEmpty -Because $Because
    }

    It 'Did not report a selector it no longer recognizes' {
        # Separate from the assertion above so that a run which somehow completed the sign-in while
        # still reporting an unrecognized page is not quietly passed over.
        $Script:FallbackWarning -join [System.Environment]::NewLine | Should -BeNullOrEmpty
    }

    It 'Was not refused by Entra ID' {
        # Distinguishes a broken selector from a broken account: a disabled canary user, an expired
        # password or a Conditional Access block all land here instead, and all are tenant
        # configuration rather than a Microsoft DOM change.
        $Script:RelyingParty.CallbackError | Should -BeNullOrEmpty -Because "Entra returned this OAuth error code instead of an authorization code; see docs/entra-canary.md"
    }

    It 'Actually travelled through Entra and back' {
        # Guards against the canary passing for the wrong reason. Without this, a stand-in that
        # somehow answered the first request with a cookie would look exactly like a successful
        # sign-in, and the tier under test would never have run at all.
        $Script:RelyingParty.RedirectHitCount | Should -BeGreaterThan 0 -Because "the browser never came back from login.microsoftonline.com, so the autofill tier was not exercised"
    }

    It 'Returned the protected resource' {
        $Script:CanaryResponse | Should -Not -BeNullOrEmpty
        ($Script:CanaryResponse.Content | ConvertFrom-Json).canary | Should -Be "ok"
    }

    It 'Kept the loopback stand-in healthy throughout' {
        # Reads the runspace's error stream as well as the loop's own record, so a listener that died
        # before it ever served a request cannot be reported as healthy while the sign-in failure is
        # blamed on Microsoft.
        (Get-CanaryRelyingPartyError -RelyingParty $Script:RelyingParty) -join [System.Environment]::NewLine | Should -BeNullOrEmpty
    }
}

# The two sign-ins that are not meant to finish.
#
# A password that was never supplied and an account that was never named both end the same way: the
# module fills in what it was given, refuses to invent the rest, and leaves the window open for the
# person it is waiting for. On a runner that person does not exist, so there is nothing to wait for
# and nothing to assert afterwards - which is exactly why these are worth watching against the real
# Entra ID. It is the one arrangement where "the sign-in did not complete" is the correct outcome,
# and where a module that quietly submitted an empty password instead would look like a success.
#
# So the sign-in runs in a background job and is watched rather than awaited. The job is a separate
# process, which is what makes it stoppable: the WinForms dialog blocks the thread it is shown on, so
# nothing inside that process can be interrupted once the window is up. The observation window is
# fixed rather than cut short at the first marker, because the last thing these check - the handover
# that says the sign-in is waiting for you - only happens after the module has seen no progress for
# $Script:LoginAutomationFallbackTimeout seconds.
Describe 'Entra ID sign-in canary - a sign-in that waits for the user' -Tag 'E2E' -Skip:(-not $Script:RunWaitingScenario) {

    BeforeAll {
        . (Join-Path $PSScriptRoot 'Start-CanaryRelyingParty.ps1')

        $Port = if ([string]::IsNullOrWhiteSpace($Env:OMADAWEBPS_CANARY_PORT)) { 8400 } else { [int]$Env:OMADAWEBPS_CANARY_PORT }

        # Both scenarios get an authorization request that carries no prompt and no login hint. For
        # UserNameOnly that is the point - what reaches Entra has to have been put there by the
        # module - and for NoUserName it is what makes "the module added nothing" mean something.
        $Script:RelyingParty = Start-CanaryRelyingParty -TenantId $Env:OMADAWEBPS_CANARY_TENANT_ID -ClientId $Env:OMADAWEBPS_CANARY_CLIENT_ID -LoginHint '' -Prompt '' -Port $Port

        # Long enough for the redirect chain, the sign-in page, and the 60 seconds of no progress
        # that ends in the handover ($Script:LoginAutomationFallbackTimeout), with room for a slow
        # runner. The workflow allows more than this per attempt, so a window that overruns is
        # reported by these assertions rather than by a killed step.
        $ObservationSeconds = 135

        $UserNameForScenario = if ($Scenario -eq 'UserNameOnly') { $Env:OMADAWEBPS_CANARY_USERNAME } else { '' }

        $SignIn = Start-Job -ScriptBlock {
            param($ModulePath, $ResourceUrl, $UserName)

            $VerbosePreference = 'Continue'
            Import-Module $ModulePath -Force -ErrorAction Stop

            $Parameter = @{
                Uri                = $ResourceUrl
                AuthenticationType = 'WebView2'
                SkipCookieCache    = $true
            }

            # PowerShell 7 refuses to send a credential over an unencrypted connection without being
            # told to, and the stand-in serves plain HTTP on loopback. Guarded by version because the
            # parameter does not exist on Windows PowerShell 5.1.
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                $Parameter['AllowUnencryptedAuthentication'] = $true
            }

            if (-not [string]::IsNullOrWhiteSpace($UserName)) {
                $Parameter['UserName'] = $UserName
            }

            # Every stream, as strings, as they are produced. The verbose trace is the product here:
            # what is being asserted is which decisions the module took on a page it could read
            # perfectly well, and those are only ever reported there.
            Invoke-OmadaWebRequest @Parameter -Verbose *>&1 | ForEach-Object { $_.ToString() }
        } -ArgumentList $ModulePath, $Script:RelyingParty.ResourceUrl, $UserNameForScenario

        $Deadline = [DateTime]::Now.AddSeconds($ObservationSeconds)
        $Captured = [System.Collections.Generic.List[string]]::new()

        while ([DateTime]::Now -lt $Deadline -and $SignIn.State -eq 'Running') {
            foreach ($Record in @(Receive-Job -Job $SignIn -ErrorAction SilentlyContinue)) {
                $Captured.Add([string]$Record)
            }
            Start-Sleep -Milliseconds 500
        }

        # Stopped, then drained: a job that buffered rather than streamed still hands over everything
        # it wrote, so the assertions below never depend on how promptly a record crossed the process
        # boundary.
        Stop-Job -Job $SignIn -ErrorAction SilentlyContinue
        foreach ($Record in @(Receive-Job -Job $SignIn -ErrorAction SilentlyContinue)) {
            $Captured.Add([string]$Record)
        }
        Remove-Job -Job $SignIn -Force -ErrorAction SilentlyContinue

        # The browser belongs to a process that has just been killed, and the next attempt must not
        # inherit one that is still holding the profile.
        Get-Process -Name msedgewebview2 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

        $Script:Trace = $Captured -join [System.Environment]::NewLine

        "::group::Entra sign-in canary trace ($Scenario)" | Write-Host
        $Captured | ForEach-Object { $_ | Write-Host }
        "::endgroup::" | Write-Host

        if (-not [string]::IsNullOrWhiteSpace($Env:OMADAWEBPS_CANARY_DIAGNOSTIC_PATH)) {
            @($Captured | Where-Object { $_ -match 'Automated Microsoft sign-in' }) -join [System.Environment]::NewLine |
                Set-Content -LiteralPath $Env:OMADAWEBPS_CANARY_DIAGNOSTIC_PATH -Encoding UTF8
        }
    }

    AfterAll {
        Stop-CanaryRelyingParty -RelyingParty $Script:RelyingParty
    }

    It 'Put the account into the sign-in request' -Skip:($Scenario -ne 'UserNameOnly') {
        # An account named on the command line has to reach Entra as part of the request, because by
        # the time a page is drawn the account has already been chosen.
        #
        # This is also the scenario's proof that the browser got to Microsoft at all: the rewrite only
        # ever happens on an authorization request on a Microsoft sign-in host, so the line cannot be
        # in the trace unless the browser was there. Everything below depends on that, which is why
        # this assertion comes first.
        $Script:Trace | Should -Match 'Asking Entra ID for the account this call named' -Because "either the browser never reached the sign-in page, or -UserName did not reach the authorization request and Entra chose the account itself"
    }

    It 'Left the request alone when no account was named' -Skip:($Scenario -ne 'NoUserName') {
        # The default has to stay indistinguishable from the module not being involved in the choice.
        # The second assertion doubles as this scenario's proof that Microsoft was reached: the line
        # is written from the autofill driver, which runs only while the browser is on the sign-in
        # host.
        $Script:Trace | Should -Not -Match 'Asking Entra ID for the account this call named'
        $Script:Trace | Should -Match 'No account was named for this sign-in' -Because "either the browser never reached the sign-in page, or the module drove it when nobody had named an account"
    }

    It 'Reached the page that asks for a password' -Skip:($Scenario -ne 'UserNameOnly') {
        # Proves the account name was filled in and accepted: Entra only asks for a password once it
        # knows whose password it is asking for.
        $Script:Trace | Should -Match "Screen 'PasswordRequired'" -Because "the sign-in never got as far as being asked for a password, so what happens when it is asked was not tested"
    }

    It 'Did not submit a password it was never given' -Skip:($Scenario -ne 'UserNameOnly') {
        # An empty password is one of the attempts an account has before Entra ID locks it out, which
        # is why the resolver refuses to send one. This is the assertion that would catch it doing so.
        $Script:Trace | Should -Not -Match "Screen 'PasswordEntry', action 'SetValueAndClick'"
        $Script:Trace | Should -Match "action 'Wait'"
    }

    It 'Handed the window back saying it is waiting, not that the page is broken' -Skip:($Scenario -ne 'UserNameOnly') {
        # The failure this scenario exists for. Before, a password prompt ran into the stall detector
        # and was reported as "the sign-in page no longer matches what this module knows about it,
        # Microsoft probably changed it, please report this" - three false statements and a request
        # to file a bug for having to type your own password.
        $Script:Trace | Should -Match 'Automated Microsoft sign-in is waiting for you' -Because "a page the module read perfectly well was reported as a page it could not read"
        $Script:Trace | Should -Not -Match 'no longer matches what this module knows about it'
    }

    It 'Drove nothing, and so reported nothing to fix' -Skip:($Scenario -ne 'NoUserName') {
        # With no account named there is nothing to fill in, so the automation never engages - and a
        # handover diagnostic here would mean it had engaged and then given up, which is a different
        # thing entirely and would be reported as a broken sign-in page.
        $Script:Trace | Should -Not -Match 'Automated Microsoft sign-in'
    }

    It 'Kept the loopback stand-in healthy throughout' {
        (Get-CanaryRelyingPartyError -RelyingParty $Script:RelyingParty) -join [System.Environment]::NewLine | Should -BeNullOrEmpty
    }
}
