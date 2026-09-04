function New-OAuthClientAssertion {
    <#
    .SYNOPSIS
        Builds the signed JSON Web Token that proves possession of the client certificate.

    .DESCRIPTION
        In a certificate-based client-credentials request the client_secret field is replaced by two
        others: client_assertion_type, which is the fixed URN from RFC 7523, and client_assertion,
        which is a JWT the client signs with the private key of the certificate registered on the
        application. The identity provider verifies that signature against the public key it holds,
        so the private key itself never leaves the machine and nothing reusable travels on the wire.

        The token is three base64url segments joined by dots. The header names RS256 and carries
        'x5t', the base64url of the certificate's SHA-1 hash, which is how the provider picks the
        right public key when an application has more than one certificate registered. The payload
        carries the token endpoint as 'aud' - binding the assertion to the one endpoint it may be
        presented to - the client id as both 'iss' and 'sub', a 'jti' that makes it single use, and
        a validity window.

        That window is deliberately short and starts a minute in the past. Entra ID rejects an
        assertion whose 'nbf' lies in the future, and the clock of a scheduled job is not always the
        clock of the identity provider, so a minute of backdating turns a rejected sign-in into a
        successful one without widening the window that matters, which is 'exp'.

    .PARAMETER ClientId
        The application (client) id the assertion is issued for and about.

    .PARAMETER Audience
        The token endpoint the assertion will be presented to, exactly as it will be requested.

    .PARAMETER Certificate
        The certificate whose private key signs the assertion.

    .PARAMETER LifetimeSeconds
        How long the assertion stays valid. Defaults to 600, which is well inside the 10 minutes
        Entra ID allows and long enough for a slow round trip.

    .OUTPUTS
        System.String. The signed JWT, ready to be sent as the client_assertion form field.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [string]$Audience,

        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [ValidateRange(60, 600)]
        [int]$LifetimeSeconds = 600
    )

    if (-not $Certificate.HasPrivateKey) {
        "{0} - The certificate with thumbprint {1} has no private key, so it cannot sign a client assertion." -f $MyInvocation.MyCommand, $Certificate.Thumbprint | Write-Error -ErrorAction "Stop"
    }

    $Header = [ordered]@{
        alg = "RS256"
        typ = "JWT"
        x5t = ConvertTo-Base64UrlString -Byte $Certificate.GetCertHash()
    }

    $IssuedAt = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $Payload = [ordered]@{
        aud = $Audience
        exp = $IssuedAt + $LifetimeSeconds
        iat = $IssuedAt
        iss = $ClientId
        jti = [guid]::NewGuid().ToString()
        nbf = $IssuedAt - 60
        sub = $ClientId
    }

    $EncodedHeader = ConvertTo-Base64UrlString -Byte ([System.Text.Encoding]::UTF8.GetBytes(($Header | ConvertTo-Json -Compress)))
    $EncodedPayload = ConvertTo-Base64UrlString -Byte ([System.Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Compress)))
    $SigningInput = "{0}.{1}" -f $EncodedHeader, $EncodedPayload

    $PrivateKey = $null
    $Signature = $null
    try {
        # RSACertificateExtensions is used rather than the PrivateKey property. PrivateKey returns the
        # legacy CSP object, which on an older provider cannot sign with SHA-256 at all, and it is
        # obsolete on .NET Core. This static call returns an RSA that works the same way on Windows
        # PowerShell and on PowerShell 7, for both CSP and CNG keys.
        $PrivateKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
        if ($null -eq $PrivateKey) {
            "{0} - The private key of certificate {1} is not an RSA key, or is not readable by this account. A client assertion is signed with RS256, so an RSA key is required." -f $MyInvocation.MyCommand, $Certificate.Thumbprint | Write-Error -ErrorAction "Stop"
        }

        $Signature = $PrivateKey.SignData([System.Text.Encoding]::UTF8.GetBytes($SigningInput), [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    }
    finally {
        if ($null -ne $PrivateKey) {
            $PrivateKey.Dispose()
        }
    }

    "{0} - Signed a client assertion for client id {1}, audience {2}, valid for {3} seconds." -f $MyInvocation.MyCommand, $ClientId, $Audience, $LifetimeSeconds | Write-Verbose

    return "{0}.{1}" -f $SigningInput, (ConvertTo-Base64UrlString -Byte $Signature)
}
