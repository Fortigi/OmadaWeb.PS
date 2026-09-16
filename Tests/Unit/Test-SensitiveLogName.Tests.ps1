param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Test-SensitiveLogName' -Tag 'Unit' {
    Context 'Substring patterns' {
        It 'Should match a name containing a substring pattern' {
            InModuleScope 'OmadaWeb.PS' {
                Test-SensitiveLogName -Name 'X-CSRF-Token' -SubstringPatterns @('csrf') -ExactPatterns @() | Should -BeTrue
            }
        }

        It 'Should not match a name that contains none of the substring patterns' {
            InModuleScope 'OmadaWeb.PS' {
                Test-SensitiveLogName -Name 'Method' -SubstringPatterns @('csrf') -ExactPatterns @() | Should -BeFalse
            }
        }
    }

    Context 'Exact patterns' {
        It 'Should match a name that exactly equals an exact pattern' {
            InModuleScope 'OmadaWeb.PS' {
                Test-SensitiveLogName -Name 'key' -SubstringPatterns @() -ExactPatterns @('key') | Should -BeTrue
            }
        }

        It 'Should not match an exact pattern when it is only part of the name' {
            InModuleScope 'OmadaWeb.PS' {
                Test-SensitiveLogName -Name 'StatusCode' -SubstringPatterns @() -ExactPatterns @('code') | Should -BeFalse
            }
        }
    }

    Context 'Normalization' {
        It 'Should ignore hyphens and underscores when matching a substring pattern' {
            InModuleScope 'OmadaWeb.PS' {
                Test-SensitiveLogName -Name 'X-API-Key' -SubstringPatterns @('apikey') -ExactPatterns @() | Should -BeTrue
                Test-SensitiveLogName -Name 'x_functions_key' -SubstringPatterns @('functionskey') -ExactPatterns @() | Should -BeTrue
            }
        }

        It 'Should ignore hyphens and underscores when matching an exact pattern' {
            InModuleScope 'OmadaWeb.PS' {
                Test-SensitiveLogName -Name 'x-sig' -SubstringPatterns @() -ExactPatterns @('xsig') | Should -BeTrue
            }
        }

        It 'Should be case-insensitive' {
            InModuleScope 'OmadaWeb.PS' {
                Test-SensitiveLogName -Name 'APIKEY' -SubstringPatterns @('apikey') -ExactPatterns @() | Should -BeTrue
            }
        }
    }

    Context 'Negatives against the module patterns' {
        It 'Should not treat StatusCode, Keys, Description, KeyCount, HashCode or Design as sensitive' {
            InModuleScope 'OmadaWeb.PS' {
                foreach ($Name in @('StatusCode', 'Keys', 'Description', 'KeyCount', 'HashCode', 'Design')) {
                    Test-SensitiveLogName -Name $Name -SubstringPatterns $Script:SensitiveLogNameSubstringPatterns -ExactPatterns $Script:SensitiveLogNameExactPatterns | Should -BeFalse -Because "$Name should not be redacted"
                }
            }
        }
    }

    Context 'Edge cases' {
        It 'Should not match an empty name against any pattern' {
            InModuleScope 'OmadaWeb.PS' {
                Test-SensitiveLogName -Name '' -SubstringPatterns @('token') -ExactPatterns @('key') | Should -BeFalse
            }
        }

        It 'Should not match a null name against any pattern' {
            InModuleScope 'OmadaWeb.PS' {
                Test-SensitiveLogName -Name $null -SubstringPatterns @('token') -ExactPatterns @('key') | Should -BeFalse
            }
        }

        It 'Should return false when both pattern lists are empty' {
            InModuleScope 'OmadaWeb.PS' {
                Test-SensitiveLogName -Name 'Token' -SubstringPatterns @() -ExactPatterns @() | Should -BeFalse
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
