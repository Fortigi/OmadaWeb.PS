param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-BrowserAuthentication' -Tag 'Unit' {
    BeforeAll {
        InModuleScope 'OmadaWeb.PS' {
            # Each test builds its own context instead of relying on ambient variables inherited
            # from the caller's scope. Script: so the definition lands in the module's scope and
            # stays visible to the InModuleScope block of every It below.
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

    Context 'Contract' {
        It 'Should require a RequestContext' {
            InModuleScope 'OmadaWeb.PS' {
                # Asserted through the parameter metadata rather than by calling the function
                # without it: in an interactive host a missing mandatory parameter prompts rather
                # than throwing, which would hang the run.
                (Get-Command Invoke-BrowserAuthentication).Parameters['RequestContext'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
            }
        }

        It 'Should return the same context instance it was given' {
            InModuleScope 'OmadaWeb.PS' {
                Mock Get-DataFromWebDriver {
                    @(
                        [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'cookie-value'; domain = 'localhost' },
                        'user-agent'
                    )
                }
                Mock Write-OmadaDeprecationWarning {}

                # -SkipCookieCache keeps the run off the encrypted cookie cache on disk.
                $RequestContext = New-TestRequestContext -Key 'unit-test-browser-returns-context' -BoundParams @{
                    AuthenticationType = 'Browser'
                    Headers            = @{}
                    SkipCookieCache    = $true
                }

                $Returned = Invoke-BrowserAuthentication -RequestContext $RequestContext

                [object]::ReferenceEquals($Returned, $RequestContext) | Should -BeTrue
            }
        }
    }

    Context 'Cookie propagation' {
        It 'Should write the acquired cookie to both the Headers and the WebRequestSession in the context' {
            InModuleScope 'OmadaWeb.PS' {
                Mock Get-DataFromWebDriver {
                    @(
                        [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'cookie-value'; domain = 'localhost' },
                        'user-agent'
                    )
                }
                Mock Write-OmadaDeprecationWarning {}

                # This is the one helper that touches all three context members, so it is the one
                # that proves the explicitly passed context reaches the same objects the caller holds.
                $RequestContext = New-TestRequestContext -Key 'unit-test-browser-cookie-propagation' -BoundParams @{
                    AuthenticationType = 'Browser'
                    Headers            = @{}
                    SkipCookieCache    = $true
                }

                Invoke-BrowserAuthentication -RequestContext $RequestContext | Out-Null

                $RequestContext.BoundParams.Headers.Cookie | Should -Be 'oisauthtoken=cookie-value'
                $RequestContext.Session.Cookies.GetCookies('http://localhost')['oisauthtoken'].Value | Should -Be 'cookie-value'
                $RequestContext.SessionContext.AuthCookie.Value | Should -Be 'cookie-value'
            }
        }
    }

    Context 'Selenium deprecation' {
        It 'Should warn about the Selenium deprecation when the Selenium engine drives the login' {
            InModuleScope 'OmadaWeb.PS' {
                Mock Get-DataFromWebDriver {
                    @(
                        [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'cookie-value'; domain = 'localhost' },
                        'user-agent'
                    )
                }
                Mock Write-OmadaDeprecationWarning {}

                $RequestContext = New-TestRequestContext -Key 'unit-test-selenium-deprecation' -BoundParams @{
                    AuthenticationType = 'Browser'
                    Headers            = @{}
                    SkipCookieCache    = $true
                }

                Invoke-BrowserAuthentication -RequestContext $RequestContext | Out-Null

                Should -Invoke Get-DataFromWebDriver -Times 1 -Exactly
                Should -Invoke Write-OmadaDeprecationWarning -Times 1 -Exactly -ParameterFilter {
                    $Feature -eq 'SeleniumBrowserEngine'
                }
            }
        }

        It 'Should not warn about the Selenium deprecation when WebView2 drives the login' {
            InModuleScope 'OmadaWeb.PS' {
                # $SessionContext here is the mock's own bound parameter - Invoke-BrowserAuthentication
                # passes the context's SessionContext to Get-DataFromWebView2 explicitly.
                Mock Get-DataFromWebView2 {
                    $SessionContext.AuthCookie = [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'cookie-value'; domain = 'localhost' }
                }
                Mock Write-OmadaDeprecationWarning {}

                $RequestContext = New-TestRequestContext -Key 'unit-test-webview2-no-deprecation' -BoundParams @{
                    AuthenticationType = 'WebView2'
                    Headers            = @{}
                    SkipCookieCache    = $true
                }

                Invoke-BrowserAuthentication -RequestContext $RequestContext | Out-Null

                Should -Invoke Get-DataFromWebView2 -Times 1 -Exactly
                Should -Invoke Write-OmadaDeprecationWarning -Times 0 -Exactly
            }
        }
    }

    Context 'Preferred MFA method' {
        It 'Should carry -PreferredMfaMethod onto the session context the sign-in reads' {
            InModuleScope 'OmadaWeb.PS' {
                # The WebView2 sign-in runs inside a blocking WinForm dialog whose event handlers
                # cannot see the call stack, so the session context is the only way the choice
                # reaches Resolve-EntraSignInScreen.
                Mock Get-DataFromWebView2 { $SessionContext.AuthCookie = [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'cookie-value'; domain = 'localhost' } }

                $RequestContext = New-TestRequestContext -Key 'unit-test-preferred-mfa-method' -BoundParams @{
                    AuthenticationType = 'WebView2'
                    Headers            = @{}
                    SkipCookieCache    = $true
                    PreferredMfaMethod = 'PhoneAppOTP'
                }

                Invoke-BrowserAuthentication -RequestContext $RequestContext | Out-Null

                $RequestContext.SessionContext.PreferredMfaMethod | Should -Be 'PhoneAppOTP'
            }
        }

        It 'Should clear a preference left over from an earlier call' {
            InModuleScope 'OmadaWeb.PS' {
                Mock Get-DataFromWebView2 { $SessionContext.AuthCookie = [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'cookie-value'; domain = 'localhost' } }

                $RequestContext = New-TestRequestContext -Key 'unit-test-preferred-mfa-method-cleared' -BoundParams @{
                    AuthenticationType = 'WebView2'
                    Headers            = @{}
                    SkipCookieCache    = $true
                    PreferredMfaMethod = 'PhoneAppOTP'
                }

                Invoke-BrowserAuthentication -RequestContext $RequestContext | Out-Null

                $RequestContext.SessionContext.AuthCookie = $null
                $RequestContext.BoundParams.Remove('PreferredMfaMethod')
                $RequestContext.BoundParams.Headers = @{}

                Invoke-BrowserAuthentication -RequestContext $RequestContext | Out-Null

                $RequestContext.SessionContext.PreferredMfaMethod | Should -BeNullOrEmpty
            }
        }

        It 'Should not forward -PreferredMfaMethod to the underlying web cmdlet' {
            InModuleScope 'OmadaWeb.PS' {
                # It configures this module's sign-in automation; Invoke-RestMethod has never heard
                # of it and would fail the call.
                $RequestContext = New-TestRequestContext -Key 'unit-test-preferred-mfa-not-forwarded' -BoundParams @{
                    AuthenticationType = 'WebView2'
                    Headers            = @{}
                    PreferredMfaMethod = 'PhoneAppOTP'
                    Uri                = 'http://localhost:19000/'
                }

                (Set-RequestParameter -RequestContext $RequestContext).Keys | Should -Not -Contain 'PreferredMfaMethod'
            }
        }

        It 'Should offer only the method identifiers Entra ID uses' {
            InModuleScope 'OmadaWeb.PS' {
                $Parameter = (Set-DynamicParameter -FunctionName 'Invoke-RestMethod')['PreferredMfaMethod']
                $ValidateSet = $Parameter.Attributes.Where({ $_ -is [System.Management.Automation.ValidateSetAttribute] })[0]

                $ValidateSet.ValidValues | Should -Contain 'PhoneAppNotification'
                $ValidateSet.ValidValues | Should -Contain 'PhoneAppOTP'
                $ValidateSet.ValidValues | Should -Contain 'OneWaySMS'
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
