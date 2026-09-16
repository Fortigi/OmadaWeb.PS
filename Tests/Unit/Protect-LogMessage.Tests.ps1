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

        It 'Should mask hyphenated header-style keys in query-string style text' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message 'X-API-Key=api-key-secret&Ocp-Apim-Subscription-Key=subscription-key-secret'
                $Result | Should -Not -Match 'api-key-secret'
                $Result | Should -Not -Match 'subscription-key-secret'
            }
        }

        It 'Should mask hyphenated header-style keys in JSON text' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message '{"x-functions-key": "functions-key-secret", "Method": "POST"}'
                $Result | Should -Not -Match 'functions-key-secret'
                $Result | Should -Match 'POST'
            }
        }

        It 'Should mask bare key, sig, signature, code, passwd and passphrase pairs in free text' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message 'key=key-secret&sig=sig-secret&code=code-secret&passwd=passwd-secret&passphrase=passphrase-secret&signature=signature-secret'
                $Result | Should -Not -Match 'key-secret'
                $Result | Should -Not -Match 'sig-secret'
                $Result | Should -Not -Match 'code-secret'
                $Result | Should -Not -Match 'passwd-secret'
                $Result | Should -Not -Match 'passphrase-secret'
                $Result | Should -Not -Match 'signature-secret'
            }
        }

        It 'Should mask bare key and sig only as exact JSON keys, never as a substring of another key' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message '{"key": "key-secret", "sig": "sig-secret"}'
                $Result | Should -Not -Match 'key-secret'
                $Result | Should -Not -Match 'sig-secret'
            }
        }

        It 'Should keep a bare code member in JSON text, which carries the AADSTS/sign-in error code' {
            InModuleScope 'OmadaWeb.PS' {
                Protect-LogMessage -Message '{"code":"AADSTS50058"}' | Should -Match 'AADSTS50058'
            }
        }

        It 'Should mask an OAuth authorization code in a redirect URL query string while keeping the rest' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message 'https://host/cb?code=abc123&state=s'
                $Result | Should -Not -Match 'abc123'
                $Result | Should -Match 'state=s'
            }
        }

        It 'Should leave a bare "code" outside a query string untouched' {
            InModuleScope 'OmadaWeb.PS' {
                $Message = 'status code=401'
                Protect-LogMessage -Message $Message | Should -Be $Message
            }
        }

        It 'Should mask an Azure SAS signature in a URL query string' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message 'https://acct.blob.core.windows.net/c/b?sig=abc123%3D&se=2026-01-01'
                $Result | Should -Not -Match 'abc123'
                $Result | Should -Match 'se=2026-01-01'
            }
        }

        It 'Should mask a bare key=value pair but not key preceded by "-" or "."' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message 'key=key-secret&x.key=untouched-secret&some-key=also-untouched'
                $Result | Should -Not -Match 'key=key-secret'
                $Result | Should -Match 'x.key=untouched-secret'
                $Result | Should -Match 'some-key=also-untouched'
            }
        }

        It 'Should leave StatusCode, monkey and statuscode untouched' {
            InModuleScope 'OmadaWeb.PS' {
                $Message = 'StatusCode=200&monkey=1&statuscode=200'
                Protect-LogMessage -Message $Message | Should -Be $Message
            }
        }
    }

    Context 'Credentials in URLs' {
        It 'Should mask user-info embedded in a URL' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message 'Connecting to https://svc_user:Sup3rSecret!@tenant.omada.cloud/OData'
                $Result | Should -Not -Match 'Sup3rSecret'
                $Result | Should -Not -Match 'svc_user'
                $Result | Should -Match 'tenant\.omada\.cloud/OData'
            }
        }

        It 'Should leave a URL without user-info untouched' {
            InModuleScope 'OmadaWeb.PS' {
                $Message = 'Connecting to https://tenant.omada.cloud/OData'
                Protect-LogMessage -Message $Message | Should -Be $Message
            }
        }

        It 'Should mask a token embedded as URL user-info with no colon, as a PAT would be' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message 'Fetching https://ghp_Sup3rSecretToken@github.com/org/repo.git'
                $Result | Should -Not -Match 'ghp_Sup3rSecretToken'
                $Result | Should -Match 'github\.com/org/repo\.git'
            }
        }

        It 'Should leave a plain email address with no scheme untouched' {
            InModuleScope 'OmadaWeb.PS' {
                $Message = 'Contact mark@example.com for access'
                Protect-LogMessage -Message $Message | Should -Be $Message
            }
        }
    }

    Context 'Cookies' {
        It 'Should mask every cookie in a request Cookie header, whatever it is called' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message 'Cookie: a=1; oisauthtoken=x'
                $Result | Should -Not -Match 'a=1'
                $Result | Should -Not -Match 'oisauthtoken=x'
                $Result | Should -Match 'Cookie:'
            }
        }

        It 'Should mask both cookies in "Cookie: a=1; b=2"' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message 'Cookie: a=1; b=2'
                $Result | Should -Not -Match 'a=1'
                $Result | Should -Not -Match 'b=2'
            }
        }

        It 'Should not let the Cookie-header rule reach into a Set-Cookie line and mask its attributes' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message 'Set-Cookie: oisauthtoken=cookie-secret-value; Path=/; HttpOnly'
                $Result | Should -Not -Match 'cookie-secret-value'
                $Result | Should -Match 'Path=/'
                $Result | Should -Match 'HttpOnly'
            }
        }

        It 'Should mask a JSON name/value pair naming a cookie regardless of field order' {
            InModuleScope 'OmadaWeb.PS' {
                $NameFirst = Protect-LogMessage -Message '{"name":"oisauthtoken","value":"cookie-secret-value"}'
                $NameFirst | Should -Not -Match 'cookie-secret-value'

                $ValueFirst = Protect-LogMessage -Message '{"value":"cookie-secret-value","name":"oisauthtoken"}'
                $ValueFirst | Should -Not -Match 'cookie-secret-value'
            }
        }
    }

    Context 'Bearer token character set' {
        It 'Should mask a bearer token containing tilde, percent and exclamation characters' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = Protect-LogMessage -Message 'Authorization: Bearer abc~123%45!xyz=='
                $Result | Should -Not -Match 'abc~123%45!xyz'
                $Result | Should -Match 'Bearer \*\*\*REDACTED\*\*\*'
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
