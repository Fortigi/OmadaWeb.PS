function Test-OmadaTransientFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Exception
    )

    # Decides whether an exception carrying no HTTP status code is a socket-level blip worth
    # retrying. Types are matched by full name walked up the inheritance chain instead of with -is,
    # because System.Net.Http is not loaded by default on Windows PowerShell 5.1 and a literal type
    # reference to it would fault while resolving rather than simply not match.
    $NonTransientTypeNames = @(
        "System.Threading.Tasks.TaskCanceledException",
        "System.OperationCanceledException",
        "System.TimeoutException"
    )
    $TransientTypeNames = @(
        "System.Net.Sockets.SocketException",
        "System.Net.WebException",
        "System.Net.Http.HttpRequestException",
        "System.IO.IOException"
    )

    $Chain = [System.Collections.Generic.List[object]]::new()
    $Current = $Exception
    while ($null -ne $Current) {
        $Chain.Add($Current)
        $InnerProperty = $Current.PSObject.Properties['InnerException']
        $Current = if ($InnerProperty) { $InnerProperty.Value } else { $null }
    }

    # A client-side timeout or cancellation is deliberately not transient: retrying one multiplies
    # the wall-clock time a caller already bounded with -TimeoutSec. Bounding total retry time is
    # tracked separately as roadmap item D2. The non-transient scan runs over the whole chain first,
    # because .NET 5 and later surface a timeout as a TaskCanceledException wrapped in - or
    # wrapping - one of the transient types below.
    foreach ($Link in $Chain) {
        $Type = $Link.GetType()
        while ($null -ne $Type) {
            if ($Type.FullName -in $NonTransientTypeNames) {
                return $false
            }
            $Type = $Type.BaseType
        }
    }

    foreach ($Link in $Chain) {
        $Type = $Link.GetType()
        while ($null -ne $Type) {
            if ($Type.FullName -in $TransientTypeNames) {
                return $true
            }
            $Type = $Type.BaseType
        }
    }

    return $false
}
