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
        $ExcludedParameters = @("SkipCookieCache", "CookiePath", "InPrivate", "ForceAuthentication", "AuthenticationType", "EntraIdTenantId", "RequestType", "EdgeProfile", "UseWebView2")
    }

    $Parameters = @{}
    $BoundParams.Keys | ForEach-Object {
        if ($_ -notin $ExcludedParameters) {
            $Parameters.Add($_, $BoundParams[$_])
        }
    }

    "Parameters" | Write-Verbose
    $Parameters | ConvertTo-Json | Write-Verbose
    return $Parameters
}