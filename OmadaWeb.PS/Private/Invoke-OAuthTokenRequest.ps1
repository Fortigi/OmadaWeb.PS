function Invoke-OAuthTokenRequest {
    <#
    .SYNOPSIS
        Performs the OAuth2 client-credentials token request.

    .DESCRIPTION
        Split out of Invoke-OAuth2Authentication so a test can replace exactly this call. A Pester mock
        of Invoke-RestMethod itself, even one scoped to this module, is invisible to nothing else in
        the module - but Invoke-OmadaRestMethod's own dynamicparam block calls Set-DynamicParameter,
        which introspects the real Invoke-RestMethod cmdlet to build its dynamic parameters, and a mock
        of that cmdlet breaks that introspection for the rest of the same test. Naming this call gives
        it a seam of its own that a mock cannot collide with.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [hashtable]$Body
    )

    $Arguments = @{
        Method      = "Post"
        Uri         = $Uri
        Body        = $Body
        ContentType = 'application/x-www-form-urlencoded'
        ErrorAction = "Stop"
    }

    # UseBasicParsing is deprecated since PowerShell Core 6, there it is only set when using PowerShell 5 (https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest?view=powershell-7.4#-usebasicparsing)
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $Arguments.Add("UseBasicParsing", $true)
    }

    return Invoke-RestMethod @Arguments
}
