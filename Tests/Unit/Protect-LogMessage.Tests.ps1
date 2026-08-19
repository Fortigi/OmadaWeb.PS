param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Protect-LogMessage' -Tag 'Unit' {
    Context 'Authentication schemes' {
        It 'Should mask the token after a Basic scheme' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message 'Authorization: Basic dXNlcjpwYXNzd29yZA=='
                $Result | Should -Not -Match 'dXNlcjpwYXNzd29yZA'
                $Result | Should -Match 'Basic \*\*\*REDACTED\*\*\*'
            }
        }

        It 'Should mask the token after a Bearer scheme' {
            InModuleScope 'OmadaWeb.PS' {
                Protect-LogMessage -Message 'Authorization: Bearer abcdefgh12345678' | Should -Not -Match 'abcdefgh12345678'
            }
        }

        It 'Should leave a bare scheme name alone, since it is diagnostic and not secret' {
            InModuleScope 'OmadaWeb.PS' {
                Protect-LogMessage -Message 'AuthenticationType: Basic' | Should -Be 'AuthenticationType: Basic'
            }
        }
    }

    Context 'Tokens without a scheme prefix' {
        It 'Should mask a bare JWT' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message 'cached token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.Xy_Z1 for tenant'
                $Result | Should -Not -Match 'eyJhbGciOiJIUzI1NiJ9'
                $Result | Should -Match 'REDACTED-JWT'
                $Result | Should -Match 'for tenant'
            }
        }
    }

    Context 'Key/value pairs' {
        It 'Should mask a JSON pair whose key names a secret' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message '{"Password": "Sup3rSecret!", "Method": "POST"}'
                $Result | Should -Not -Match 'Sup3rSecret'
                $Result | Should -Match 'POST'
            }
        }

        It 'Should mask a query-string or form pair whose key names a secret' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message 'grant_type=client_credentials&client_secret=Sup3rSecret!'
                $Result | Should -Not -Match 'Sup3rSecret'
                $Result | Should -Match 'grant_type=client_credentials'
            }
        }

        It 'Should mask a Set-Cookie header whatever the cookie is called' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message 'Set-Cookie: oisauthtoken=cookie-secret-value; Path=/; HttpOnly'
                $Result | Should -Not -Match 'cookie-secret-value'
                $Result | Should -Match 'oisauthtoken=\*\*\*REDACTED\*\*\*'
            }
        }

        It 'Should spare the credential user name that ConvertTo-RedactedLogString deliberately emits' {
            InModuleScope 'OmadaWeb.PS' {
                # The walker keeps the account name on purpose - it is the first thing you need for a
                # 401 - so the two layers must not silently disagree about it.
                $Result = Protect-LogMessage -Message '{"Credential": "PSCredential(UserName=omada\\svc_sql)"}'
                $Result | Should -Match 'svc_sql'
            }
        }
    }

    Context 'Edge cases' {
        It 'Should return an empty message unchanged' {
            InModuleScope 'OmadaWeb.PS' {
                Protect-LogMessage -Message '' | Should -Be ''
            }
        }

        It 'Should return a null message unchanged' {
            InModuleScope 'OmadaWeb.PS' {
                Protect-LogMessage -Message $null | Should -BeNullOrEmpty
            }
        }

        It 'Should leave text without secrets untouched' {
            InModuleScope 'OmadaWeb.PS' {
                $Message = 'Invoke-OmadaRequest - BaseUrl: https://tenant.omada.cloud'
                Protect-LogMessage -Message $Message | Should -Be $Message
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
