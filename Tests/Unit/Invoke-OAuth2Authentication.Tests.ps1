param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    $Script:Credential = New-Object System.Management.Automation.PSCredential('client-id', (ConvertTo-SecureString 'secret' -AsPlainText -Force))
}

Describe 'Invoke-OAuth2Authentication' -Tag 'Unit' {
    Context 'Validation' {
        It 'Should throw when Credential is missing' {
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{ EntraIdTenantId = 'tenant' }
                $Script:OmadaWebBaseUrl = 'https://example.omada.cloud'
                { Invoke-OAuth2Authentication -ErrorAction Stop } | Should -Throw
            }
        }

        It 'Should throw when neither EntraIdTenantId nor OAuthUri is provided' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Credential = $Script:Credential } {
                $BoundParams = @{ Credential = $Credential }
                $Script:OmadaWebBaseUrl = 'https://example.omada.cloud'
                { Invoke-OAuth2Authentication -ErrorAction Stop } | Should -Throw
            }
        }
    }

    Context 'Token request' {
        It 'Should build the Entra ID token URL from EntraIdTenantId and add the Authorization header' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Credential = $Script:Credential } {
                Mock Invoke-RestMethod { [PSCustomObject]@{ access_token = 'test-token'; token_type = 'Bearer' } } -Verifiable

                $BoundParams = @{ Credential = $Credential; EntraIdTenantId = 'c1ec94c3-4a7a-4568-9321-79b0a74b8e70'; Headers = @{} }
                $Script:OmadaWebBaseUrl = 'https://example.omada.cloud'

                Invoke-OAuth2Authentication

                Should -Invoke Invoke-RestMethod -ParameterFilter {
                    $Uri -eq 'https://login.microsoftonline.com/c1ec94c3-4a7a-4568-9321-79b0a74b8e70/oauth2/v2.0/token'
                }
                $BoundParams.Headers.Authorization | Should -Be 'Bearer test-token'
            }
        }

        It 'Should use a custom OAuthUri when provided instead of EntraIdTenantId' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Credential = $Script:Credential } {
                Mock Invoke-RestMethod { [PSCustomObject]@{ access_token = 'custom-token' } }

                $BoundParams = @{ Credential = $Credential; OAuthUri = 'https://idp.example.com/oauth2/token'; Headers = @{} }
                $Script:OmadaWebBaseUrl = 'https://example.omada.cloud'

                Invoke-OAuth2Authentication

                Should -Invoke Invoke-RestMethod -ParameterFilter { $Uri -eq 'https://idp.example.com/oauth2/token' }
                $BoundParams.Headers.Authorization | Should -Be 'Bearer custom-token'
            }
        }

        It 'Should default the scope to "<BaseUrl>/.default" when OAuthScope is not provided' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Credential = $Script:Credential } {
                Mock Invoke-RestMethod { [PSCustomObject]@{ access_token = 'token' } }

                $BoundParams = @{ Credential = $Credential; EntraIdTenantId = 'tenant'; Headers = @{} }
                $Script:OmadaWebBaseUrl = 'https://example.omada.cloud'

                Invoke-OAuth2Authentication

                Should -Invoke Invoke-RestMethod -ParameterFilter { $Body.scope -eq 'https://example.omada.cloud/.default' }
            }
        }

        It 'Should use a custom OAuthScope when provided' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Credential = $Script:Credential } {
                Mock Invoke-RestMethod { [PSCustomObject]@{ access_token = 'token' } }

                $BoundParams = @{ Credential = $Credential; EntraIdTenantId = 'tenant'; OAuthScope = 'customScope'; Headers = @{} }
                $Script:OmadaWebBaseUrl = 'https://example.omada.cloud'

                Invoke-OAuth2Authentication

                Should -Invoke Invoke-RestMethod -ParameterFilter { $Body.scope -eq 'customScope' }
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
