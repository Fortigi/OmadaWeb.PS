param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    $Script:CreatedKey = [System.Security.Cryptography.RSA]::Create(2048)
    $CertificateRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new('CN=OmadaWeb.PS certificate resolution test'),
        $Script:CreatedKey,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $SelfSignedCertificate = $CertificateRequest.CreateSelfSigned([System.DateTimeOffset]::UtcNow.AddDays(-1), [System.DateTimeOffset]::UtcNow.AddDays(1))

    $Script:CertificateFilePassword = ConvertTo-SecureString 'omadaweb-test' -AsPlainText -Force
    $Script:CertificateFilePath = Join-Path ([System.IO.Path]::GetTempPath()) ("OmadaWeb.PS-{0}.pfx" -f [guid]::NewGuid())
    [System.IO.File]::WriteAllBytes($Script:CertificateFilePath, $SelfSignedCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, 'omadaweb-test'))

    $Script:TestCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $Script:CertificateFilePath,
        $Script:CertificateFilePassword,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
    $Script:PublicOnlyCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($SelfSignedCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))

    # The store lookup is the one path that cannot be exercised without touching the store, so the
    # test certificate is installed into the current user's personal store for the duration of the
    # run and removed again in AfterAll. CurrentUser needs no elevation, and the certificate is
    # self-signed and valid for a day, so nothing outside this run can be affected by it.
    $Script:StoreCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $Script:CertificateFilePath,
        $Script:CertificateFilePassword,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
    $Script:CertificateStore = [System.Security.Cryptography.X509Certificates.X509Store]::new(
        [System.Security.Cryptography.X509Certificates.StoreName]::My,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser)
    $Script:CertificateStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $Script:CertificateStore.Add($Script:StoreCertificate)
    $Script:CertificateStore.Close()

    $Script:Thumbprint = $Script:TestCertificate.Thumbprint
}

