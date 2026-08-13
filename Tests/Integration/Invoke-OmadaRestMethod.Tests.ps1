param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop -Prefix Test

    $RandomPort = Get-Random -Minimum 17000 -Maximum 19000

    . (Join-Path $PSScriptRoot 'Start-WebServer.ps1') -Action Start -Port $RandomPort -Force | Out-Null
    Start-Sleep -Seconds 2
    $Uri = "http://localhost:{0}/" -f $RandomPort

    # -AllowUnencryptedAuthentication (Invoke-WebRequest/Invoke-RestMethod) needs PS6+; Windows PowerShell 5.1 has no such parameter.
    $Script:AllowUnencryptedAuthParams = if ($PSVersionTable.PSVersion.Major -ge 6) { @{ AllowUnencryptedAuthentication = $true } } else { @{} }

    # The -CookiePath file name is derived from the URI authority (which includes this test's
    # non-default port), not a plain "<host>.cookie" - compute it the same way the module does so
    # tests seed/check the exact file the code actually reads/writes.
    $Script:CookieFileName = InModuleScope 'OmadaWeb.PS' -Parameters @{ UriA = $Uri } {
        Get-OmadaCookieFileName -Uri ([System.Uri]::new($UriA))
    }

    InModuleScope 'OmadaWeb.PS' {
        if ($env:TF_BUILD -eq 'True' -or $env:TF_BUILD -eq $true -or $env:GITHUB_ACTIONS -eq 'true') {
            #Skip WebView2 login in CI/CD pipelines
            # Get-DataFromWebView2 sets $Script:CurrentWebView2Session before calling this (mocked) function,
            # so writing through that pointer lands the fake cookie in the correct per-session context.
            Mock -ModuleName OmadaWeb.PS Start-WebView2Login { $Script:CurrentWebView2Session.AuthCookie = [pscustomobject]@{
                    name     = "oisauthtoken"
                    value    = "test-cookie-value"
                    domain   = "localhost"
                    path     = "/"
                    expires  = $null
                    httpOnly = $true
                    secure   = $false
                    sameSite = "Lax"
                }
                $Script:UserAgent = "test-user-agent"
            } -Verifiable
        }
    }
}

