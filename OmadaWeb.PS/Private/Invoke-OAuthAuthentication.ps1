function Invoke-OAuth2Authentication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSTypeName("OmadaWeb.PS.RequestContext")]$RequestContext
    )

    $BoundParams = $RequestContext.BoundParams
    $SessionContext = $RequestContext.SessionContext

    "{0} - Invoking OAuth authentication" -f $MyInvocation.MyCommand | Write-Verbose

    "{0} - Request bearer token" -f $MyInvocation.MyCommand | Write-Verbose

    # A confidential client proves who it is with either a shared secret or a certificate, and this
    # is where that fork is decided. Resolving the certificate first means the credential check below
    # can ask the question that actually matters - was any client credential supplied at all - rather
    # than insisting on the secret form of one.
    $ClientCertificate = Get-OAuthClientCertificate -Certificate $BoundParams['OAuthCertificate'] -CertificateThumbprint $BoundParams['OAuthCertificateThumbprint'] -CertificatePath $BoundParams['OAuthCertificatePath'] -CertificatePassword $BoundParams['OAuthCertificatePassword']

    if ($null -eq $ClientCertificate -and $null -eq $BoundParams['Credential']) {
        "{0} - Credentials not provided! This is mandatory for OAuth authentication. Supply -Credential holding the client id and secret, or a client certificate with -OAuthCertificateThumbprint, -OAuthCertificatePath or -OAuthCertificate together with -ClientId." -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
    }

    $ClientId = $null
    if (-not [string]::IsNullOrWhiteSpace($BoundParams['ClientId'])) {
        $ClientId = $BoundParams['ClientId'].Trim()
    }
    elseif ($null -eq $ClientCertificate) {
        # Only the secret flow reads the client id off the credential, and only because a secret has
        # to arrive in a PSCredential anyway, where the user name is the client id by construction.
        # The certificate flow deliberately does not fall back to it: a credential held for some
        # other purpose would otherwise sign an assertion for the wrong application, and the sign-in
        # would fail with an error from the identity provider that names neither cause nor cure.
        $ClientId = $BoundParams['Credential'].UserName.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($ClientId)) {
        "{0} - No client id was provided! Supply the application (client) id with -ClientId. It is required whenever a client certificate is used, and is never taken from -Credential in that case." -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
    }

    # Both forms at once is not an error - the credential may be there because the same script also
    # signs in interactively - but only one of them authenticates the client, and which one is not
    # something to leave a reader of the logs guessing at.
    if ($null -ne $ClientCertificate -and $null -ne $BoundParams['Credential']) {
        "Both a client certificate and a Credential were supplied for OAuth authentication. The certificate is used and the client secret in the credential is ignored." | Write-Warning
    }

    if ($null -eq $BoundParams['EntraIdTenantId'] -and -not $BoundParams.Keys.Contains("OAuthUri")) {
        "{0} - EntraIdTenantId not provided! This is mandatory for Entra based OAuth authentication when no custom OAuthUri is provided." -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
    }

    $OAuthUri = $null
    if ($null -ne $BoundParams['EntraIdTenantId']) {
        if ($null -ne $BoundParams['OAuthUri']) {
            "Using OAuth2 authentication with a provided EntraIdTenantId. Parameter OAuthUri is also provided, but will not be used!" -f $MyInvocation.MyCommand | Write-Warning
        }

        $EntraIdTenantId = $BoundParams['EntraIdTenantId']

        # This value is formatted straight into the token endpoint URL below, so it is validated as one
        # of the two shapes Entra ID actually accepts for a tenant - a GUID, or a DNS-style name such
        # as 'contoso.onmicrosoft.com' (a single label like 'common' is also a real Entra ID tenant
        # value and is a syntactically valid DNS name, so it is accepted too). Anything else - a
        # path segment, a query string, a fragment, whitespace, an empty label - is refused here rather
        # than escaped, because escaping it would just send a well-formed request to a host the caller
        # never actually named.
        $ParsedTenantGuid = [guid]::Empty
        $TenantIsGuid = [guid]::TryParse($EntraIdTenantId, [ref]$ParsedTenantGuid)
        $TenantIsDnsName = $EntraIdTenantId -match '^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'
        if (-not $TenantIsGuid -and -not $TenantIsDnsName) {
            "{0} - EntraIdTenantId '{1}' is neither a GUID nor a DNS-style tenant name (e.g. 'contoso.onmicrosoft.com'). Refusing to build a token endpoint from it." -f $MyInvocation.MyCommand, $EntraIdTenantId | Write-Error -ErrorAction "Stop"
        }

        $OAuthUri = ("https://login.microsoftonline.com/{0}/oauth2/v2.0/token" -f $EntraIdTenantId)
    }
    elseif ( $null -ne $BoundParams['OAuthUri']) {
        $OAuthUri = $BoundParams['OAuthUri']
    }
    else {
        "{0} - Neither EntraIdTenantId nor OAuthUri provided! Cannot proceed with OAuth authentication!" -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
    }

    # The token request body carries the client secret (or, for the certificate flow, a signed
    # assertion) form-encoded over the wire, so a non-https endpoint - most often a plain typo of
    # 'http://' for 'https://' - would send it in clear text. Refused here, before anything is built
    # from it, rather than left to whatever a plain-HTTP POST happens to do.
    $OAuthUriScheme = $null
    try {
        $OAuthUriScheme = ([System.Uri]$OAuthUri).Scheme
    }
    catch {
        $OAuthUriScheme = $null
    }
    if ($OAuthUriScheme -ne [System.Uri]::UriSchemeHttps) {
        "{0} - -OAuthUri '{1}' must use https. A non-https token endpoint would send the client secret in clear text." -f $MyInvocation.MyCommand, $OAuthUri | Write-Error -ErrorAction "Stop"
    }

    $EntraApplicationIdUri = $SessionContext.BaseUrl
    if ("EntraApplicationIdUri" -in $BoundParams.Keys) {
        $EntraApplicationIdUri = $BoundParams['EntraApplicationIdUri']
    }

    $OAuthScope = ("{0}/.default" -f $EntraApplicationIdUri )
    if ($BoundParams.Keys -contains "OAuthScope" -and $null -ne $BoundParams['OAuthScope']) {
        "{0} - OAuthScope parameter used! OAuthScope: {1}" -f $MyInvocation.MyCommand, $BoundParams['OAuthScope'] | Write-Verbose
        $OAuthScope = $BoundParams['OAuthScope']
    }
    else {
        # Reports $OAuthScope, the default derived above. This branch is the one where no OAuthScope
        # was supplied, so it used to announce a "custom" scope and then print the empty value of the
        # parameter that was not passed - the opposite of what happened, on the path where a reader
        # most needs to know which scope was actually requested.
        "{0} - No OAuthScope parameter used, defaulting to: {1}" -f $MyInvocation.MyCommand, $OAuthScope | Write-Verbose
    }

    $RequestBody = @{
        scope      = $OAuthScope
        client_id  = $ClientId
        grant_type = 'client_credentials'
    }

    if ($null -ne $ClientCertificate) {
        try {
            # RFC 7523. The assertion is bound to this exact token endpoint through its 'aud' claim,
            # which is why it is built here, after the endpoint has been resolved, rather than
            # alongside the certificate.
            $RequestBody['client_assertion_type'] = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
            $RequestBody['client_assertion'] = New-OAuthClientAssertion -ClientId $ClientId -Audience $OAuthUri -Certificate $ClientCertificate
            "{0} - Authenticating the client with certificate {1} instead of a client secret." -f $MyInvocation.MyCommand, $ClientCertificate.Thumbprint | Write-Verbose
        }
        finally {
            # A certificate the module opened itself - from the store or from a file - is opened
            # again on every request, so an unattended job making thousands of them would hold
            # thousands of key handles until the collector got round to them. The assertion is a
            # string by this point and nothing downstream needs the certificate.
            #
            # One passed in with -OAuthCertificate belongs to the caller, who may well reuse it for
            # the next call, and is left alone. The validation failures above end the request rather
            # than repeating, so they are not the path that accumulates and are deliberately not
            # wrapped.
            if ($null -eq $BoundParams['OAuthCertificate']) {
                $ClientCertificate.Dispose()
            }
        }
    }
    else {
        $RequestBody['client_secret'] = $($BoundParams['Credential'].GetNetworkCredential().Password)
    }

    "{0} - Invoke REST method to get bearer token from OAuth2 endpoint: {1}" -f $MyInvocation.MyCommand, $OAuthUri | Write-Verbose

    # The token call itself lives in Invoke-OAuthTokenRequest rather than being made directly here, so
    # a test can replace exactly that call without shadowing the Invoke-RestMethod cmdlet - something
    # Invoke-OmadaRestMethod's own dynamicparam block introspects through Set-DynamicParameter, and a
    # mock of the cmdlet itself breaks that introspection wherever it is active.
    #
    # A failed token request used to run with -ErrorAction SilentlyContinue and fall through to an
    # empty bearer value, so the caller's actual request went to Omada with 'Authorization: Bearer '
    # and came back as an unexplained 401 instead of whatever the identity provider actually said.
    # Invoke-OAuthTokenRequest stops on error, and the failure is re-thrown here carrying the identity
    # provider's own error - Omada is never contacted with an empty token.
    try {
        $BearerToken = Invoke-OAuthTokenRequest -Uri $OAuthUri -Body $RequestBody
    }
    catch {
        throw (New-OAuthTokenRequestError -OAuthUri $OAuthUri -ErrorRecord $PSItem)
    }

    $AccessToken = $null
    if ($null -ne $BearerToken -and $BearerToken.PSObject.Properties['access_token']) {
        $AccessToken = $BearerToken.access_token
    }
    else {
        # A response can arrive as HTTP 200 without an access_token - an identity provider answering
        # with a document this function does not recognise - which is just as unusable as a thrown
        # error, so it ends the call the same way rather than continuing with an empty bearer value.
        throw (New-OAuthTokenRequestError -OAuthUri $OAuthUri -Message 'no access_token was returned')
    }

    # Indexer assignment, not .Add: a caller-supplied Authorization header may already be present,
    # and the OAuth authentication the caller asked for overrides it rather than throwing on a
    # duplicate key.
    $BoundParams['Headers']['Authorization'] = "Bearer {0}" -f $AccessToken

    return $RequestContext
}