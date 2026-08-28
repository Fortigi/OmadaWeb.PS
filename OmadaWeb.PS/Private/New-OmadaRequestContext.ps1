function New-OmadaRequestContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$BoundParams,

        [Parameter(Mandatory)]
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session,

        [Parameter(Mandatory)]
        [psobject]$SessionContext
    )

    # One request's mutable state, gathered into a single object so the private helpers can take it
    # as a parameter instead of reading $BoundParams, $Session and $SessionContext out of their
    # caller's scope. Members:
    #
    #   BoundParams    - hashtable of the caller's bound parameters. Every helper reads it and most
    #                    add to it: headers, credential, Authorization, UseDefaultCredentials.
    #   Session        - the WebRequestSession carrying the cookie container and the user agent.
    #   SessionContext - per-(base URL, authentication type, identity) state, the object returned by
    #                    Get-OmadaSessionContext.
    #
    # The three members are the same object instances the caller holds, not copies, so a helper that
    # adds a header or a cookie still mutates what the caller is about to send - the behavior is
    # unchanged. What changes is that the dependency is declared in the helper's own param() block
    # and visible at the call site instead of being inherited invisibly from the calling scope.
    #
    # Helpers that modify the context return it, so call sites read:
    #     $RequestContext = Invoke-BasicAuthentication -RequestContext $RequestContext
    # Set-RequestParameter only reads the context and returns the parameter hashtable instead.
    return [pscustomobject]@{
        PSTypeName     = "OmadaWeb.PS.RequestContext"
        BoundParams    = $BoundParams
        Session        = $Session
        SessionContext = $SessionContext
    }
}
