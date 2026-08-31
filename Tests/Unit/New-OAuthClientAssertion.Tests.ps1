param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    # The assertion is a signature, so the only assertion worth making about it is that the signature
    # verifies. That needs a real key pair, which is built in memory here rather than taken from the
    # certificate store: nothing is installed, nothing has to be cleaned up, and the test does not
    # depend on what happens to be present on the machine running it.
    $Script:SigningKey = [System.Security.Cryptography.RSA]::Create(2048)
    $CertificateRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new('CN=OmadaWeb.PS assertion test'),
        $Script:SigningKey,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $SelfSignedCertificate = $CertificateRequest.CreateSelfSigned([System.DateTimeOffset]::UtcNow.AddDays(-1), [System.DateTimeOffset]::UtcNow.AddDays(1))
    # Exported and re-imported rather than used as returned. On Windows PowerShell's .NET Framework
    # the certificate CreateSelfSigned hands back does not always carry a private key the certificate
    # object itself can sign with; a PKCS#12 round trip produces one that does, on both engines.
    $Script:TestCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $SelfSignedCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, 'omadaweb-test'),
        'omadaweb-test',
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)

    # The same certificate without its private key, which is what a certificate imported from a .cer
    # file looks like.
    $Script:PublicOnlyCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($Script:TestCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))

    function Script:ConvertFrom-Base64UrlText {
        param(
            [string]$Text
        )

        $Padded = $Text.Replace('-', '+').Replace('_', '/')
        switch ($Padded.Length % 4) {
            2 {
                $Padded += '=='
            }
            3 {
                $Padded += '='
            }
        }

        return [Convert]::FromBase64String($Padded)
    }

    function Script:ConvertFrom-JwtSegment {
        param(
            [string]$Segment
        )

        return ([System.Text.Encoding]::UTF8.GetString((ConvertFrom-Base64UrlText -Text $Segment)) | ConvertFrom-Json)
    }
}

Describe 'New-OAuthClientAssertion' -Tag 'Unit' {
    Context 'Shape' {
        It 'Should return three dot-separated segments' {
            $Assertion = InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:TestCertificate } {
                New-OAuthClientAssertion -ClientId 'a1b2c3d4-0000-0000-0000-000000000000' -Audience 'https://login.microsoftonline.com/tenant/oauth2/v2.0/token' -Certificate $Certificate
            }

            @($Assertion -split '\.').Count | Should -Be 3
        }

        It 'Should name RS256 and identify the certificate by its SHA-1 hash in the header' {
            $Assertion = InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:TestCertificate } {
                New-OAuthClientAssertion -ClientId 'client' -Audience 'https://idp.example.com/token' -Certificate $Certificate
            }

            $Header = ConvertFrom-JwtSegment -Segment ($Assertion -split '\.')[0]

            $Header.alg | Should -Be 'RS256'
            $Header.typ | Should -Be 'JWT'
            # x5t is how the provider picks the right public key when the application has more than
            # one certificate registered, so it has to be this certificate's hash and not any other.
            [BitConverter]::ToString((ConvertFrom-Base64UrlText -Text $Header.x5t)) | Should -Be ([BitConverter]::ToString($Script:TestCertificate.GetCertHash()))
        }
    }

    Context 'Claims' {
        It 'Should bind the assertion to the token endpoint and to the client id' {
            $Assertion = InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:TestCertificate } {
                New-OAuthClientAssertion -ClientId 'client-id' -Audience 'https://idp.example.com/oauth2/token' -Certificate $Certificate
            }

            $Payload = ConvertFrom-JwtSegment -Segment ($Assertion -split '\.')[1]

            $Payload.aud | Should -Be 'https://idp.example.com/oauth2/token'
            $Payload.iss | Should -Be 'client-id'
            $Payload.sub | Should -Be 'client-id'
        }

        It 'Should make every assertion single use' {
            $First, $Second = InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:TestCertificate } {
                New-OAuthClientAssertion -ClientId 'client' -Audience 'https://idp.example.com/token' -Certificate $Certificate
                New-OAuthClientAssertion -ClientId 'client' -Audience 'https://idp.example.com/token' -Certificate $Certificate
            }

            $FirstJti = (ConvertFrom-JwtSegment -Segment ($First -split '\.')[1]).jti
            $SecondJti = (ConvertFrom-JwtSegment -Segment ($Second -split '\.')[1]).jti

            $FirstJti | Should -Not -BeNullOrEmpty
            $FirstJti | Should -Not -Be $SecondJti
        }

        It 'Should start the validity window in the past so a skewed clock does not fail the sign-in' {
            $Assertion = InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:TestCertificate } {
                New-OAuthClientAssertion -ClientId 'client' -Audience 'https://idp.example.com/token' -Certificate $Certificate
            }

            $Payload = ConvertFrom-JwtSegment -Segment ($Assertion -split '\.')[1]

            $Payload.nbf | Should -BeLessThan $Payload.iat
            $Payload.exp | Should -Be ($Payload.iat + 600)
        }

        It 'Should honour a shorter requested lifetime' {
            $Assertion = InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:TestCertificate } {
                New-OAuthClientAssertion -ClientId 'client' -Audience 'https://idp.example.com/token' -Certificate $Certificate -LifetimeSeconds 120
            }

            $Payload = ConvertFrom-JwtSegment -Segment ($Assertion -split '\.')[1]

            $Payload.exp | Should -Be ($Payload.iat + 120)
        }
    }

    Context 'Signature' {
        It 'Should sign the header and payload with the certificate private key' {
            $Assertion = InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:TestCertificate } {
                New-OAuthClientAssertion -ClientId 'client' -Audience 'https://idp.example.com/token' -Certificate $Certificate
            }

            $Segments = $Assertion -split '\.'
            $SigningInput = [System.Text.Encoding]::UTF8.GetBytes(("{0}.{1}" -f $Segments[0], $Segments[1]))
            $Signature = ConvertFrom-Base64UrlText -Text $Segments[2]

            # This is the check the identity provider itself performs. If it passes here, the only
            # thing between this token and a successful sign-in is the tenant configuration.
            $PublicKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($Script:TestCertificate)
            $PublicKey.VerifyData($SigningInput, $Signature, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1) | Should -BeTrue
        }

        It 'Should not verify against a tampered payload' {
            $Assertion = InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:TestCertificate } {
                New-OAuthClientAssertion -ClientId 'client' -Audience 'https://idp.example.com/token' -Certificate $Certificate
            }

            $Segments = $Assertion -split '\.'
            $TamperedInput = [System.Text.Encoding]::UTF8.GetBytes(("{0}.{1}" -f $Segments[0], $Segments[1].Substring(0, $Segments[1].Length - 2)))
            $Signature = ConvertFrom-Base64UrlText -Text $Segments[2]

            $PublicKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($Script:TestCertificate)
            $PublicKey.VerifyData($TamperedInput, $Signature, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1) | Should -BeFalse
        }
    }

    Context 'Validation' {
        It 'Should throw for a certificate without a private key' {
            {
                InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:PublicOnlyCertificate } {
                    New-OAuthClientAssertion -ClientId 'client' -Audience 'https://idp.example.com/token' -Certificate $Certificate -ErrorAction Stop
                }
            } | Should -Throw '*no private key*'
        }
    }
}

AfterAll {
    if ($null -ne $Script:SigningKey) {
        $Script:SigningKey.Dispose()
    }

    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
