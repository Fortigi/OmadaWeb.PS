param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Set-Body' -Tag 'Unit' {
    Context 'Missing Body' {
        It 'Should throw a terminating error when -Body is empty' {
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{ Method = 'POST'; Headers = @{} ; Body = $null }
                { Set-Body -ErrorAction Stop } | Should -Throw
            }
        }
    }

    Context 'Content-Type header' {
        It 'Should add Content-Type application/json when not present' {
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{ Method = 'POST'; Headers = @{} ; Body = @{ key = 'value' } }
                Set-Body
                $BoundParams.Headers.'Content-Type' | Should -Be 'application/json'
            }
        }

        It 'Should overwrite an existing Content-Type header with application/json' {
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{ Method = 'POST'; Headers = @{ 'Content-Type' = 'text/plain' } ; Body = @{ key = 'value' } }
                Set-Body
                $BoundParams.Headers.'Content-Type' | Should -Be 'application/json'
            }
        }
    }

    Context 'Body conversion' {
        It 'Should convert a Hashtable body to JSON' {
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{ Method = 'POST'; Headers = @{} ; Body = @{ key = 'value' } }
                Set-Body
                $BoundParams.Body | Should -BeOfType [string]
                ($BoundParams.Body | ConvertFrom-Json).key | Should -Be 'value'
            }
        }

        It 'Should convert an ordered dictionary body to JSON' {
            InModuleScope 'OmadaWeb.PS' {
                $Ordered = [ordered]@{ key = 'value' }
                $BoundParams = @{ Method = 'POST'; Headers = @{} ; Body = $Ordered }
                Set-Body
                ($BoundParams.Body | ConvertFrom-Json).key | Should -Be 'value'
            }
        }

        It 'Should convert a PSCustomObject body to JSON' {
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{ Method = 'POST'; Headers = @{} ; Body = [PSCustomObject]@{ key = 'value' } }
                Set-Body
                ($BoundParams.Body | ConvertFrom-Json).key | Should -Be 'value'
            }
        }

        It 'Should serialize a deeply nested body without truncation' {
            InModuleScope 'OmadaWeb.PS' {
                $NestedBody = @{
                    L1 = @{
                        L2 = @{
                            L3 = @{
                                L4 = @{
                                    L5 = @{
                                        Value = 'deep'
                                    }
                                }
                            }
                        }
                    }
                }
                $BoundParams = @{ Method = 'POST'; Headers = @{} ; Body = $NestedBody }
                Set-Body
                $BoundParams.Body | Should -Not -Match 'System\.Collections\.Hashtable'
                ($BoundParams.Body | ConvertFrom-Json).L1.L2.L3.L4.L5.Value | Should -Be 'deep'
            }
        }

        It 'Should serialize nested arrays of objects' {
            InModuleScope 'OmadaWeb.PS' {
                $NestedBody = @{
                    IDENTITY = @{
                        ASSIGNMENTS = @(
                            @{ Id = 1 ; Resource = @{ Name = 'FirstResource' } }
                            @{ Id = 2 ; Resource = @{ Name = 'SecondResource' } }
                        )
                    }
                }
                $BoundParams = @{ Method = 'POST'; Headers = @{} ; Body = $NestedBody }
                Set-Body
                $BoundParams.Body | Should -Not -Match 'System\.Collections\.Hashtable'
                $Result = $BoundParams.Body | ConvertFrom-Json
                ($Result.IDENTITY.ASSIGNMENTS | Measure-Object).Count | Should -Be 2
                $Result.IDENTITY.ASSIGNMENTS[1].Resource.Name | Should -Be 'SecondResource'
            }
        }

        It 'Should leave a raw string body untouched' {
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{ Method = 'POST'; Headers = @{} ; Body = '<xml>raw</xml>' }
                Set-Body
                $BoundParams.Body | Should -Be '<xml>raw</xml>'
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
