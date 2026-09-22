[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ModulePath', Justification = 'Used by Import-Module inside the Describe BeforeAll, which the analyzer does not follow into.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Scenario', Justification = 'Read in BeforeDiscovery to decide which scenario runs, and inside the Describe BeforeAll to pick the credential form. The analyzer follows into neither.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The client secret and the certificate password arrive from GitHub environment secrets as environment variables, which are plain strings by the time this process can see them. Building the PSCredential and the SecureString the module takes is the only thing done with them.')]
param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1'),

    # Which credential form to authenticate the client with. They are separate runs rather than
    # separate assertions in one, because each has to be the only credential in play: supply two and
    # Invoke-OAuth2Authentication picks the certificate and says so, which is the right behaviour and
    # the wrong test.
    [ValidateSet('OAuthClientSecret', 'OAuthCertificateStore', 'OAuthCertificateFile', 'OAuthCertificateObject')]
    [string]$Scenario = 'OAuthClientSecret'
)

# The scheduled service-principal canary.
#
# WHAT THIS WATCHES
#
# Unattended authentication - -AuthenticationType OAuth, the client-credentials grant that scheduled
# tasks, containers and CI pipelines use. It is the one part of the module with no person in front of
# it, so a break here is discovered by a job that stopped running rather than by somebody watching it
# fail.
#
# The part that cannot be unit tested is the client assertion. New-OAuthClientAssertion signs an
# RS256 JWT carrying x5t, aud, iss, sub, jti and exp, and a mock will accept any of that; only
# Microsoft can say whether it is actually valid. The same is true of the tenant shape around it - a
# certificate credential Entra rejects, a scope that resolves to nothing, a client holding no app
# role on the resource. Tests/Unit/Invoke-OAuth2Authentication.Tests.ps1 and
# Tests/Unit/Get-OAuthClientCertificate.Tests.ps1 cover the code; this covers the agreement with
# Entra ID.
#
# WHAT IT ASSERTS AGAINST, AND WHY IT IS NOT "THE CALL DID NOT THROW"
#
# Invoke-OAuth2Authentication requests its token with -ErrorAction SilentlyContinue and, when no
# access_token comes back, continues with an EMPTY bearer value - a verbose line is the only trace.
# A test that asserted the request completed would therefore pass against a tenant issuing no tokens
# at all. So every assertion below is made against the token that arrived at the resource, which
# Start-CanaryRelyingParty records for this purpose.
#
# HOW IT IS SHAPED LIKE A CUSTOMER'S TENANT
#
# Omada's own OAuth documentation describes two app registrations: the OpenID Connect application
# that Omada is configured with, which carries the Application ID URI and exposes the application
# role, and a separate OAuth client application per connecting client, which carries the credentials.
# The main OIDC registration explicitly cannot be used with client secret grants. The canary tenant
# holds the same two, and the claims checked below - aud is the OIDC application, azp is the OAuth
# client - are the ones Omada's documentation tells an administrator to verify.
# See https://documentation.omadaidentity.com/docs/getting-started/authentication-sso/oauth/ and
# Build/New-EntraCanaryConfiguration.ps1.
#
# NO BROWSER IS INVOLVED. The OAuth branch in Invoke-OmadaRequest never reaches WebView2, so there is
# no window, no STA requirement and no selector table anywhere in this file. A red run here never
# means Microsoft changed a sign-in page.
#
# See docs/entra-canary.md for the tenant setup, the secrets, and what to do when this goes red.

