param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    $Script:Credential = New-Object System.Management.Automation.PSCredential('client-id', (ConvertTo-SecureString 'secret' -AsPlainText -Force))

    # A real key pair, built in memory, so the certificate flow can be asserted on the request body
    # it actually produces rather than on a stub. Nothing is installed and nothing has to be cleaned
    # up; Get-OAuthClientCertificate.Tests.ps1 covers where a certificate is found.
    $Script:CertificateKey = [System.Security.Cryptography.RSA]::Create(2048)
    $CertificateRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new('CN=OmadaWeb.PS OAuth test'),
        $Script:CertificateKey,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $SelfSignedCertificate = $CertificateRequest.CreateSelfSigned([System.DateTimeOffset]::UtcNow.AddDays(-1), [System.DateTimeOffset]::UtcNow.AddDays(1))
    $Script:ClientCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $SelfSignedCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, 'omadaweb-test'),
        'omadaweb-test',
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)

    function Script:ConvertFrom-JwtPayload {
        param(
            [string]$Assertion
        )

        $Padded = ($Assertion -split '\.')[1].Replace('-', '+').Replace('_', '/')
        switch ($Padded.Length % 4) {
            2 {
                $Padded += '=='
            }
            3 {
                $Padded += '='
            }
        }

        return ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Padded)) | ConvertFrom-Json)
    }
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
                # Asserted through the parameter metadata rather than by calling the function
                # without it: in an interactive host a missing mandatory parameter prompts rather
                # than throwing, which would hang the run.
                (Get-Command Invoke-OAuth2Authentication).Parameters['RequestContext'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
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

        It 'Should throw when a certificate is supplied without a client id' {
            {
                InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:ClientCertificate } {
                    # The secret flow takes the client id from the credential's user name. There is no
                    # credential here, so it has to be given explicitly and saying so is the only
                    # useful answer.
                    $RequestContext = New-TestRequestContext -BoundParams @{ OAuthCertificate = $Certificate; EntraIdTenantId = 'tenant'; Headers = @{} }
                    Invoke-OAuth2Authentication -RequestContext $RequestContext -ErrorAction Stop
                }
            } | Should -Throw '*No client id was provided*'
        }
    }

    Context 'Certificate credential' {
        It 'Should send a signed client assertion instead of a client secret' {
            $Body = InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:ClientCertificate } {
                $Captured = $null
                Mock Invoke-RestMethod {
                    $Script:CapturedBody = $Body
                    return [PSCustomObject]@{ access_token = 'certificate-token' }
                }

                $BoundParams = @{
                    ClientId         = 'a1b2c3d4-0000-0000-0000-000000000000'
                    OAuthCertificate = $Certificate
                    EntraIdTenantId  = 'c1ec94c3-4a7a-4568-9321-79b0a74b8e70'
                    Headers          = @{}
                }

                Invoke-OAuth2Authentication -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null

                $BoundParams.Headers.Authorization | Should -Be 'Bearer certificate-token'
                $Captured = $Script:CapturedBody
                return $Captured
            }

            $Body.grant_type | Should -Be 'client_credentials'
            $Body.client_id | Should -Be 'a1b2c3d4-0000-0000-0000-000000000000'
            $Body.client_assertion_type | Should -Be 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
            $Body.client_assertion | Should -Not -BeNullOrEmpty
            # The secret field must be absent, not empty: an empty client_secret alongside an
            # assertion is rejected by Entra ID as a malformed request.
            $Body.ContainsKey('client_secret') | Should -BeFalse
        }

        It 'Should bind the assertion to the token endpoint that is actually called' {
            $Body = InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:ClientCertificate } {
                Mock Invoke-RestMethod {
                    $Script:CapturedBody = $Body
                    return [PSCustomObject]@{ access_token = 'token' }
                }

                $BoundParams = @{
                    ClientId         = 'client'
                    OAuthCertificate = $Certificate
                    OAuthUri         = 'https://dev-505878.okta.com/oauth2/ausc0u4lq9sPySN5W4x7/v1/token'
                    OAuthScope       = 'omadaIdentityCloud'
                    Headers          = @{}
                }

                Invoke-OAuth2Authentication -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null

                return $Script:CapturedBody
            }

            $Payload = ConvertFrom-JwtPayload -Assertion $Body.client_assertion

            $Payload.aud | Should -Be 'https://dev-505878.okta.com/oauth2/ausc0u4lq9sPySN5W4x7/v1/token'
            $Payload.iss | Should -Be 'client'
            $Payload.sub | Should -Be 'client'
        }

        It 'Should not take the client id from the credential when a certificate is used' {
            {
                InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:ClientCertificate; Credential = $Script:Credential } {
                    Mock Invoke-RestMethod { [PSCustomObject]@{ access_token = 'token' } }

                    # A credential is present, so its user name could be read - and deliberately is
                    # not. It may belong to something else entirely, and an assertion signed for the
                    # wrong application fails with an error from the identity provider that names
                    # neither cause nor cure.
                    $BoundParams = @{ Credential = $Credential; OAuthCertificate = $Certificate; EntraIdTenantId = 'tenant'; Headers = @{} }

                    Invoke-OAuth2Authentication -RequestContext (New-TestRequestContext -BoundParams $BoundParams) -WarningAction SilentlyContinue -ErrorAction Stop
                }
            } | Should -Throw '*No client id was provided*'
        }

        It 'Should warn that the client secret is ignored when both credentials are supplied' {
            $Warnings = InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:ClientCertificate; Credential = $Script:Credential } {
                Mock Invoke-RestMethod { [PSCustomObject]@{ access_token = 'token' } }

                $BoundParams = @{ ClientId = 'client'; Credential = $Credential; OAuthCertificate = $Certificate; EntraIdTenantId = 'tenant'; Headers = @{} }

                Invoke-OAuth2Authentication -RequestContext (New-TestRequestContext -BoundParams $BoundParams) -WarningVariable CapturedWarnings -WarningAction SilentlyContinue | Out-Null

                return $CapturedWarnings
            }

            $Warnings -join "`n" | Should -BeLike '*client secret in the credential is ignored*'
        }

        It 'Should still send a client secret when no certificate is supplied' {
            $Body = InModuleScope 'OmadaWeb.PS' -Parameters @{ Credential = $Script:Credential } {
                Mock Invoke-RestMethod {
                    $Script:CapturedBody = $Body
                    return [PSCustomObject]@{ access_token = 'token' }
                }

                $BoundParams = @{ Credential = $Credential; EntraIdTenantId = 'tenant'; Headers = @{} }

                Invoke-OAuth2Authentication -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null

                return $Script:CapturedBody
            }

            $Body.client_secret | Should -Be 'secret'
            $Body.ContainsKey('client_assertion') | Should -BeFalse
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
    if ($null -ne $Script:CertificateKey) {
        $Script:CertificateKey.Dispose()
    }

    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
