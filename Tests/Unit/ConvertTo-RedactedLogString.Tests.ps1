param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'ConvertTo-RedactedLogString' -Tag 'Unit' {
    Context 'Name-based masking' {
        It 'Should mask a value whose key names a secret' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = ConvertTo-RedactedLogString -InputObject @{ Authorization = 'Basic dXNlcjpwYXNzd29yZA==' }
                $Result | Should -Not -Match 'dXNlcjpwYXNzd29yZA'
                $Result | Should -Match '\*\*\*REDACTED\*\*\*'
            }
        }

        It 'Should match the key as a case-insensitive substring so composite names are covered' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = ConvertTo-RedactedLogString -InputObject @{
                    'X-CSRF-Token'  = 'csrf-secret-value'
                    'RefreshToken'  = 'refresh-secret-value'
                    'oisauthtoken'  = 'cookie-secret-value'
                    'ClientSecret'  = 'client-secret-value'
                }
                $Result | Should -Not -Match 'csrf-secret-value'
                $Result | Should -Not -Match 'refresh-secret-value'
                $Result | Should -Not -Match 'cookie-secret-value'
                $Result | Should -Not -Match 'client-secret-value'
            }
        }

        It 'Should keep values whose key names nothing secret' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = ConvertTo-RedactedLogString -InputObject @{ Method = 'POST'; Uri = 'https://tenant.omada.cloud/OData' }
                $Result | Should -Match 'POST'
                $Result | Should -Match 'tenant\.omada\.cloud'
            }
        }
    }

    Context 'Type-based masking' {
        It 'Should keep the credential user name and never the password' {
            InModuleScope 'OmadaWeb.PS' {
                $Credential = New-Object System.Management.Automation.PSCredential('omada\svc_sql', (ConvertTo-SecureString 'Sup3rSecret!' -AsPlainText -Force))
                $Result = ConvertTo-RedactedLogString -InputObject @{ Credential = $Credential }
                $Result | Should -Match 'svc_sql'
                $Result | Should -Not -Match 'Sup3rSecret'
            }
        }

        It 'Should mask a SecureString' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = ConvertTo-RedactedLogString -InputObject @{ Anything = (ConvertTo-SecureString 'Sup3rSecret!' -AsPlainText -Force) }
                $Result | Should -Not -Match 'Sup3rSecret'
                $Result | Should -Match '\*\*\*REDACTED\*\*\*'
            }
        }

        It 'Should reduce a byte array to its length' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = ConvertTo-RedactedLogString -InputObject @{ Raw = [byte[]]@(1, 2, 3, 4, 5) }
                $Result | Should -Match 'Byte\[5\]'
            }
        }

        It 'Should reduce a WebRequestSession to its cookie count and user agent' {
            InModuleScope 'OmadaWeb.PS' {
                $Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                $Session.UserAgent = 'OmadaWeb.PS/1.0'
                $Session.Cookies.Add((New-Object System.Net.Cookie('oisauthtoken', 'cookie-secret-value', '/', 'tenant.omada.cloud')))
                $Result = ConvertTo-RedactedLogString -InputObject @{ WebSession = $Session }
                $Result | Should -Not -Match 'cookie-secret-value'
                $Result | Should -Match 'WebRequestSession\(Cookies=1'
                $Result | Should -Match 'OmadaWeb.PS/1.0'
            }
        }

        It 'Should mask a token carried in a Uri query string' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = ConvertTo-RedactedLogString -InputObject ([System.Uri]::new('https://login.microsoftonline.com/common/callback?id_token=header.payload.signature'))
                $Result | Should -Not -Match 'header\.payload\.signature'
                $Result | Should -Match 'login\.microsoftonline\.com'
            }
        }
    }

    Context 'Free-form values the name rules cannot see' {
        It 'Should mask an auth scheme and token arriving under an unremarkable key' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = ConvertTo-RedactedLogString -InputObject @{ Note = 'retrying with Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature' }
                $Result | Should -Not -Match 'eyJhbGciOiJIUzI1NiJ9'
            }
        }
    }

    Context 'Bounds' {
        It 'Should collapse an array of more than three elements to a shape summary' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = ConvertTo-RedactedLogString -InputObject @{ Rows = @('a', 'b', 'c', 'd', 'e') }
                $Result | Should -Match 'Array\[5\] of String'
            }
        }

        It 'Should stop at the requested depth' {
            InModuleScope 'OmadaWeb.PS' {
                $Deep = @{ L1 = @{ L2 = @{ L3 = @{ L4 = 'bottom' } } } }
                $Result = ConvertTo-RedactedLogString -InputObject $Deep -MaxDepth 2
                $Result | Should -Not -Match 'bottom'
                $Result | Should -Match 'max depth 2 reached'
            }
        }

        It 'Should truncate a long string' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = ConvertTo-RedactedLogString -InputObject @{ Text = ('x' * 40) } -MaxStringLength 10
                $Result | Should -Match 'truncated, 40 chars'
            }
        }

        It 'Should not loop on a circular reference' {
            InModuleScope 'OmadaWeb.PS' {
                $Outer = [PSCustomObject]@{ Name = 'outer'; Child = $null }
                $Inner = [PSCustomObject]@{ Name = 'inner'; Parent = $Outer }
                $Outer.Child = $Inner
                $Result = ConvertTo-RedactedLogString -InputObject $Outer
                $Result | Should -Match 'circular reference'
            }
        }
    }

    Context 'Bodies and -ShapeOnly' {
        It 'Should keep body keys and value shapes but no body values' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = ConvertTo-RedactedLogString -InputObject @{ Body = @{ C_QUERY = 'SELECT * FROM dbo.Person' } }
                $Result | Should -Match 'C_QUERY'
                $Result | Should -Not -Match 'dbo\.Person'
                $Result | Should -Match 'String\(24\)'
            }
        }

        It 'Should keep keys and shapes only when -ShapeOnly is used' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = ConvertTo-RedactedLogString -InputObject @{ Name = 'Omada' } -ShapeOnly
                $Result | Should -Match 'Name'
                $Result | Should -Not -Match 'Omada'
            }
        }
    }

    Context 'Edge cases' {
        It 'Should render a null input as the literal null' {
            InModuleScope 'OmadaWeb.PS' {
                ConvertTo-RedactedLogString -InputObject $null | Should -Be 'null'
            }
        }

        It 'Should report a failure instead of returning the unredacted object' {
            InModuleScope 'OmadaWeb.PS' {
                Mock ConvertTo-RedactedLogValue { throw 'walker exploded' }
                $Result = ConvertTo-RedactedLogString -InputObject @{ Password = 'Sup3rSecret!' }
                $Result | Should -Not -Match 'Sup3rSecret'
                $Result | Should -Match 'redaction failed'
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
