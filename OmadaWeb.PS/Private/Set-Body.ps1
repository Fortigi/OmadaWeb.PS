function Set-Body {
    [CmdletBinding()]
    PARAM()

    "{0} - {1} - Add Body" -f $MyInvocation.MyCommand, $BoundParams.Method | Write-Verbose
    if ($null -eq $BoundParams.Body) {
        "{0} - Provided -Body is empty this is mandatory for a {1} command" -f $MyInvocation.MyCommand , $BoundParams.Method | Write-Error -ErrorAction "Stop"
    }

    if ("Content-Type" -notin $BoundParams.Headers.Keys) {
        $BoundParams.Headers.Add("Content-Type", "application/json")
    }
    else{
        $BoundParams.Headers.'Content-Type' = "application/json"
    }
    if ($BoundParams.Body.GetType().FullName -in @("System.Collections.Hashtable", "System.Collections.Specialized.OrderedDictionary", "System.Management.Automation.PSCustomObject")) {
        "{0} - Provided -Body data type is {1}, converting it to json" -f $MyInvocation.MyCommand, $BoundParams.Body.GetType().FullName | Write-Verbose
        $BoundParams.Body = $BoundParams.Body | ConvertTo-Json
    }
    else {
        "{0} - Provided -Body will be processed directly without converting it." -f $MyInvocation.MyCommand | Write-Verbose
    }
}