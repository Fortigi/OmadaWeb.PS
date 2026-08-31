function Get-OAuthClientCertificate {
    <#
    .SYNOPSIS
        Resolves the client certificate an OAuth2 client-credentials assertion is signed with.

    .DESCRIPTION
        A confidential client authenticates to its token endpoint either with a shared secret or
        with a certificate. Entra ID, and every identity provider that follows RFC 7523, accepts a
        signed JSON Web Token in place of the secret, and Microsoft's own guidance is to prefer the
        certificate: it cannot be copied out of a log or a script the way a secret can, its private
        key stays in the platform key store, and it expires on a schedule the tenant controls.

        A certificate can be named in three ways, and unattended jobs use all three:

          - By thumbprint, for a certificate already installed on the machine that runs the job.
            Both 'CurrentUser\My' and 'LocalMachine\My' are searched, in that order, because a
            scheduled task under a service account and an interactive session under a user account
            keep their certificates in different places and the caller should not have to say which.
          - By path, for a PKCS#12 (.pfx) file, with the password supplied as a SecureString.
          - As an already loaded X509Certificate2, for callers that obtain the certificate from
            somewhere this module does not know about - a Key Vault, a secret store, a provider.

        Exactly one of them may be given. Two would leave the question of which one actually signed
        the request answerable only by reading the source, and a certificate is the thing the tenant
        audits the sign-in against.

        Whichever way it arrives, the certificate must carry a usable private key. That is checked
        here rather than at signing time, so the error names the certificate the caller asked for
        instead of a failure inside the token request.

        Every error raised here reaches the user of Invoke-OmadaRestMethod or Invoke-OmadaWebRequest
        unchanged, so the messages name the public parameters - -OAuthCertificate,
        -OAuthCertificateThumbprint, -OAuthCertificatePath, -OAuthCertificatePassword - and not this
        function's own, shorter ones. Telling somebody to supply -CertificatePath when no such
        parameter exists on the command they called is worse than saying nothing.

    .PARAMETER Certificate
        An already loaded certificate, including its private key. Supplied by the caller from
        -OAuthCertificate.

    .PARAMETER CertificateThumbprint
        The thumbprint of a certificate in 'CurrentUser\My' or 'LocalMachine\My'. Spaces and other
        separators are ignored, so a thumbprint copied out of the Windows certificate dialog can be
        pasted in unchanged.

    .PARAMETER CertificatePath
        Path to a PKCS#12 (.pfx or .p12) file holding the certificate and its private key.

    .PARAMETER CertificatePassword
        The password protecting the file named by CertificatePath, as a SecureString. Omit it for a
        file that is not password protected.

    .OUTPUTS
        System.Security.Cryptography.X509Certificates.X509Certificate2, or $null when no certificate
        source was supplied at all - which is how the caller learns to fall back to the secret flow.
    #>
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [string]$CertificateThumbprint,

        [string]$CertificatePath,

        [System.Security.SecureString]$CertificatePassword
    )

    [string[]]$SuppliedSources = @()
    if ($null -ne $Certificate) {
        $SuppliedSources += "OAuthCertificate"
    }

    if (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
        $SuppliedSources += "OAuthCertificateThumbprint"
    }

    if (-not [string]::IsNullOrWhiteSpace($CertificatePath)) {
        $SuppliedSources += "OAuthCertificatePath"
    }

    if ($SuppliedSources.Count -gt 1) {
        "{0} - More than one client certificate was supplied ({1}). Provide exactly one of -OAuthCertificate, -OAuthCertificateThumbprint or -OAuthCertificatePath." -f $MyInvocation.MyCommand, ($SuppliedSources -join ", ") | Write-Error -ErrorAction "Stop"
    }

    if ($SuppliedSources.Count -eq 0) {
        if ($null -ne $CertificatePassword) {
            "{0} - OAuthCertificatePassword was supplied without -OAuthCertificatePath, so there is no certificate file to open with it." -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
        }
        return $null
    }

    if ($null -ne $Certificate) {
        if (-not $Certificate.HasPrivateKey) {
            "{0} - The certificate supplied to -OAuthCertificate (thumbprint {1}) has no private key, so it cannot sign a client assertion." -f $MyInvocation.MyCommand, $Certificate.Thumbprint | Write-Error -ErrorAction "Stop"
        }

        "{0} - Using the client certificate supplied to -OAuthCertificate. Thumbprint: {1}, subject: {2}" -f $MyInvocation.MyCommand, $Certificate.Thumbprint, $Certificate.Subject | Write-Verbose
        return $Certificate
    }

    if (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
        # A thumbprint copied from the Windows certificate dialog carries spaces, and one copied from
        # the Entra portal is lower case. Both name the same certificate, so everything that is not a
        # hexadecimal digit is dropped before the comparison the store does byte for byte.
        $NormalizedThumbprint = ($CertificateThumbprint -replace "[^0-9A-Fa-f]", "").ToUpperInvariant()
        if ($NormalizedThumbprint.Length -ne 40) {
            "{0} - '{1}' is not a certificate thumbprint. A thumbprint is the 40 hexadecimal digits of the certificate's SHA-1 hash." -f $MyInvocation.MyCommand, $CertificateThumbprint | Write-Error -ErrorAction "Stop"
        }

        $StoreLocations = @(
            [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser,
            [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
        )

        $FoundCertificates = @()
        foreach ($StoreLocation in $StoreLocations) {
            $Store = [System.Security.Cryptography.X509Certificates.X509Store]::new([System.Security.Cryptography.X509Certificates.StoreName]::My, $StoreLocation)
            try {
                $Store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
                # validOnly is deliberately $false. An expired or not-yet-trusted certificate is still
                # the certificate the caller named, and saying so is far more useful than reporting it
                # as absent - which is what a validity filter here would do.
                $FoundCertificates += @($Store.Certificates.Find([System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint, $NormalizedThumbprint, $false))
            }
            catch {
                # A machine store that cannot be opened - no permission, no such store - is not an
                # error in itself: the certificate may well be in the other location.
                "{0} - The certificate store '{1}\My' could not be searched: {2}" -f $MyInvocation.MyCommand, $StoreLocation, $PSItem.Exception.Message | Write-Verbose
            }
            finally {
                # Close() releases the store handle; Dispose() is what the type documents, and a
                # request-scoped helper in a long-running job opens two stores on every call.
                $Store.Dispose()
            }
        }

        if ($FoundCertificates.Count -eq 0) {
            "{0} - No certificate with thumbprint {1} was found in 'CurrentUser\My' or 'LocalMachine\My'. Install the certificate for the account this runs under, or supply it with -OAuthCertificatePath." -f $MyInvocation.MyCommand, $NormalizedThumbprint | Write-Error -ErrorAction "Stop"
        }

        $CertificatesWithPrivateKey = @($FoundCertificates | Where-Object { $_.HasPrivateKey })
        if ($CertificatesWithPrivateKey.Count -eq 0) {
            $FoundCertificates | ForEach-Object { $_.Dispose() }
            "{0} - The certificate with thumbprint {1} was found, but the account this runs under cannot reach its private key, so it cannot sign a client assertion. Grant that account read access to the private key, or import the certificate into its own 'CurrentUser\My' store." -f $MyInvocation.MyCommand, $NormalizedThumbprint | Write-Error -ErrorAction "Stop"
        }

        $StoreCertificate = $CertificatesWithPrivateKey[0]

        # The same certificate can be installed in both locations, and the search does not stop at
        # the first hit, so everything that is not being returned is released here.
        $FoundCertificates | Where-Object { -not [object]::ReferenceEquals($_, $StoreCertificate) } | ForEach-Object { $_.Dispose() }

        "{0} - Using the client certificate from the certificate store. Thumbprint: {1}, subject: {2}, expires: {3}" -f $MyInvocation.MyCommand, $StoreCertificate.Thumbprint, $StoreCertificate.Subject, $StoreCertificate.NotAfter | Write-Verbose
        return $StoreCertificate
    }

    if (-not (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) {
        "{0} - The certificate file '{1}' does not exist." -f $MyInvocation.MyCommand, $CertificatePath | Write-Error -ErrorAction "Stop"
    }

    $ResolvedCertificatePath = (Resolve-Path -LiteralPath $CertificatePath).ProviderPath

    # EphemeralKeySet keeps the private key in memory for the lifetime of the object instead of
    # writing it into the account's key container, which is what a job that loads the same file on
    # every run wants. It is not supported everywhere though - Windows PowerShell's .NET Framework
    # in particular - so the load is attempted with it first and repeated with the default flags
    # when either the load or the read of the private key fails. Trying the key read here rather
    # than only the constructor matters: the flag combination that fails does so at first use.
    $KeyStorageFlags = @(
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet
    )

    $LoadedCertificate = $null
    $LastLoadError = $null
    foreach ($KeyStorageFlag in $KeyStorageFlags) {
        $CandidateCertificate = $null
        try {
            # The X509Certificate2 constructor is used rather than X509CertificateLoader, which only
            # exists on .NET 9 and later and would leave Windows PowerShell without a way to open the
            # file at all.
            $CandidateCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($ResolvedCertificatePath, $CertificatePassword, $KeyStorageFlag)
            $CandidatePrivateKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($CandidateCertificate)
            if ($null -ne $CandidatePrivateKey) {
                $CandidatePrivateKey.Dispose()
                $LoadedCertificate = $CandidateCertificate
                break
            }

            $LastLoadError = "the file was opened with {0} but carries no RSA private key" -f $KeyStorageFlag
        }
        catch {
            $LastLoadError = $PSItem.Exception.Message
            "{0} - Opening '{1}' with {2} failed: {3}" -f $MyInvocation.MyCommand, $ResolvedCertificatePath, $KeyStorageFlag, $PSItem.Exception.Message | Write-Verbose
        }
        finally {
            # The first flag combination is expected to fail on some runtimes, so this loop routinely
            # produces a certificate that is thrown away. Left undisposed it would leak a key handle
            # on every call of a job that opens the same file on every run.
            if ($null -ne $CandidateCertificate -and -not [object]::ReferenceEquals($CandidateCertificate, $LoadedCertificate)) {
                $CandidateCertificate.Dispose()
            }
        }
    }

    if ($null -eq $LoadedCertificate) {
        "{0} - The certificate file '{1}' could not be opened with a usable private key: {2}. Check the password supplied to -OAuthCertificatePassword and that the file is a PKCS#12 (.pfx) export that includes the private key." -f $MyInvocation.MyCommand, $ResolvedCertificatePath, $LastLoadError | Write-Error -ErrorAction "Stop"
    }

    "{0} - Using the client certificate from '{1}'. Thumbprint: {2}, subject: {3}, expires: {4}" -f $MyInvocation.MyCommand, $ResolvedCertificatePath, $LoadedCertificate.Thumbprint, $LoadedCertificate.Subject, $LoadedCertificate.NotAfter | Write-Verbose
    return $LoadedCertificate
}
