function Set-RequestParameter {
    [CmdletBinding()]
    PARAM(
        [switch]$InvokeOmadaRequest
    )

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
        $ExcludedParameters = @("SkipCookieCache","CookiePath", "InPrivate", "ForceAuthentication", "AuthenticationType", "EntraIdTenantId", "RequestType", "EdgeProfile")
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