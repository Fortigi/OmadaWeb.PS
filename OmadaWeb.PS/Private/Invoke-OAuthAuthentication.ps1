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
    if ($null -eq $BoundParams['Credential']) {
        "{0} - Credentials not provided! This mandatory for OAuth authentication!" -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
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
        scope         = $OAuthScope
        client_id     = $($BoundParams['Credential'].UserName.Trim())
        grant_type    = 'client_credentials'
        client_secret = $($BoundParams['Credential'].GetNetworkCredential().Password)
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