function Test-EnvironmentSuspended {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Url,
        [int]$TimeoutSec = 30
    )

    try {
        $Uri = [System.Uri]::new($Url)
        $Url = "{0}://{1}:{2}/" -f $Uri.Scheme, $Uri.Host, $Uri.Port
        Add-Type -AssemblyName System.Net.Http
        $Client = [System.Net.Http.HttpClient]::new()
        $Result = $Client.GetAsync($Url).Result
        $Html = $Result.Content.ReadAsStringAsync().Result
        $Client.Dispose()
        $IsSuspended = $Html -match 'The environment is suspended'
        "{0} - Environment is {1}." -f $MyInvocation.MyCommand, ($IsSuspended ? "suspended" : "active") | Write-Verbose
        return $IsSuspended
    }
    catch {
        "{0} - could not determine environment status." -f $MyInvocation.MyCommand | Write-Verbose
        return $false
    }
}

