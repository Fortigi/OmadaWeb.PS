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
        # MaximumRetryCount and RetryIntervalSec are excluded even though PowerShell 7's native
        # cmdlets would accept them: the retry policy is implemented by Invoke-OmadaRetryableRequest
        # around the call, so passing them on as well would nest a second, differently behaving
        # retry loop inside each attempt of the first.
        $ExcludedParameters = @("SkipCookieCache", "CookiePath", "InPrivate", "ForceAuthentication", "AuthenticationType", "EntraIdTenantId", "RequestType", "EdgeProfile", "UseWebView2", "EntraApplicationIdUri", "OAuthUri", "OAuthScope", "DebugWebView2", "Paged", "SessionKey", "MaximumRetryCount", "RetryIntervalSec")
    }

    $Parameters = @{}
    $BoundParams.Keys | ForEach-Object {
        if ($_ -notin $ExcludedParameters) {
            $Parameters.Add($_, $BoundParams[$_])
        }
    }

    "Parameters" | Write-Verbose
    # Diagnostics only: the parameter set is what goes on the wire - Authorization header, credential,
    # session and body - so it only reaches the verbose stream through the redaction walker. The string
    # is built on every request, even without -Verbose, which is why the depth cap matters too.
    ConvertTo-RedactedLogString -InputObject $Parameters | Write-Verbose
    return $Parameters
}