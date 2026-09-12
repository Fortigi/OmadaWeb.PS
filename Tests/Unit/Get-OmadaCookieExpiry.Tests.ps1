param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

# Issue #82. Export-OmadaSession and Import-OmadaSession both refuse a session whose cookie has
# already expired, which only works if the expiry can be read out of a cookie from either browser
# engine - and, just as importantly, if a cookie that declares no expiry is never mistaken for one
# that has expired.

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaCookieExpiry' -Tag 'Unit' {
    Context 'A cookie that declares an expiry' {
        It 'Should read the WebView2 shape, which uses "expires"' {
            InModuleScope 'OmadaWeb.PS' {
                $Expected = [datetime]::new(2030, 5, 1, 12, 0, 0, [System.DateTimeKind]::Utc)
                $Cookie = [PSCustomObject]@{ name = 'oisauthtoken'; value = 'x'; expires = $Expected }

                Get-OmadaCookieExpiry -AuthCookie $Cookie | Should -Be $Expected
            }
        }

        It 'Should read the Selenium shape, which uses "Expiry"' {
            InModuleScope 'OmadaWeb.PS' {
                $Expected = [datetime]::new(2030, 5, 1, 12, 0, 0, [System.DateTimeKind]::Utc)
                $Cookie = [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'x'; Expiry = $Expected }

                Get-OmadaCookieExpiry -AuthCookie $Cookie | Should -Be $Expected
            }
        }

        It 'Should read an expiry that survived serialization as a string' {
            InModuleScope 'OmadaWeb.PS' {
                $Cookie = [PSCustomObject]@{ name = 'oisauthtoken'; value = 'x'; expires = '2030-05-01T12:00:00Z' }

                $Expiry = Get-OmadaCookieExpiry -AuthCookie $Cookie
                $Expiry | Should -Be ([datetime]::new(2030, 5, 1, 12, 0, 0, [System.DateTimeKind]::Utc))
                $Expiry.Kind | Should -Be ([System.DateTimeKind]::Utc)
            }
        }

        It 'Should read an expiry expressed as seconds since the Unix epoch' {
            InModuleScope 'OmadaWeb.PS' {
                $Expected = [datetime]::new(2030, 5, 1, 12, 0, 0, [System.DateTimeKind]::Utc)
                $Epoch = [System.DateTimeOffset]::new($Expected).ToUnixTimeSeconds()
                $Cookie = [PSCustomObject]@{ name = 'oisauthtoken'; value = 'x'; expires = $Epoch }

                Get-OmadaCookieExpiry -AuthCookie $Cookie | Should -Be $Expected
            }
        }

        It 'Should return the moment in UTC when the cookie states a local time' {
            InModuleScope 'OmadaWeb.PS' {
                $Local = [datetime]::new(2030, 5, 1, 12, 0, 0, [System.DateTimeKind]::Local)
                $Cookie = [PSCustomObject]@{ name = 'oisauthtoken'; value = 'x'; expires = $Local }

                $Expiry = Get-OmadaCookieExpiry -AuthCookie $Cookie
                $Expiry.Kind | Should -Be ([System.DateTimeKind]::Utc)
                $Expiry | Should -Be $Local.ToUniversalTime()
            }
        }
    }

    Context 'A cookie that declares nothing usable' {
        # Every case here has to answer $null rather than a date. The callers read $null as "this
        # cookie does not say" and carry on; anything else would refuse a live session.
        It 'Should answer nothing for a session cookie with no expiry property at all' {
            InModuleScope 'OmadaWeb.PS' {
                Get-OmadaCookieExpiry -AuthCookie ([PSCustomObject]@{ name = 'oisauthtoken'; value = 'x' }) | Should -BeNullOrEmpty
            }
        }

        It 'Should answer nothing for DateTime.MinValue, which is what a session cookie carries' {
            InModuleScope 'OmadaWeb.PS' {
                $Cookie = [PSCustomObject]@{ name = 'oisauthtoken'; value = 'x'; expires = [datetime]::MinValue }

                Get-OmadaCookieExpiry -AuthCookie $Cookie | Should -BeNullOrEmpty
            }
        }

        It 'Should answer nothing for DateTime.MaxValue, which means it never expires' {
            InModuleScope 'OmadaWeb.PS' {
                $Cookie = [PSCustomObject]@{ name = 'oisauthtoken'; value = 'x'; expires = [datetime]::MaxValue }

                Get-OmadaCookieExpiry -AuthCookie $Cookie | Should -BeNullOrEmpty
            }
        }

        It 'Should answer nothing for an expiry that cannot be understood' {
            InModuleScope 'OmadaWeb.PS' {
                $Cookie = [PSCustomObject]@{ name = 'oisauthtoken'; value = 'x'; expires = 'not a date' }

                Get-OmadaCookieExpiry -AuthCookie $Cookie | Should -BeNullOrEmpty
            }
        }

        It 'Should answer nothing for a null cookie' {
            InModuleScope 'OmadaWeb.PS' {
                Get-OmadaCookieExpiry -AuthCookie $null | Should -BeNullOrEmpty
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
