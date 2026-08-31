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
        "{0} - Credentials not provided! This mandatory for OAuth authentication! Supply -Credential holding the client id and secret, or a client certificate with -OAuthCertificateThumbprint, -OAuthCertificatePath or -OAuthCertificate together with -ClientId." -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
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
        "{0} - EntraIdTenantId not provided! This mandatory for Entra based OAuth authentication when no custom OAuthUri is provided!" -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
    }

    $OAuthUri = $null
    if ($null -ne $BoundParams['EntraIdTenantId']) {
        if ($null -ne $BoundParams['OAuthUri']) {
            "Using OAuth2 authentication with a provided EntraIdTenantId. Parameter OAuthUri is also provided, but will not be used!" -f $MyInvocation.MyCommand | Write-Warning
        }
        $OAuthUri = ("https://login.microsoftonline.com/{0}/oauth2/v2.0/token" -f $BoundParams['EntraIdTenantId'])
    }
    elseif ( $null -ne $BoundParams['OAuthUri']) {
        $OAuthUri = $BoundParams['OAuthUri']
    }
    else {
        "{0} - Neither EntraIdTenantId nor OAuthUri provided! Cannot proceed with OAuth authentication!" -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
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
        # RFC 7523. The assertion is bound to this exact token endpoint through its 'aud' claim, which
        # is why it is built here, after the endpoint has been resolved, rather than alongside the
        # certificate.
        $RequestBody['client_assertion_type'] = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        $RequestBody['client_assertion'] = New-OAuthClientAssertion -ClientId $ClientId -Audience $OAuthUri -Certificate $ClientCertificate
        "{0} - Authenticating the client with certificate {1} instead of a client secret." -f $MyInvocation.MyCommand, $ClientCertificate.Thumbprint | Write-Verbose
    }
    else {
        $RequestBody['client_secret'] = $($BoundParams['Credential'].GetNetworkCredential().Password)
    }

    $Arguments = @{
        Method      = "Post"
        Uri         = $OAuthUri
        Body        = $RequestBody
        ContentType = 'application/x-www-form-urlencoded'
        ErrorAction = "SilentlyContinue"
    }

    # UseBasicParsing is deprecated since PowerShell Core 6, there it is only set when using PowerShell 5 (https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest?view=powershell-7.4#-usebasicparsing)
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $Arguments.Add("UseBasicParsing", $true)
    }

    "{0} - Invoke REST method to get bearer token from OAuth2 endpoint: {1}" -f $MyInvocation.MyCommand, $OAuthUri | Write-Verbose
    $BearerToken = Invoke-RestMethod @Arguments

    # The token request runs with -ErrorAction SilentlyContinue, so a failed call or a response that is
    # not a token document arrives here as $null, or as an object with no access_token on it, instead
    # of as a thrown error. That case is passed through as an empty bearer value, which is what this
    # function has always done - it is deliberately not turned into a terminating error here, because
    # callers today rely on the request continuing. It is only made explicit so the read cannot fault.
    $AccessToken = $null
    if ($null -ne $BearerToken -and $BearerToken.PSObject.Properties['access_token']) {
        $AccessToken = $BearerToken.access_token
    }
    else {
        "{0} - The OAuth2 endpoint '{1}' returned no access_token. Continuing with an empty bearer value." -f $MyInvocation.MyCommand, $OAuthUri | Write-Verbose
    }

    $BoundParams['Headers'].Add("Authorization" , "Bearer {0}" -f $AccessToken)

    return $RequestContext
}