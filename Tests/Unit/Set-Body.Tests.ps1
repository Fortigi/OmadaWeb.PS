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
