function Set-Body {

    "{0} - {1} - Add Body" -f $MyInvocation.MyCommand, $BoundParams.Method | Write-Verbose
    if ($null -eq $BoundParams.Body) {
        "{0} - Provided -Body is empty this is mandatory for a {1} command" -f $MyInvocation.MyCommand , $BoundParams.Method | Write-Error -ErrorAction "Stop"
    }
    $BoundParams.Headers.Add("Content-Type", "application/json")
    if ($BoundParams.Body -is [hashtable]) {
        $BoundParams.Body = $BoundParams.Body | ConvertTo-Json
    }
    if ($BoundParams.Body -isnot [hashtable] -and $BoundParams.Body -isnot [string]) {
        "{0} - Content parameter should be a hashtable to string!" -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
    }
    $BoundParams.Body = $BoundParams.Body
    "{0} - {1}" -f $MyInvocation.MyCommand, ($BoundParams | ConvertTo-Json) | Write-Verbose

}