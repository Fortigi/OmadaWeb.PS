function Set-Body {
    [CmdletBinding()]
    PARAM(
        [Parameter(Mandatory)]
        [PSTypeName("OmadaWeb.PS.RequestContext")]$RequestContext
    )

    $BoundParams = $RequestContext.BoundParams

    "{0} - {1} - Add Body" -f $MyInvocation.MyCommand, $BoundParams['Method'] | Write-Verbose
    if ($null -eq $BoundParams['Body']) {
        "{0} - Provided -Body is empty this is mandatory for a {1} command" -f $MyInvocation.MyCommand , $BoundParams['Method'] | Write-Error -ErrorAction "Stop"
    }

    # Indexer assignment, not .Add: the key may already be present in the (now copied) Headers
    # dictionary, and this function always overrides it to json regardless - issue #105 addresses
    # that "always json" override behaviour separately, so it is kept as-is here beyond the
    # .Add -> indexer change.
    $BoundParams['Headers']['Content-Type'] = "application/json"
    if ($BoundParams['Body'].GetType().FullName -in @("System.Collections.Hashtable", "System.Collections.Specialized.OrderedDictionary", "System.Management.Automation.PSCustomObject")) {
        "{0} - Provided -Body data type is {1}, converting it to json" -f $MyInvocation.MyCommand, $BoundParams['Body'].GetType().FullName | Write-Verbose
        # Depth 100 (the maximum PowerShell accepts) so nested request bodies are never
        # silently truncated to their type name. Depth is a ceiling, not a cost: serialization
        # stops when the object graph ends, so a flat body is no slower than at the default.
        $BoundParams['Body'] = $BoundParams['Body'] | ConvertTo-Json -Depth 100
    }
    else {
        "{0} - Provided -Body will be processed directly without converting it." -f $MyInvocation.MyCommand | Write-Verbose
    }

    return $RequestContext
}
