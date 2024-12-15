function Set-RequestParameter {

    $Parameters = @{}
    $BoundParams.Keys | ForEach-Object {
        if ($_ -notin $ExcludedRestMethodParameters -and $_ -notin $ExcludedParameters) {
            $Parameters.Add($_, $BoundParams[$_])
        }
    }

    "Parameters" | Write-Verbose
    $Parameters | ConvertTo-Json | Write-Verbose
    return $Parameters
}