function Set-RequestParameter {
    [CmdletBinding()]
    param(
        [switch]$InvokeOmadaRequest
    )

    "{0} - Setting request parameters" -f $MyInvocation.MyCommand | Write-Verbose

    if ($InvokeOmadaRequest) {
        $InvokeOmadaRequestFunction = Get-Command -Name Invoke-OmadaRequest
        $ExcludedParameters = @()
        $BoundParams.Keys | ForEach-Object {
            if ($_ -notin $InvokeOmadaRequestFunction.Parameters.Keys) {
                $ExcludedParameters += $_
            }
        }
    }
    else {
        $ExcludedParameters = @("SkipCookieCache", "CookiePath", "InPrivate", "ForceAuthentication", "AuthenticationType", "EntraIdTenantId", "RequestType", "EdgeProfile", "UseWebView2", "EntraApplicationIdUri", "OAuthUri", "OAuthScope", "DebugWebView2", "Paged", "SessionKey")
    }

    $Parameters = @{}
    $BoundParams.Keys | ForEach-Object {
        if ($_ -notin $ExcludedParameters) {
            $Parameters.Add($_, $BoundParams[$_])
        }
    }

    "Parameters" | Write-Verbose
    # Diagnostics only: the parameter set holds rich objects (credential, session, body), so the
    # depth stays deliberately low - this string is built on every request, even without -Verbose.
    $Parameters | ConvertTo-Json -Depth 5 | Write-Verbose
    return $Parameters
}