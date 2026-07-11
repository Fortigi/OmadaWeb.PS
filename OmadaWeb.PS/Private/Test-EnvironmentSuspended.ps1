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
        Add-Type -AssemblyName System.Net.Http
        $Client = [System.Net.Http.HttpClient]::new()
        $Client.Timeout = [System.TimeSpan]::FromSeconds($TimeoutSec)
        try {
            $Response = $Client.GetAsync($BaseUrl).GetAwaiter().GetResult()
            $Html = $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
        finally {
            if ($null -ne $Response) { $Response.Dispose() }
            $Client.Dispose()
        }
        $IsSuspended = $Html -match 'The environment is suspended'
        "{0} - Environment suspended: {1}." -f $MyInvocation.MyCommand, $IsSuspended | Write-Verbose
        return $IsSuspended
    }
    catch {
        "{0} - could not determine environment status." -f $MyInvocation.MyCommand | Write-Verbose
        return $false
    }
}