BeforeDiscovery {
    # Read at discovery so the whole file can be skipped as configuration rather than reported as a
    # failure. A developer running the suite locally, and PR Validation, both land here.
    $Script:CanaryTenantId = $Env:OMADAWEBPS_CANARY_TENANT_ID
    $Script:ClientId = $Env:OMADAWEBPS_CANARY_SP_CLIENT_ID
    $Script:ClientSecret = $Env:OMADAWEBPS_CANARY_SP_CLIENT_SECRET
    $Script:CertificatePfx = $Env:OMADAWEBPS_CANARY_SP_CERT_PFX_BASE64
    $Script:CertificatePassword = $Env:OMADAWEBPS_CANARY_SP_CERT_PASSWORD
    $Script:ResourceUri = $Env:OMADAWEBPS_CANARY_SP_RESOURCE_URI
    $Script:ResourceClientId = $Env:OMADAWEBPS_CANARY_SP_RESOURCE_CLIENT_ID
    $Script:AppRole = $Env:OMADAWEBPS_CANARY_SP_APP_ROLE

    # Everything except the credential itself is needed by every scenario.
    $Script:CommonConfigured = -not (
        [string]::IsNullOrWhiteSpace($Script:CanaryTenantId) -or
        [string]::IsNullOrWhiteSpace($Script:ClientId) -or
        [string]::IsNullOrWhiteSpace($Script:ResourceUri) -or
        [string]::IsNullOrWhiteSpace($Script:ResourceClientId) -or
        [string]::IsNullOrWhiteSpace($Script:AppRole)
    )

    # The credential this scenario needs, and only that one: a tenant provisioned with a certificate
    # but no secret should run the three certificate scenarios rather than skip all four.
    $Script:CredentialConfigured = if ($Scenario -eq 'OAuthClientSecret') {
        -not [string]::IsNullOrWhiteSpace($Script:ClientSecret)
    }
    else {
        -not ([string]::IsNullOrWhiteSpace($Script:CertificatePfx) -or [string]::IsNullOrWhiteSpace($Script:CertificatePassword))
    }

    $Script:RunServicePrincipalScenario = $Script:CommonConfigured -and $Script:CredentialConfigured

    # Read at discovery for the same reason: whether the certificate assertions apply is a property
    # of the scenario, not something to decide inside one.
    $Script:CertificateScenario = $Scenario -ne 'OAuthClientSecret'
}

