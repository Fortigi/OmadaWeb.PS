function Test-EnvironmentSuspended {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Url,
        [int]$TimeoutSec = 5
    )

    try {
        $Uri = [System.Uri]::new($Url)
        $BaseUrl = $Uri.GetLeftPart([System.UriPartial]::Authority) + '/'

        # Reuse a single module-scoped HttpClient instead of newing one up per call. Creating a
        # client (and its handler) per request allocates a fresh connection pool each time, which
        # under high-volume usage contributes to socket/port exhaustion in .NET. Because the client
        # is shared, the per-call timeout is enforced with a CancellationToken rather than
        # HttpClient.Timeout (which cannot vary per request once the client is reused).
        if ($null -eq $Script:EnvironmentSuspendedHttpClient) {
            Add-Type -AssemblyName System.Net.Http
            $Script:EnvironmentSuspendedHttpClient = [System.Net.Http.HttpClient]::new()
            # Represent "no client-level timeout" with TimeSpan.FromMilliseconds(Timeout.Infinite)
            # rather than Timeout.InfiniteTimeSpan: the latter static is missing on some older .NET
            # Framework builds (Windows PowerShell 5.1) and would fault while initializing the client.
            # Both are the same infinite value; the real per-call limit is applied via the
            # CancellationToken below.
            $Script:EnvironmentSuspendedHttpClient.Timeout = [System.TimeSpan]::FromMilliseconds([System.Threading.Timeout]::Infinite)
        }
        $Client = $Script:EnvironmentSuspendedHttpClient

        $CancellationSource = [System.Threading.CancellationTokenSource]::new([System.TimeSpan]::FromSeconds($TimeoutSec))
        try {
            $Response = $Client.GetAsync($BaseUrl, $CancellationSource.Token).GetAwaiter().GetResult()
            try {
                $Html = $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            }
            finally {
                $Response.Dispose()
            }
        }
        finally {
            $CancellationSource.Dispose()
        }

        $IsSuspended = $Html -match 'The environment is suspended'
        "{0} - Environment suspended: {1}." -f $MyInvocation.MyCommand, $IsSuspended | Write-Verbose
        return $IsSuspended
    }
    catch {
        # Include the exception message so callers can distinguish an invalid URL from a timeout,
        # DNS/TLS failure, etc. Behavior is unchanged: an unreachable environment is treated as
        # "not suspended" so a failed probe never blocks an otherwise valid request.
        "{0} - could not determine environment status: {1}" -f $MyInvocation.MyCommand, $_.Exception.Message | Write-Verbose
        return $false
    }
}
