function Invoke-EntraIdOAuth {
    "{0} - Request bearer token" -f $MyInvocation.MyCommand, $_ | Write-Verbose
    if ($null -eq $BoundParams.Credential) {
        "{0} - Credentials not provided! This mandatory for OAuth authentication!" -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
    }
    if ($null -eq $BoundParams.EntraIdTenantId) {
        "{0} - EntraIdTenantId not provided! This mandatory for OAuth authentication!" -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
    }

    $RequestBody = @{
        scope         = ("{0}/.default" -f $Script:OmadaWebBaseUrl)
        client_id     = $($BoundParams.Credential.UserName)
        grant_type    = 'client_credentials'
        client_secret = $($BoundParams.Credential.GetNetworkCredential().Password)
    }

    $BearerToken = Invoke-RestMethod -Uri ("https://login.microsoftonline.com/{0}/oauth2/v2.0/token" -f $BoundParams.EntraIdTenantId) -UseBasicParsing -Method Post -Body $RequestBody -ContentType 'application/x-www-form-urlencoded'
    $BearerToken = $BearerToken
    $BoundParams.Headers.Add("Authorization" , "Bearer {0}" -f $BearerToken.access_token)
}