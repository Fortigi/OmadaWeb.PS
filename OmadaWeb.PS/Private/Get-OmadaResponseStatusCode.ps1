function Get-OmadaResponseStatusCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Exception
    )

    # Not every exception raised by the web stack is HTTP-based - the re-authentication signal
    # Invoke-OmadaRequest throws at itself has no .Response at all, and a socket-level failure has
    # a .Response of $null. Both members are therefore resolved through PSObject.Properties lookups
    # so a missing .Response/.StatusCode evaluates to $null instead of faulting the caller under
    # Set-StrictMode, where a bare $Exception.Response.StatusCode read throws.
    if ($null -eq $Exception) {
        return $null
    }

    $ResponseProperty = $Exception.PSObject.Properties['Response']
    if (-not $ResponseProperty -or $null -eq $ResponseProperty.Value) {
        return $null
    }

    $StatusCodeProperty = $ResponseProperty.Value.PSObject.Properties['StatusCode']
    if (-not $StatusCodeProperty) {
        return $null
    }

    return $StatusCodeProperty.Value
}
