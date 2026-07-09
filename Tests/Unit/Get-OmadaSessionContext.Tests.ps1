param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSessionContext' -Tag 'Unit' {
    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            $Script:OmadaSessions = @{}
        }
    }

    It 'Should create a new, empty session context on first lookup' {
        InModuleScope 'OmadaWeb.PS' {
            $Context = Get-OmadaSessionContext -Key 'a.example.com::webview2::'
            $Context.Key | Should -Be 'a.example.com::webview2::'
            $Context.AuthCookie | Should -BeNullOrEmpty
            $Context.WebView2Used | Should -Be $false
        }
    }

    It 'Should return the same context instance for the same key' {
        InModuleScope 'OmadaWeb.PS' {
            $Context1 = Get-OmadaSessionContext -Key 'a.example.com::webview2::'
            $Context1.AuthCookie = [pscustomobject]@{ name = 'oisauthtoken'; value = 'abc' }
            $Context2 = Get-OmadaSessionContext -Key 'a.example.com::webview2::'
            $Context2.AuthCookie.value | Should -Be 'abc'
        }
    }

    It 'Should create independent contexts for different keys, so one session cannot clobber another' {
        InModuleScope 'OmadaWeb.PS' {
            $ContextA = Get-OmadaSessionContext -Key 'a.example.com::webview2::'
            $ContextB = Get-OmadaSessionContext -Key 'b.example.com::webview2::'
            $ContextA.AuthCookie = [pscustomobject]@{ value = 'a-cookie' }
            $ContextB.AuthCookie | Should -BeNullOrEmpty
        }
    }

    It 'Should assign different WebView2ProfilePath values for different keys' {
        InModuleScope 'OmadaWeb.PS' {
            $ContextA = Get-OmadaSessionContext -Key 'a.example.com::webview2::'
            $ContextB = Get-OmadaSessionContext -Key 'b.example.com::webview2::'
            $ContextA.WebView2ProfilePath | Should -Not -Be $ContextB.WebView2ProfilePath
            $ContextA.WebView2ProfilePath | Should -Not -BeLike '*OmadaWebView2Profile'
        }
    }

    It 'Should recompute the same WebView2ProfilePath deterministically for the same key' {
        InModuleScope 'OmadaWeb.PS' {
            $Key = 'a.example.com::webview2::'
            $Path1 = (Get-OmadaSessionContext -Key $Key).WebView2ProfilePath
            $Script:OmadaSessions.Remove($Key)
            $Path2 = (Get-OmadaSessionContext -Key $Key).WebView2ProfilePath
            $Path2 | Should -Be $Path1
        }
    }

    It 'Should place WebView2ProfilePath under the WebView2 user profile base path' {
        InModuleScope 'OmadaWeb.PS' {
            $Context = Get-OmadaSessionContext -Key 'a.example.com::webview2::'
            $Context.WebView2ProfilePath | Should -BeLike (Join-Path $Script:WebView2UserProfileBasePath '*')
        }
    }

    Context 'Legacy -ArgumentList OmadaWebAuthCookie seed' {
        It 'Should seed only the session whose host matches the seeded cookie domain, not whichever session is created first' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:OmadaWebAuthCookie = [pscustomobject]@{ name = 'oisauthtoken'; value = 'seed-value'; domain = 'a.example.com' }

                # A different tenant's session is created first - it must NOT receive the seed meant for tenant A.
                $ContextB = Get-OmadaSessionContext -Key 'b.example.com::webview2::' -AuthorityHost 'b.example.com'
                $ContextB.AuthCookie | Should -BeNullOrEmpty

                $ContextA = Get-OmadaSessionContext -Key 'a.example.com::webview2::' -AuthorityHost 'a.example.com'
                $ContextA.AuthCookie.value | Should -Be 'seed-value'
            }
        }

        It 'Should consume the seed only once it is actually used, leaving it available for a later matching session' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:OmadaWebAuthCookie = [pscustomobject]@{ name = 'oisauthtoken'; value = 'seed-value'; domain = 'a.example.com' }

                Get-OmadaSessionContext -Key 'b.example.com::webview2::' -AuthorityHost 'b.example.com' | Out-Null
                $Script:OmadaWebAuthCookie | Should -Not -BeNullOrEmpty

                $ContextA = Get-OmadaSessionContext -Key 'a.example.com::webview2::' -AuthorityHost 'a.example.com'
                $ContextA.AuthCookie.value | Should -Be 'seed-value'
                $Script:OmadaWebAuthCookie | Should -BeNullOrEmpty
            }
        }

        It 'Should not seed (and not throw) when -AuthorityHost is omitted, rather than mis-parsing the composite Key' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:OmadaWebAuthCookie = [pscustomobject]@{ name = 'oisauthtoken'; value = 'seed-value'; domain = 'a.example.com' }

                $Context = Get-OmadaSessionContext -Key 'a.example.com::webview2::'
                $Context.AuthCookie | Should -BeNullOrEmpty
                $Script:OmadaWebAuthCookie | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should correctly match an IPv6 authority host, which a naive split on the Key string would mis-parse' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:OmadaWebAuthCookie = [pscustomobject]@{ name = 'oisauthtoken'; value = 'seed-value'; domain = '::1' }

                # The Key embeds the bracketed IPv6 literal authority, which itself contains "::" -
                # a naive $Key -split '::' would mis-parse this; AuthorityHost must be used instead.
                $Context = Get-OmadaSessionContext -Key '[::1]:8443::webview2::' -AuthorityHost '::1'
                $Context.AuthCookie.value | Should -Be 'seed-value'
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
