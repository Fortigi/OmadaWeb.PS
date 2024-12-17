function Set-RequestParameter {

    $ExcludedParameters = @("OmadaWebAuthCookieExportLocation", "InPrivate", "ForceAuthentication", "AuthenticationType", "EntraIdTenantId", "RequestType", "EdgeProfile")

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