Describe 'Invoke-TestOmadaRestMethod' -Tag 'Integration' {
    Context 'Function Definition' {
        It 'Should have Invoke-(Test)OmadaODataMethod alias' {
            (Get-Alias Invoke-TestOmadaODataMethod).ReferencedCommand.Name | Should -Eq 'Invoke-TestOmadaRestMethod'
        }

        It 'Should have CmdletBinding attribute' {
            (Get-Command Invoke-TestOmadaRestMethod).CmdletBinding | Should -Be $true
        }

        It 'Should have DefaultParameterSetName set to StandardMethod' {
            $cmd = Get-Command Invoke-TestOmadaRestMethod
            $cmd.DefaultParameterSet | Should -Be 'StandardMethod'
        }
    }

    Context 'Process Block - Success' {
        It 'Should return result from Invoke-(Test)OmadaRestMethod' {
            $Result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType None
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRestMethod using None Authentication' {
            $Result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType None -Verbose
            $Result | Should -Be "OK"
        }

        It 'Should probe the environment once and proceed when it is not suspended' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ UriA = $Uri } {
                # Clear the cached suspension state so the probe is guaranteed to run for this
                # call, independent of any earlier test that already warmed the cache.
                $Global:OmadaWebPSCurrentBaseUrl = $null
                $Script:EnvironmentSuspended = $false
                $Script:RecheckEnvironmentSuspended = $false
                Mock Test-EnvironmentSuspended { $false } -Verifiable
                $Result = Invoke-OmadaRestMethod -Uri $UriA -AuthenticationType None
                $Result | Should -Be "OK"
                Should -Invoke Test-EnvironmentSuspended -Times 1 -Exactly -ParameterFilter { $TimeoutSec -eq 5 }
            }
        }

        It 'Should probe the environment only once for repeated requests to the same base URL' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ UriA = $Uri } {
                $Global:OmadaWebPSCurrentBaseUrl = $null
                $Script:EnvironmentSuspended = $false
                $Script:RecheckEnvironmentSuspended = $false
                Mock Test-EnvironmentSuspended { $false } -Verifiable
                $null = Invoke-OmadaRestMethod -Uri $UriA -AuthenticationType None
                $null = Invoke-OmadaRestMethod -Uri $UriA -AuthenticationType None
                # Cached after the first probe: the second request must not re-probe.
                Should -Invoke Test-EnvironmentSuspended -Times 1 -Exactly
            }
        }

        It 'Should re-probe the environment when a re-check is flagged (as after a 502)' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ UriA = $Uri } {
                # Cache is already warm for this base URL...
                $Global:OmadaWebPSCurrentBaseUrl = ([System.Uri]::new($UriA)).GetLeftPart([System.UriPartial]::Authority)
                $Script:EnvironmentSuspended = $false
                # ...but a prior 502 flagged that the environment must be re-checked.
                $Script:RecheckEnvironmentSuspended = $true
                Mock Test-EnvironmentSuspended { $false } -Verifiable
                $null = Invoke-OmadaRestMethod -Uri $UriA -AuthenticationType None
                Should -Invoke Test-EnvironmentSuspended -Times 1 -Exactly
                # The flag is consumed so the check falls back to once-per-base-URL caching.
                $Script:RecheckEnvironmentSuspended | Should -Be $false
            }
        }

        It 'Should return result from Invoke-(Test)OmadaRestMethod using Basic Authentication' {
            $Credential = (New-Object System.Management.Automation.PSCredential("user", (ConvertTo-SecureString "password" -AsPlainText -Force)))
            $Result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType Basic -Credential $Credential @AllowUnencryptedAuthParams
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRestMethod using Windows Authentication' {
            $Credential = (New-Object System.Management.Automation.PSCredential("user", (ConvertTo-SecureString "password" -AsPlainText -Force)))
            $Result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType Windows -Credential $Credential @AllowUnencryptedAuthParams
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRestMethod using Integrated Authentication' {
            $Result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType Integrated @AllowUnencryptedAuthParams
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRestMethod using Browser Authentication using WebDriver/Selenium' {
            $Result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType Browser -ForceAuthentication
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRestMethod using Browser Authentication using WebDriver/Selenium -InPrivate' {
            $Result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType Browser -ForceAuthentication -InPrivate -Verbose
            $Result | Should -Be "OK"
        }

        Context 'Process Block - WebView2 Authentication' {
            BeforeAll {
                $Result = Invoke-TestOmadaRestMethod -Uri $Uri -UseWebView2 -ForceAuthentication -WarningVariable WarningOutput
            }
            It 'Should return result from Invoke-(Test)OmadaRestMethod using Browser Authentication using -UseWebView2' {
                $Result | Should -Be "OK"
            }
            It 'Should return warning that -UseWebView2 is deprecated' {
                $WarningOutput | Should -BeLike "*UseWebView2 is deprecated*"
            }
        }

        Context 'Process Block - WebView2 Authentication -InPrivate' {
            BeforeAll {
                $Result = Invoke-TestOmadaRestMethod -Uri $Uri -UseWebView2 -ForceAuthentication -InPrivate -WarningVariable WarningOutput -Verbose
            }
            It 'Should return result from Invoke-(Test)OmadaRestMethod using Browser Authentication using -UseWebView2 -InPrivate' {
                $Result | Should -Be "OK"

            }
            It 'Should return warning that -UseWebView2 is deprecated' {
                $WarningOutput | Should -BeLike "*UseWebView2 is deprecated*"
            }
        }

        It 'Should return result from Invoke-(Test)OmadaRestMethod using Browser Authentication using AuthenticationType WebView2' {
            $Result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType WebView2 -ForceAuthentication
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRestMethod using Browser Authentication using AuthenticationType WebView2 -InPrivate' {
            $Result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType WebView2 -ForceAuthentication -InPrivate -Verbose
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaWebRequest using a custom OAuthUri' {
            $Credential = (New-Object System.Management.Automation.PSCredential("user", (ConvertTo-SecureString "password" -AsPlainText -Force)))
            $Result = Invoke-TestOmadaWebRequest -Uri $Uri -AuthenticationType OAuth -ForceAuthentication -Credential $Credential  -OAuthUri $Uri @AllowUnencryptedAuthParams -Verbose
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaWebRequest using a custom OAuthUri and OAuthScope' {
            $Credential = (New-Object System.Management.Automation.PSCredential("user", (ConvertTo-SecureString "password" -AsPlainText -Force)))
            $Result = Invoke-TestOmadaWebRequest -Uri $Uri -AuthenticationType OAuth -ForceAuthentication -Credential $Credential -OAuthUri $Uri -OAuthScope $Uri  @AllowUnencryptedAuthParams -WarningVariable Test -Verbose
            $Result | Should -Be "OK"
        }

        It 'Should read cookie previous from exported cookie file' {
            $CookieObject = [PSCustomObject]@{
                OmadaWebAuthCookie = [pscustomobject]@{
                    name     = "oisauthtoken"
                    value    = "test-cookie-value"
                    domain   = "localhost"
                    path     = "/"
                    expires  = $null
                    httpOnly = $true
                    secure   = $false
                    sameSite = "Lax"
                }
            }
            $CookiePath = Join-Path $Env:Temp $Script:CookieFileName
            $CookieObject | Export-Clixml -Path $CookiePath -Force
            $Result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType None -CookiePath $Env:Temp -Verbose
            Get-Item $CookiePath | Remove-Item -Force
            $Result | Should -Be "OK"
        }

        It 'Should create cookie file when using CookiePath parameter using WebView2' {
            $CookiePath = Join-Path $Env:Temp $Script:CookieFileName
            try { Get-Item $CookiePath | Remove-Item -Force } catch { }
            Test-Path $CookiePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaRestMethod -Uri $Uri -CookiePath $Env:Temp -Verbose -ForceAuthentication | Out-Null
            Test-Path $CookiePath -PathType Leaf | Should -Be $true
        }

        It 'Should create cookie file when using CookiePath parameter using WebView2 -InPrivate' {
            $CookiePath = Join-Path $Env:Temp $Script:CookieFileName
            try { Get-Item $CookiePath | Remove-Item -Force } catch { }
            Test-Path $CookiePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaRestMethod -Uri $Uri -CookiePath $Env:Temp -Verbose -ForceAuthentication -InPrivate | Out-Null
            Test-Path $CookiePath -PathType Leaf | Should -Be $true
        }

        It 'Should create cookie file when using CookiePath parameter using WebView2' {
            $CookiePath = Join-Path $Env:Temp $Script:CookieFileName
            try { Get-Item $CookiePath | Remove-Item -Force } catch { }
            Test-Path $CookiePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaRestMethod -Uri $Uri -CookiePath $Env:Temp -UseWebView2 -Verbose -ForceAuthentication | Out-Null
            Test-Path $CookiePath -PathType Leaf | Should -Be $true
        }

        It 'Should create cookie file when using CookiePath parameter using WebView2 -InPrivate' {
            $CookiePath = Join-Path $Env:Temp $Script:CookieFileName
            try { Get-Item $CookiePath | Remove-Item -Force } catch { }
            Test-Path $CookiePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaRestMethod -Uri $Uri -CookiePath $Env:Temp -UseWebView2 -Verbose -ForceAuthentication -InPrivate | Out-Null
            Test-Path $CookiePath -PathType Leaf | Should -Be $true
        }

        It 'Should create cached cookie file when using CookiePath parameter using WebView2' {
            # The encrypted cookie cache is keyed by the full session key (base URL :: auth type :: identity),
            # not just the URI authority, so different auth types/identities to the same host don't collide.
            $SessionKey = "{0}::webview2::" -f ([System.Uri]::New($Uri)).Authority.ToLowerInvariant()
            $CookieCacheFilePath = Join-Path (Join-Path $Env:LOCALAPPDATA -ChildPath "OmadaWeb.PS\Cookies") -ChildPath (([System.Guid]([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($SessionKey)))).Guid -replace "-", "")
            try { Get-Item $CookieCacheFilePath | Remove-Item -Force } catch { }
            Test-Path $CookieCacheFilePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaRestMethod -Uri $Uri -UseWebView2 -Verbose -ForceAuthentication | Out-Null
            Test-Path $CookieCacheFilePath -PathType Leaf | Should -Be $true
            try { Get-Item $CookieCacheFilePath | Remove-Item -Force } catch { }
        }

        It 'Should not create cached cookie file when using CookiePath parameter using WebView2' {
            # The encrypted cookie cache is keyed by the full session key (base URL :: auth type :: identity),
            # not just the URI authority, so different auth types/identities to the same host don't collide.
            $SessionKey = "{0}::webview2::" -f ([System.Uri]::New($Uri)).Authority.ToLowerInvariant()
            $CookieCacheFilePath = Join-Path (Join-Path $Env:LOCALAPPDATA -ChildPath "OmadaWeb.PS\Cookies") -ChildPath (([System.Guid]([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($SessionKey)))).Guid -replace "-", "")
            try { Get-Item $CookieCacheFilePath | Remove-Item -Force } catch { }
            Test-Path $CookieCacheFilePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaRestMethod -Uri $Uri -UseWebView2 -Verbose -ForceAuthentication -SkipCookieCache | Out-Null
            Test-Path $CookieCacheFilePath -PathType Leaf | Should -Be $false
            try { Get-Item $CookieCacheFilePath | Remove-Item -Force } catch { }
        }
    }

    Context 'Process Block - Session Isolation' {
        It 'Should keep independent sessions for two different -SessionKey values against the same tenant' {
            Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType WebView2 -ForceAuthentication -SessionKey 'user-a' | Out-Null
            Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType WebView2 -ForceAuthentication -SessionKey 'user-b' | Out-Null

            InModuleScope 'OmadaWeb.PS' -Parameters @{ UriA = $Uri } {
                $KeyA = Get-OmadaSessionKey -Uri ([System.Uri]::new($UriA)) -AuthenticationType 'WebView2' -SessionKey 'user-a'
                $KeyB = Get-OmadaSessionKey -Uri ([System.Uri]::new($UriA)) -AuthenticationType 'WebView2' -SessionKey 'user-b'

                $KeyA | Should -Not -Be $KeyB
                $Script:OmadaSessions.ContainsKey($KeyA) | Should -Be $true
                $Script:OmadaSessions.ContainsKey($KeyB) | Should -Be $true
                $Script:OmadaSessions[$KeyA].AuthCookie | Should -Not -BeNullOrEmpty
                $Script:OmadaSessions[$KeyB].AuthCookie | Should -Not -BeNullOrEmpty
                # The two sessions must be distinct objects, proving they no longer share one flat cookie slot
                # where authenticating "user-b" would silently overwrite "user-a"'s cookie.
                [object]::ReferenceEquals($Script:OmadaSessions[$KeyA], $Script:OmadaSessions[$KeyB]) | Should -Be $false
            }
        }

        It 'Should use the cookie from -CookiePath even when an in-memory cookie already exists for that session' {
            # Populate an in-memory cookie for this session first.
            Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType WebView2 -ForceAuthentication | Out-Null

            # Pre-seed a *different* cookie value into a -CookiePath file for the same host.
            $CookieObject = [PSCustomObject]@{
                OmadaWebAuthCookie = [pscustomobject]@{
                    name     = "oisauthtoken"
                    value    = "cookie-from-path-value"
                    domain   = "localhost"
                    path     = "/"
                    expires  = $null
                    httpOnly = $true
                    secure   = $false
                    sameSite = "Lax"
                }
            }
            $CookiePath = Join-Path $Env:Temp $Script:CookieFileName
            $CookieObject | Export-Clixml -Path $CookiePath -Force

            $Result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType WebView2 -CookiePath $Env:Temp -Verbose
            Get-Item $CookiePath | Remove-Item -Force
            $Result | Should -Be "OK"

            InModuleScope 'OmadaWeb.PS' -Parameters @{ UriA = $Uri } {
                $Key = Get-OmadaSessionKey -Uri ([System.Uri]::new($UriA)) -AuthenticationType 'WebView2'
                $Script:OmadaSessions[$Key].AuthCookie.value | Should -Be 'cookie-from-path-value'
            }
        }
    }

    Context 'Process Block - Error Handling' {
        It 'Should throw terminating error when Invoke-OmadaRestMethod fails' {
            InModuleScope 'OmadaWeb.PS' {
                Mock Invoke-OmadaRequest { throw "Test Error" }
                { Invoke-OmadaRestMethod -Uri "http://localhost" -ErrorAction Stop } | Should -Throw
            }
        }

        It 'Should throw terminating error when the environment is suspended' {
            InModuleScope 'OmadaWeb.PS' {
                $Global:OmadaWebPSCurrentBaseUrl = $null
                $Script:EnvironmentSuspended = $false
                $Script:RecheckEnvironmentSuspended = $false
                Mock Test-EnvironmentSuspended { $true }
                try {
                    { Invoke-OmadaRestMethod -Uri "http://localhost" -AuthenticationType None -ErrorAction Stop } | Should -Throw "*Environment is suspended*"
                }
                finally {
                    # Clear the cached suspended flag so it does not leak into later tests.
                    $Script:EnvironmentSuspended = $false
                    $Global:OmadaWebPSCurrentBaseUrl = $null
                }
            }
        }

        It 'Should cache the suspended result and not re-probe repeated calls to the same base URL' {
            InModuleScope 'OmadaWeb.PS' {
                $Global:OmadaWebPSCurrentBaseUrl = $null
                $Script:EnvironmentSuspended = $false
                $Script:RecheckEnvironmentSuspended = $false
                Mock Test-EnvironmentSuspended { $true }
                try {
                    { Invoke-OmadaRestMethod -Uri "http://localhost" -AuthenticationType None -ErrorAction Stop } | Should -Throw "*Environment is suspended*"
                    { Invoke-OmadaRestMethod -Uri "http://localhost" -AuthenticationType None -ErrorAction Stop } | Should -Throw "*Environment is suspended*"
                    # The suspended status must be cached even though the abort throws: only the
                    # first call probes; the second reuses the cached result.
                    Should -Invoke Test-EnvironmentSuspended -Times 1 -Exactly
                }
                finally {
                    $Script:EnvironmentSuspended = $false
                    $Global:OmadaWebPSCurrentBaseUrl = $null
                }
            }
        }

        It 'Should throw terminating error when -WebSession is used' {
            { Invoke-TestOmadaRestMethod -Uri $Uri -ErrorAction Stop  -Verbose -WebSession null } | Should -Throw
        }
        It 'Should throw terminating error when -Authentication Basic is used' -Skip:($PSVersionTable.PSVersion.Major -lt 6) {
            # -Authentication doesn't exist on Windows PowerShell 5.1's Invoke-RestMethod, so there is no native
            # parameter here to guard against on that edition - it prefix-matches -AuthenticationType instead.
            $Credential = (New-Object System.Management.Automation.PSCredential("user", (ConvertTo-SecureString "password" -AsPlainText -Force)))
            { Invoke-TestOmadaRestMethod -Uri $Uri -ErrorAction Stop  -Verbose -Authentication Basic  $Credential } | Should -Throw
        }
        It 'Should throw terminating error when -SessionVariable is used' {
            { Invoke-TestOmadaRestMethod -Uri $Uri -ErrorAction Stop  -Verbose -SessionVariable session } | Should -Throw
        }
        It 'Should throw terminating error when -UseDefaultCredentials is used' {
            { Invoke-TestOmadaRestMethod -Uri $Uri -ErrorAction Stop  -Verbose -UseDefaultCredentials } | Should -Throw
        }
        It 'Should throw terminating error when -UseBasicParsing is used' {
            { Invoke-TestOmadaRestMethod -Uri $Uri -ErrorAction Stop  -Verbose -UseBasicParsing } | Should -Throw
        }

    }
}

AfterAll {
    . (Join-Path $PSScriptRoot 'Start-WebServer.ps1') -Port $RandomPort -Action Stop -Force | Out-Null
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}