Describe 'Entra ID service-principal canary' -Tag 'E2E' -Skip:(-not $Script:RunServicePrincipalScenario) {

    BeforeAll {
        . (Join-Path $PSScriptRoot 'Start-CanaryRelyingParty.ps1')

        Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
        Import-Module $ModulePath -Force -ErrorAction Stop

        function ConvertFrom-CanaryJwtPayload {
            <#
            .SYNOPSIS
                Reads the claims out of an access token without validating its signature.
            .DESCRIPTION
                The assertion being made is that Microsoft issued this token for the resource, not
                that this process can verify it - verification is the resource server's job, and the
                canary has no resource server. So the payload is decoded and read, and nothing here
                pretends to check the signature.
            #>
            [CmdletBinding()]
            [OutputType([System.Management.Automation.PSCustomObject])]
            param(
                [Parameter(Mandatory)]
                [AllowEmptyString()]
                [string]$Token
            )

            $Part = @($Token -split '\.')
            if ($Part.Count -lt 2) {
                return $null
            }

            # base64url: the padding is stripped and two characters are swapped.
            $Payload = $Part[1].Replace('-', '+').Replace('_', '/')
            switch ($Payload.Length % 4) {
                2 { $Payload = $Payload + '==' }
                3 { $Payload = $Payload + '=' }
            }

            try {
                return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Payload)) | ConvertFrom-Json
            }
            catch {
                return $null
            }
        }

        $Port = if ([string]::IsNullOrWhiteSpace($Env:OMADAWEBPS_CANARY_PORT)) { 8400 } else { [int]$Env:OMADAWEBPS_CANARY_PORT }

        # The same loopback stand-in the sign-in canary uses. Only its /api/* route is exercised here:
        # the module goes straight to the token endpoint and then to the resource, so the authorize
        # URI this builds is never fetched by anything.
        $Script:RelyingParty = Start-CanaryRelyingParty -TenantId $Env:OMADAWEBPS_CANARY_TENANT_ID -ClientId $Env:OMADAWEBPS_CANARY_SP_CLIENT_ID -LoginHint '' -Prompt '' -Port $Port

        $Script:StoredCertificate = $null
        $Script:CertificateFilePath = $null
        $Script:ClientCertificate = $null
        $Script:ExpectedThumbprint = $null

        # Derived here rather than read from the variable BeforeDiscovery set: discovery and run are
        # separate phases, and only the -Skip: expressions are evaluated in the first one.
        $CertificateScenario = $Scenario -ne 'OAuthClientSecret'

        if ($CertificateScenario) {
            $CertificateByte = [Convert]::FromBase64String($Env:OMADAWEBPS_CANARY_SP_CERT_PFX_BASE64)
            $SecureCertificatePassword = ConvertTo-SecureString -String $Env:OMADAWEBPS_CANARY_SP_CERT_PASSWORD -AsPlainText -Force

            switch ($Scenario) {
                'OAuthCertificateStore' {
                    # PersistKeySet, because a key that lives only for the length of this constructor
                    # call is not there any more when Get-OAuthClientCertificate reopens the store.
                    $Script:StoredCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                        $CertificateByte,
                        $SecureCertificatePassword,
                        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet)

                    $Store = [System.Security.Cryptography.X509Certificates.X509Store]::new(
                        [System.Security.Cryptography.X509Certificates.StoreName]::My,
                        [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser)
                    $Store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
                    $Store.Add($Script:StoredCertificate)
                    $Store.Close()

                    $Script:ExpectedThumbprint = $Script:StoredCertificate.Thumbprint
                }

                'OAuthCertificateFile' {
                    # What a container or a job running under an account with no certificate store
                    # does. Written to the process temp directory and removed in AfterAll.
                    $Script:CertificateFilePath = Join-Path ([System.IO.Path]::GetTempPath()) ("omadaweb-canary-{0}.pfx" -f [guid]::NewGuid().ToString("N"))
                    [System.IO.File]::WriteAllBytes($Script:CertificateFilePath, $CertificateByte)

                    $Probe = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                        $CertificateByte,
                        $SecureCertificatePassword,
                        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
                    $Script:ExpectedThumbprint = $Probe.Thumbprint
                    $Probe.Dispose()
                }

                'OAuthCertificateObject' {
                    # A certificate the caller already holds. Invoke-OAuth2Authentication deliberately
                    # does not dispose this one, because it belongs to whoever passed it in.
                    $Script:ClientCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                        $CertificateByte,
                        $SecureCertificatePassword,
                        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)

                    $Script:ExpectedThumbprint = $Script:ClientCertificate.Thumbprint
                }
            }

            # A plain variable, because splatting does not accept a scope qualifier: @Script:Name
            # binds the hashtable as one positional argument instead of expanding it.
            $AuthenticationArgument = switch ($Scenario) {
                'OAuthCertificateStore' { @{ ClientId = $Env:OMADAWEBPS_CANARY_SP_CLIENT_ID; OAuthCertificateThumbprint = $Script:ExpectedThumbprint } }
                'OAuthCertificateFile' { @{ ClientId = $Env:OMADAWEBPS_CANARY_SP_CLIENT_ID; OAuthCertificatePath = $Script:CertificateFilePath; OAuthCertificatePassword = $SecureCertificatePassword } }
                'OAuthCertificateObject' { @{ ClientId = $Env:OMADAWEBPS_CANARY_SP_CLIENT_ID; OAuthCertificate = $Script:ClientCertificate } }
            }
        }
        else {
            # The secret form. The client id is the user name by construction, which is the one place
            # the module reads it off the credential.
            $SecureClientSecret = ConvertTo-SecureString -String $Env:OMADAWEBPS_CANARY_SP_CLIENT_SECRET -AsPlainText -Force
            $AuthenticationArgument = @{
                Credential = [System.Management.Automation.PSCredential]::new($Env:OMADAWEBPS_CANARY_SP_CLIENT_ID, $SecureClientSecret)
            }
        }

        $Script:CanaryError = $null
        $Script:CanaryResponse = $null
        $Script:CanaryVerbose = @()

        # The stand-in serves plain HTTP on the loopback interface. -Credential is not in
        # Set-RequestParameter's exclusion list, so on the secret scenario it is forwarded to
        # Invoke-RestMethod, and PowerShell 7 refuses to carry a credential over an unencrypted
        # connection without being told to. Guarded by version because the parameter does not exist on
        # Windows PowerShell 5.1, which is the same shape Tests/Integration uses for the same reason.
        $UnencryptedAuthParameter = if ($PSVersionTable.PSVersion.Major -ge 6) { @{ AllowUnencryptedAuthentication = $true } } else { @{} }

        try {
            # Verbose is captured rather than merely enabled: it is the only place the module states
            # which credential form actually authenticated the client, and the certificate scenarios
            # assert on that. The module's own streams go through Protect-LogMessage, and the workflow
            # masks every canary secret before this runs.
            $Output = Invoke-OmadaRestMethod -Uri $Script:RelyingParty.ResourceUrl `
                -AuthenticationType OAuth `
                -EntraIdTenantId $Env:OMADAWEBPS_CANARY_TENANT_ID `
                -EntraApplicationIdUri $Env:OMADAWEBPS_CANARY_SP_RESOURCE_URI `
                -SkipCookieCache `
                @UnencryptedAuthParameter `
                @AuthenticationArgument `
                -Verbose `
                -ErrorAction Stop 4>&1

            foreach ($Record in @($Output)) {
                if ($Record -is [System.Management.Automation.VerboseRecord]) {
                    $Script:CanaryVerbose += $Record.Message
                }
                else {
                    $Script:CanaryResponse = $Record
                }
            }
        }
        catch {
            $Script:CanaryError = $_
        }

        $Script:Bearer = $Script:RelyingParty.ResourceBearer
        $Script:AccessToken = if ([string]::IsNullOrWhiteSpace($Script:Bearer)) { "" } else { ($Script:Bearer -replace '^\s*Bearer\s+', '').Trim() }
        $Script:Claim = ConvertFrom-CanaryJwtPayload -Token $Script:AccessToken

        # An AADSTS code is the difference between "the tenant is misconfigured or a credential
        # expired" and "the module builds an assertion Microsoft will not take". It is pulled out of
        # the error rather than out of the token, because a request that got no token is exactly the
        # case that has one.
        $ErrorText = if ($null -eq $Script:CanaryError) { "" } else { $Script:CanaryError.Exception.Message }
        $Script:EntraErrorCode = @([regex]::Matches($ErrorText, 'AADSTS\d+') | ForEach-Object { $_.Value } | Select-Object -Unique)

        if ($Script:EntraErrorCode.Count -gt 0 -or -not [string]::IsNullOrWhiteSpace($ErrorText)) {
            # Only the codes and the error text reach the report. The access token never does: a
            # failing canary's diagnostic is copied into a public GitHub issue.
            $Diagnostic = (@(
                    "Scenario: {0}" -f $Scenario
                    $(if ($Script:EntraErrorCode.Count -gt 0) { "Entra ID returned: {0}" -f ($Script:EntraErrorCode -join ", ") })
                    $ErrorText
                ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [System.Environment]::NewLine

            "::group::Entra service-principal canary diagnostic" | Write-Host
            $Diagnostic | Write-Host
            "::endgroup::" | Write-Host

            if (-not [string]::IsNullOrWhiteSpace($Env:OMADAWEBPS_CANARY_DIAGNOSTIC_PATH)) {
                $Diagnostic | Set-Content -LiteralPath $Env:OMADAWEBPS_CANARY_DIAGNOSTIC_PATH -Encoding UTF8
            }
        }
    }

    AfterAll {
        if ($null -ne $Script:StoredCertificate) {
            $Store = [System.Security.Cryptography.X509Certificates.X509Store]::new(
                [System.Security.Cryptography.X509Certificates.StoreName]::My,
                [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser)
            $Store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
            $Store.Remove($Script:StoredCertificate)
            $Store.Close()
            $Script:StoredCertificate.Dispose()
        }

        if ($null -ne $Script:ClientCertificate) {
            $Script:ClientCertificate.Dispose()
        }

        if (-not [string]::IsNullOrWhiteSpace($Script:CertificateFilePath)) {
            Remove-Item -LiteralPath $Script:CertificateFilePath -Force -ErrorAction SilentlyContinue
        }

        Stop-CanaryRelyingParty -RelyingParty $Script:RelyingParty
        Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    }

    It 'Presented a bearer token at the resource' {
        # The assertion the whole file rests on. Without it every other check here could pass while
        # the module sent 'Authorization: Bearer ' and the stand-in - which authorizes nothing -
        # answered 200 anyway.
        $Because = if ($Script:EntraErrorCode.Count -gt 0) {
            "Entra ID refused to issue a token ({0}). That is the tenant or an expired credential, not the module - see docs/entra-canary.md" -f ($Script:EntraErrorCode -join ", ")
        }
        else {
            "no access token reached the resource. Invoke-OAuth2Authentication continues with an empty bearer when the token request fails, so read the diagnostic above rather than the status code"
        }

        $Script:RelyingParty.ResourceHitCount | Should -BeGreaterThan 0 -Because "the module never reached the resource at all"
        $Script:AccessToken | Should -Not -BeNullOrEmpty -Because $Because
    }

    It 'Was issued a token the way Omada expects one' {
        # The two claims Omada's own documentation tells an administrator to verify: aud is the
        # OpenID Connect application Omada is configured with, azp is the OAuth client that asked.
        # Checked together, they are what proves the app-role grant between the two registrations is
        # still in place.
        $Script:Claim | Should -Not -BeNullOrEmpty -Because "the bearer value was not a readable JWT"
        $Script:Claim.aud | Should -Be $Env:OMADAWEBPS_CANARY_SP_RESOURCE_CLIENT_ID -Because "the token was issued for a different resource than the one Omada would validate against"
        $Script:Claim.azp | Should -Be $Env:OMADAWEBPS_CANARY_SP_CLIENT_ID -Because "the token names a different client than the one the module authenticated as"
        $Script:Claim.iss | Should -BeLike ("*{0}*" -f $Env:OMADAWEBPS_CANARY_TENANT_ID) -Because "the token was issued by a different tenant"
        $Script:Claim.ver | Should -Be "2.0" -Because "requestedAccessTokenVersion on the resource registration is not 2, so the claims differ from the ones Omada documents"
    }

    It 'Carried the application role granted to the client' {
        # Entra will hand a client credentials request a role-less token when the resource does not
        # require assignment, and such a token authenticates nothing at Omada. Asserting the role is
        # present is what tells a real grant apart from that.
        @($Script:Claim.roles) | Should -Contain $Env:OMADAWEBPS_CANARY_SP_APP_ROLE -Because "the app role grant between the two app registrations is missing or was not consented"
    }

    It 'Authenticated the client with the certificate rather than a secret' -Skip:(-not $Script:CertificateScenario) {
        # The certificate scenarios pass no -Credential at all, so the only way the request could have
        # succeeded is a client assertion Microsoft accepted. This names the certificate that signed
        # it, which is what tells the three certificate forms apart in a report.
        $Trace = @($Script:CanaryVerbose | Where-Object { $_ -match 'Authenticating the client with certificate' })
        $Trace -join [System.Environment]::NewLine | Should -BeLike ("*{0}*" -f $Script:ExpectedThumbprint) -Because "the module did not report signing a client assertion with the expected certificate"
    }

    It 'Was not refused by Entra ID' {
        # Separated from the token assertion so that a tenant problem - an expired secret or
        # certificate, a revoked consent, a disabled service principal - is reported as itself rather
        # than as "no token arrived".
        $Script:EntraErrorCode -join ", " | Should -BeNullOrEmpty -Because "Entra ID returned this error code instead of a token; see docs/entra-canary.md"
    }

    It 'Returned the protected resource' {
        # Proves the whole Invoke-OmadaRestMethod path completed, not merely the token call.
        $Script:CanaryResponse | Should -Not -BeNullOrEmpty
        $Script:CanaryResponse.canary | Should -Be "ok"
    }

    It 'Kept the loopback stand-in healthy throughout' {
        # Reads the runspace's error stream as well as the loop's own record, so a listener that died
        # before it ever served a request cannot be reported as healthy while the failure is blamed on
        # Entra ID.
        (Get-CanaryRelyingPartyError -RelyingParty $Script:RelyingParty) -join [System.Environment]::NewLine | Should -BeNullOrEmpty
    }
}
