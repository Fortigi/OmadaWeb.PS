[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ModulePath', Justification = 'Used by Import-Module inside the Describe BeforeAll, which the analyzer does not follow into.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The canary password arrives from a GitHub environment secret as an environment variable, which is a plain string by the time this process can see it. Building the PSCredential the module takes is the only thing done with it.')]
param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
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
}

Describe 'Entra ID sign-in canary' -Tag 'E2E' -Skip:(-not $Script:CanaryConfigured) {

    BeforeAll {
        . (Join-Path $PSScriptRoot 'Start-CanaryRelyingParty.ps1')

        Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
        Import-Module $ModulePath -Force -ErrorAction Stop

        $Port = if ([string]::IsNullOrWhiteSpace($Env:OMADAWEBPS_CANARY_PORT)) { 8400 } else { [int]$Env:OMADAWEBPS_CANARY_PORT }

        $Script:RelyingParty = Start-CanaryRelyingParty -TenantId $Env:OMADAWEBPS_CANARY_TENANT_ID -ClientId $Env:OMADAWEBPS_CANARY_CLIENT_ID -LoginHint $Env:OMADAWEBPS_CANARY_USERNAME -Port $Port

        $SecurePassword = ConvertTo-SecureString -String $Env:OMADAWEBPS_CANARY_PASSWORD -AsPlainText -Force
        $Credential = [System.Management.Automation.PSCredential]::new($Env:OMADAWEBPS_CANARY_USERNAME, $SecurePassword)

        # -ForceAuthentication and -SkipCookieCache together are what make a scheduled run mean
        # something. A cached cookie would satisfy the request without a sign-in page ever being
        # drawn, so the canary would go green on the strength of yesterday's success.
        $Script:CanaryWarning = @()
        $Script:CanaryError = $null
        $Script:CanaryResponse = $null

        # Declared before the call rather than left to -WarningVariable to create: the tests run
        # under Set-StrictMode -Version Latest, where reading it in the catch block after a failure
        # that produced no warning would be an unset-variable error masking the real one.
        $CanaryWarningOutput = @()

        try {
            $Script:CanaryResponse = Invoke-OmadaWebRequest -Uri $Script:RelyingParty.ResourceUrl `
                -AuthenticationType WebView2 `
                -Credential $Credential `
                -ForceAuthentication `
                -SkipCookieCache `
                -ErrorAction Stop `
                -WarningVariable CanaryWarningOutput

            $Script:CanaryWarning = @($CanaryWarningOutput)
        }
        catch {
            $Script:CanaryError = $_
            $Script:CanaryWarning = @($CanaryWarningOutput)
        }

        # The one diagnostic that names a broken selector. Switch-ToManualLogin writes it to the
        # warning stream with the state, the selectors expected but absent, the ones present, and the
        # page path - so it is reported verbatim rather than summarized.
        $Script:FallbackWarning = @($Script:CanaryWarning | Where-Object { $_ -match 'Automated Microsoft sign-in could not continue' })

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

    It 'Still recognizes every Microsoft sign-in screen it was shown' {
        # This is the assertion the whole canary exists for. Its message is what a maintainer reads
        # first in a failed run, so it carries the diagnostic rather than pointing at a log.
        $Script:FallbackWarning -join [System.Environment]::NewLine | Should -BeNullOrEmpty -Because (
            "credential autofill fell back to manual sign-in, which means Microsoft changed a page this module recognizes by element id. " +
            "The diagnostic above names the state and the missing selector; update `$Script:EntraSignInElementId in OmadaWeb.PS/OmadaWeb.PS.psm1 (issue #32)"
        )
    }

    It 'Was not refused by Entra ID' {
        # Distinguishes a broken selector from a broken account: a disabled canary user, an expired
        # password or a Conditional Access block all land here instead, and all are tenant
        # configuration rather than a Microsoft DOM change.
        $Script:RelyingParty.CallbackError | Should -BeNullOrEmpty -Because "Entra returned this OAuth error code instead of an authorization code; see docs/entra-canary.md"
    }

    It 'Completed the sign-in without erroring' {
        $Message = if ($null -eq $Script:CanaryError) { "" } else { $Script:CanaryError.Exception.Message }

        $Message | Should -BeNullOrEmpty
        $Script:CanaryError | Should -BeNullOrEmpty
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
        $Script:RelyingParty.ListenerError | Should -BeNullOrEmpty
    }
}
