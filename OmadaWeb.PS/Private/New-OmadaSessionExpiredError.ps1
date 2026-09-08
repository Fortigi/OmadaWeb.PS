function New-OmadaSessionExpiredError {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$BaseUrl,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [System.Exception]$InnerException
    )

    # Both places that refuse to sign in under -NoInteractiveAuthentication build their error here, so
    # the two cases a caller has to tell apart - no session at all, and a session the server has just
    # rejected - arrive as one recognisable error rather than two lookalikes.
    #
    # AuthenticationException rather than a type this module defines: the module ships as script
    # files, so a custom exception would need Add-Type at import, and a caller matching on the type
    # would have to reach into module-private state to name it. This one is in the BCL on both
    # engines, so 'catch [System.Security.Authentication.AuthenticationException]' works from any
    # caller without a reference to anything.
    if ($null -ne $InnerException) {
        $Exception = [System.Security.Authentication.AuthenticationException]::new($Message, $InnerException)
    }
    else {
        $Exception = [System.Security.Authentication.AuthenticationException]::new($Message)
    }

    $TargetObject = $null
    if (![string]::IsNullOrWhiteSpace($BaseUrl)) {
        $TargetObject = $BaseUrl
    }

    # The error id is the documented half of the contract. Callers match it with
    # 'OmadaSessionExpired*' rather than for equality, because every ThrowTerminatingError this
    # record passes through on its way out appends the throwing function's name to the id.
    return [System.Management.Automation.ErrorRecord]::new(
        $Exception,
        "OmadaSessionExpired",
        [System.Management.Automation.ErrorCategory]::AuthenticationError,
        $TargetObject
    )
}