Describe 'Get-OAuthClientCertificate' -Tag 'Unit' {
    Context 'No certificate requested' {
        It 'Should return nothing when no certificate source is supplied' {
            InModuleScope 'OmadaWeb.PS' {
                # This is how the caller learns that the secret flow applies, so it has to be a
                # quiet $null rather than an error.
                Get-OAuthClientCertificate | Should -BeNullOrEmpty
            }
        }

        It 'Should throw when a password is supplied without a file to open with it' {
            InModuleScope 'OmadaWeb.PS' {
                # The message names the public parameter, not this helper's own: it is what the user
                # of Invoke-OmadaRestMethod sees, and -CertificatePath does not exist there.
                { Get-OAuthClientCertificate -CertificatePassword (ConvertTo-SecureString 'x' -AsPlainText -Force) -ErrorAction Stop } | Should -Throw '*without -OAuthCertificatePath*'
            }
        }
    }

    Context 'A password with nothing to open' {
        It 'Should throw when a password accompanies a thumbprint' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Thumbprint = $Script:Thumbprint } {
                # The thumbprint would resolve perfectly well, so the request would succeed and the
                # password would be silently ignored - leaving the caller believing the certificate
                # came from a file it never read.
                { Get-OAuthClientCertificate -CertificateThumbprint $Thumbprint -CertificatePassword (ConvertTo-SecureString 'x' -AsPlainText -Force) -ErrorAction Stop } | Should -Throw '*without -OAuthCertificatePath*'
            }
        }

        It 'Should throw when a password accompanies an already loaded certificate' {
            {
                InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:TestCertificate } {
                    Get-OAuthClientCertificate -Certificate $Certificate -CertificatePassword (ConvertTo-SecureString 'x' -AsPlainText -Force) -ErrorAction Stop
                }
            } | Should -Throw '*without -OAuthCertificatePath*'
        }
    }

    Context 'More than one source' {
        It 'Should throw rather than pick one' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Thumbprint = $Script:Thumbprint; Path = $Script:CertificateFilePath } {
                { Get-OAuthClientCertificate -CertificateThumbprint $Thumbprint -CertificatePath $Path -ErrorAction Stop } | Should -Throw '*More than one client certificate*'
            }
        }
    }

    Context 'From an object' {
        It 'Should return the certificate it was given' {
            $Resolved = InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:TestCertificate } {
                Get-OAuthClientCertificate -Certificate $Certificate
            }

            $Resolved.Thumbprint | Should -Be $Script:Thumbprint
        }

        It 'Should throw for a certificate without a private key' {
            {
                InModuleScope 'OmadaWeb.PS' -Parameters @{ Certificate = $Script:PublicOnlyCertificate } {
                    Get-OAuthClientCertificate -Certificate $Certificate -ErrorAction Stop
                }
            } | Should -Throw '*has no private key*'
        }
    }

    Context 'From the certificate store' {
        It 'Should find the certificate by thumbprint' {
            $Resolved = InModuleScope 'OmadaWeb.PS' -Parameters @{ Thumbprint = $Script:Thumbprint } {
                Get-OAuthClientCertificate -CertificateThumbprint $Thumbprint
            }

            $Resolved.Thumbprint | Should -Be $Script:Thumbprint
            $Resolved.HasPrivateKey | Should -BeTrue
        }

        It 'Should accept a thumbprint as the Windows certificate dialog renders it' {
            # Spaces between the byte pairs, and lower case, are what a copy out of the certificate
            # dialog and out of the Entra portal respectively look like.
            $Spaced = (($Script:Thumbprint.ToLowerInvariant() -split '(..)' | Where-Object { $_ }) -join ' ')

            $Resolved = InModuleScope 'OmadaWeb.PS' -Parameters @{ Thumbprint = $Spaced } {
                Get-OAuthClientCertificate -CertificateThumbprint $Thumbprint
            }

            $Resolved.Thumbprint | Should -Be $Script:Thumbprint
        }

        It 'Should throw for something that is not a thumbprint at all' {
            InModuleScope 'OmadaWeb.PS' {
                { Get-OAuthClientCertificate -CertificateThumbprint 'my signing certificate' -ErrorAction Stop } | Should -Throw '*is not a certificate thumbprint*'
            }
        }

        It 'Should throw when no certificate with that thumbprint is installed' {
            InModuleScope 'OmadaWeb.PS' {
                { Get-OAuthClientCertificate -CertificateThumbprint ('0' * 40) -ErrorAction Stop } | Should -Throw "*was found in 'CurrentUser\My' or 'LocalMachine\My'*"
            }
        }
    }

    Context 'From a file' {
        It 'Should open a password protected PKCS#12 file' {
            $Resolved = InModuleScope 'OmadaWeb.PS' -Parameters @{ Path = $Script:CertificateFilePath; Password = $Script:CertificateFilePassword } {
                Get-OAuthClientCertificate -CertificatePath $Path -CertificatePassword $Password
            }

            $Resolved.Thumbprint | Should -Be $Script:Thumbprint
            $Resolved.HasPrivateKey | Should -BeTrue
        }

        It 'Should throw when the file does not exist' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Path = (Join-Path ([System.IO.Path]::GetTempPath()) 'OmadaWeb.PS-does-not-exist.pfx') } {
                { Get-OAuthClientCertificate -CertificatePath $Path -ErrorAction Stop } | Should -Throw '*does not exist*'
            }
        }

        It 'Should throw when the password is wrong' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Path = $Script:CertificateFilePath } {
                { Get-OAuthClientCertificate -CertificatePath $Path -CertificatePassword (ConvertTo-SecureString 'wrong' -AsPlainText -Force) -ErrorAction Stop } | Should -Throw '*could not be opened with a usable private key*'
            }
        }
    }
}

AfterAll {
    if ($null -ne $Script:CertificateStore -and $null -ne $Script:StoreCertificate) {
        try {
            $Script:CertificateStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
            $Script:CertificateStore.Remove($Script:StoreCertificate)
        }
        finally {
            $Script:CertificateStore.Close()
        }
    }

    if ($null -ne $Script:CertificateFilePath -and (Test-Path -LiteralPath $Script:CertificateFilePath)) {
        Remove-Item -LiteralPath $Script:CertificateFilePath -Force -ErrorAction SilentlyContinue
    }

    if ($null -ne $Script:CreatedKey) {
        $Script:CreatedKey.Dispose()
    }

    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
