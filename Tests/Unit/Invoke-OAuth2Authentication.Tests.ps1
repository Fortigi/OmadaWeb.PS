param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    $Script:Credential = New-Object System.Management.Automation.PSCredential('client-id', (ConvertTo-SecureString 'secret' -AsPlainText -Force))
}

Describe 'Invoke-OAuth2Authentication' -Tag 'Unit' {
    BeforeAll {
        InModuleScope 'OmadaWeb.PS' {
            # Each test builds its own context instead of relying on ambient variables inherited
            # from the caller's scope. Script: so the definition lands in the module's scope and
            # stays visible to the InModuleScope block of every It below. The session context is a
            # stub holding only BaseUrl, which is all this helper reads from it.
            function Script:New-TestRequestContext {
                param(
                    [hashtable]$BoundParams,
                    [string]$BaseUrl = 'https://example.omada.cloud'
                )

                return New-OmadaRequestContext -BoundParams $BoundParams -Session ([Microsoft.PowerShell.Commands.WebRequestSession]::new()) -SessionContext ([pscustomobject]@{ BaseUrl = $BaseUrl })
            }
        }
    }

    Context 'Contract' {
        It 'Should require a RequestContext' {
            InModuleScope 'OmadaWeb.PS' {
                { Invoke-OAuth2Authentication -ErrorAction Stop } | Should -Throw
            }
        }

        It 'Should return the same context instance it was given' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Credential = $Script:Credential } {
                Mock Invoke-RestMethod { [PSCustomObject]@{ access_token = 'token' } }

                $RequestContext = New-TestRequestContext -BoundParams @{ Credential = $Credential; EntraIdTenantId = 'tenant'; Headers = @{} }

                $Returned = Invoke-OAuth2Authentication -RequestContext $RequestContext

                [object]::ReferenceEquals($Returned, $RequestContext) | Should -BeTrue
            }
        }
    }

    Context 'Validation' {
        It 'Should throw when Credential is missing' {
            InModuleScope 'OmadaWeb.PS' {
                $RequestContext = New-TestRequestContext -BoundParams @{ EntraIdTenantId = 'tenant' }
                { Invoke-OAuth2Authentication -RequestContext $RequestContext -ErrorAction Stop } | Should -Throw
            }
        }

        It 'Should throw when neither EntraIdTenantId nor OAuthUri is provided' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Credential = $Script:Credential } {
                $RequestContext = New-TestRequestContext -BoundParams @{ Credential = $Credential }
                { Invoke-OAuth2Authentication -RequestContext $RequestContext -ErrorAction Stop } | Should -Throw
            }
        }
    }

    Context 'Token request' {
        It 'Should build the Entra ID token URL from EntraIdTenantId and add the Authorization header' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Credential = $Script:Credential } {
                Mock Invoke-RestMethod { [PSCustomObject]@{ access_token = 'test-token'; token_type = 'Bearer' } } -Verifiable

                $BoundParams = @{ Credential = $Credential; EntraIdTenantId = 'c1ec94c3-4a7a-4568-9321-79b0a74b8e70'; Headers = @{} }

                Invoke-OAuth2Authentication -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null

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

                Invoke-OAuth2Authentication -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null

                Should -Invoke Invoke-RestMethod -ParameterFilter { $Uri -eq 'https://idp.example.com/oauth2/token' }
                $BoundParams.Headers.Authorization | Should -Be 'Bearer custom-token'
            }
        }

        It 'Should default the scope to "<BaseUrl>/.default" when OAuthScope is not provided' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Credential = $Script:Credential } {
                Mock Invoke-RestMethod { [PSCustomObject]@{ access_token = 'token' } }

                # The default scope comes from the context's SessionContext.BaseUrl, which is the
                # only member of it this helper reads.
                $RequestContext = New-TestRequestContext -BoundParams @{ Credential = $Credential; EntraIdTenantId = 'tenant'; Headers = @{} }

                Invoke-OAuth2Authentication -RequestContext $RequestContext | Out-Null

                Should -Invoke Invoke-RestMethod -ParameterFilter { $Body.scope -eq 'https://example.omada.cloud/.default' }
            }
        }

        It 'Should use a custom OAuthScope when provided' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Credential = $Script:Credential } {
                Mock Invoke-RestMethod { [PSCustomObject]@{ access_token = 'token' } }

                $BoundParams = @{ Credential = $Credential; EntraIdTenantId = 'tenant'; OAuthScope = 'customScope'; Headers = @{} }

                Invoke-OAuth2Authentication -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null

                Should -Invoke Invoke-RestMethod -ParameterFilter { $Body.scope -eq 'customScope' }
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
