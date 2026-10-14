param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'NoInteractiveAuthentication' -Tag 'Unit' {
    BeforeAll {
        InModuleScope 'OmadaWeb.PS' {
            # Same fixture shape as Invoke-BrowserAuthentication.Tests.ps1: each test builds its own
            # context rather than inheriting ambient variables. Script: so the definition lands in
            # the module's scope and stays visible to the InModuleScope block of every It below.
            function Script:New-TestRequestContext {
                param(
                    [hashtable]$BoundParams,
                    [string]$Key,
                    [string]$BaseUrl = 'http://localhost:19000/'
                )

                $SessionContext = Get-OmadaSessionContext -Key $Key
                $SessionContext.BaseUrl = $BaseUrl

                return New-OmadaRequestContext -BoundParams $BoundParams -Session ([Microsoft.PowerShell.Commands.WebRequestSession]::new()) -SessionContext $SessionContext
            }
        }
    }

    Context 'The error contract' {
        It 'Should carry the OmadaSessionExpired id and an AuthenticationException' {
            InModuleScope 'OmadaWeb.PS' {
                $ErrorRecord = New-OmadaSessionExpiredError -Message 'gone' -BaseUrl 'http://localhost:19000/'

                # Both halves of the documented contract. A caller matches on either, so both have
                # to hold - the id for a script that inspects $_, the exception type for a
                # 'catch [System.Security.Authentication.AuthenticationException]' block.
                $ErrorRecord.FullyQualifiedErrorId | Should -Be 'OmadaSessionExpired'
                $ErrorRecord.Exception | Should -BeOfType [System.Security.Authentication.AuthenticationException]
                $ErrorRecord.CategoryInfo.Category | Should -Be 'AuthenticationError'
                $ErrorRecord.TargetObject | Should -Be 'http://localhost:19000/'
            }
        }

        It 'Should keep the originating exception reachable as the inner exception' {
            InModuleScope 'OmadaWeb.PS' {
                # The 401 response is the only place the server's own explanation survives, so it
                # must not be dropped when the verdict is wrapped.
                $Original = [System.InvalidOperationException]::new('the original 401')

                $ErrorRecord = New-OmadaSessionExpiredError -Message 'gone' -BaseUrl 'http://localhost:19000/' -InnerException $Original

                $ErrorRecord.Exception.InnerException | Should -Be $Original
            }
        }
    }

    Context 'A missing session' {
        It 'Should refuse to sign in, and reach neither browser engine' {
            InModuleScope 'OmadaWeb.PS' {
                Mock Get-DataFromWebView2 { $SessionContext.AuthCookie = [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'cookie-value'; domain = 'localhost' } }
                Mock Get-DataFromWebDriver {
                    @(
                        [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'cookie-value'; domain = 'localhost' },
                        'user-agent'
                    )
                }
                Mock Write-OmadaDeprecationWarning {}

                $RequestContext = New-TestRequestContext -Key 'unit-test-no-interactive-missing-session' -BoundParams @{
                    AuthenticationType          = 'WebView2'
                    Headers                     = @{}
                    SkipCookieCache             = $true
                    NoInteractiveAuthentication = $true
                }

                $Failure = { Invoke-BrowserAuthentication -RequestContext $RequestContext } | Should -Throw -PassThru

                $Failure.FullyQualifiedErrorId | Should -BeLike 'OmadaSessionExpired*'
                $Failure.Exception | Should -BeOfType [System.Security.Authentication.AuthenticationException]

                # The acceptance criterion "no code path under it reaches Selenium, WebView2 or any
                # window", asserted at the only two places in the module that start a sign-in.
                Should -Invoke Get-DataFromWebView2 -Times 0 -Exactly
                Should -Invoke Get-DataFromWebDriver -Times 0 -Exactly
            }
        }

        It 'Should still sign in when the switch is absent, so the refusal is the switch and not the fixture' {
            InModuleScope 'OmadaWeb.PS' {
                Mock Get-DataFromWebView2 { $SessionContext.AuthCookie = [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'cookie-value'; domain = 'localhost' } }

                $RequestContext = New-TestRequestContext -Key 'unit-test-no-interactive-control' -BoundParams @{
                    AuthenticationType = 'WebView2'
                    Headers            = @{}
                    SkipCookieCache    = $true
                }

                Invoke-BrowserAuthentication -RequestContext $RequestContext | Out-Null

                Should -Invoke Get-DataFromWebView2 -Times 1 -Exactly
            }
        }
    }

    Context 'An existing session' {
        It 'Should attach the existing cookie exactly as it would without the switch' {
            InModuleScope 'OmadaWeb.PS' {
                Mock Get-DataFromWebView2 { throw 'A sign-in must not be attempted when a usable cookie exists.' }
                Mock Get-DataFromWebDriver { throw 'A sign-in must not be attempted when a usable cookie exists.' }

                $RequestContext = New-TestRequestContext -Key 'unit-test-no-interactive-existing-session' -BoundParams @{
                    AuthenticationType          = 'WebView2'
                    Headers                     = @{}
                    SkipCookieCache             = $true
                    NoInteractiveAuthentication = $true
                }
                $RequestContext.SessionContext.AuthCookie = [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'cookie-value'; domain = 'localhost' }

                Invoke-BrowserAuthentication -RequestContext $RequestContext | Out-Null

                $RequestContext.BoundParams.Headers.Cookie | Should -Be 'oisauthtoken=cookie-value'
                $RequestContext.Session.Cookies.GetCookies('http://localhost')['oisauthtoken'].Value | Should -Be 'cookie-value'
            }
        }
    }

    Context 'Parameter plumbing' {
        It 'Should be declared on both exported wrappers as a switch' {
            # A switch rather than a valued parameter, so it composes with -AuthenticationType
            # instead of becoming a new authentication type of its own.
            foreach ($CommandName in @('Invoke-OmadaRestMethod', 'Invoke-OmadaWebRequest')) {
                $Parameter = (Get-Command $CommandName).Parameters['NoInteractiveAuthentication']
                $Parameter | Should -Not -BeNullOrEmpty -Because "$CommandName should offer -NoInteractiveAuthentication"
                $Parameter.ParameterType | Should -Be ([System.Management.Automation.SwitchParameter])
            }
        }

        It 'Should not forward the switch to the underlying web cmdlet' {
            InModuleScope 'OmadaWeb.PS' {
                # It is this module's own parameter; Invoke-RestMethod has never heard of it and
                # would fail the call.
                $RequestContext = New-TestRequestContext -Key 'unit-test-no-interactive-not-forwarded' -BoundParams @{
                    AuthenticationType          = 'WebView2'
                    Headers                     = @{}
                    NoInteractiveAuthentication = $true
                    Uri                         = 'http://localhost:19000/'
                }

                (Set-RequestParameter -RequestContext $RequestContext).Keys | Should -Not -Contain 'NoInteractiveAuthentication'
            }
        }

        It 'Should refuse to be combined with -ForceAuthentication' {
            # One forbids signing in and the other requires it, so honouring either would silently
            # discard the other.
            { Invoke-OmadaRestMethod -Uri 'http://localhost:19000/api/thing' -AuthenticationType 'WebView2' -NoInteractiveAuthentication -ForceAuthentication -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Cannot combine -NoInteractiveAuthentication with -ForceAuthentication*'
        }
    }
}
