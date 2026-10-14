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
            # $PSBoundParameters inside the mock body does not reliably reflect UseBasicParsing on
            # Windows PowerShell 5.1 (ContainsKey came back $false there even though it was passed),
            # so the parameter is asserted through Should -Invoke's own ParameterFilter instead, where
            # $UseBasicParsing is bound directly to the value the call actually carried.
            Mock Invoke-RestMethod { [PSCustomObject]@{ access_token = 'token' } }

            Invoke-OAuthTokenRequest -Uri 'https://idp.example.com/token' -Body @{ grant_type = 'client_credentials' } | Out-Null

            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { [bool]$UseBasicParsing -eq ($PSVersionTable.PSVersion.Major -lt 6) }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
