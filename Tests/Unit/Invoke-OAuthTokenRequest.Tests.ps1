param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-OAuthTokenRequest' -Tag 'Unit' {
    It 'Should POST the body form-encoded to the given Uri with -ErrorAction Stop' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-RestMethod { [PSCustomObject]@{ access_token = 'token' } }

            $Body = @{ grant_type = 'client_credentials'; client_id = 'client' }
            Invoke-OAuthTokenRequest -Uri 'https://idp.example.com/token' -Body $Body | Out-Null

            Should -Invoke Invoke-RestMethod -ParameterFilter {
                $Method -eq 'Post' -and
                $Uri -eq 'https://idp.example.com/token' -and
                $ContentType -eq 'application/x-www-form-urlencoded' -and
                $ErrorAction -eq 'Stop'
            }
        }
    }

    It 'Should return the response Invoke-RestMethod produced' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-RestMethod { [PSCustomObject]@{ access_token = 'returned-token' } }

            $Result = Invoke-OAuthTokenRequest -Uri 'https://idp.example.com/token' -Body @{ grant_type = 'client_credentials' }

            $Result.access_token | Should -Be 'returned-token'
        }
    }

    It 'Should propagate a terminating error from Invoke-RestMethod' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-RestMethod { throw [System.Exception]::new('boom') }

            { Invoke-OAuthTokenRequest -Uri 'https://idp.example.com/token' -Body @{ grant_type = 'client_credentials' } -ErrorAction Stop } | Should -Throw '*boom*'
        }
    }

    It 'Should set -UseBasicParsing only on Windows PowerShell (major version below 6)' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-RestMethod {
                # Captured from inside the mock's own invocation, where $PSBoundParameters reflects
                # exactly what Invoke-OAuthTokenRequest passed on - the ParameterFilter script block
                # does not reliably expose an unbound parameter as a variable, and this engine's
                # UseBasicParsing branch is not taken at all when the test runs on PowerShell 6+.
                $Script:CapturedHasUseBasicParsing = $PSBoundParameters.ContainsKey('UseBasicParsing')
                [PSCustomObject]@{ access_token = 'token' }
            }

            Invoke-OAuthTokenRequest -Uri 'https://idp.example.com/token' -Body @{ grant_type = 'client_credentials' } | Out-Null

            if ($PSVersionTable.PSVersion.Major -lt 6) {
                $Script:CapturedHasUseBasicParsing | Should -BeTrue
            }
            else {
                $Script:CapturedHasUseBasicParsing | Should -BeFalse
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
