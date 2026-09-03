function Export-OmadaCookieFile {
    <#
    .SYNOPSIS
    Write an authentication cookie to disk, protected at rest.

    .DESCRIPTION
    The single writer for every cookie file this module produces - the default cache and -CookiePath
    alike. It exists because those two used to disagree: the cache was DPAPI-protected while
    -CookiePath wrote the raw oisauthtoken as plain Clixml, so the opt-in "keep my cookie somewhere
    stable" parameter was also, silently, the one that left a usable bearer token in a readable file
    (issue #21). One writer means that cannot drift apart again.

    Protection is DPAPI via SecureString, which binds the file to the current user on the current
    machine. That is the point: a copied file is useless to anyone else. It also means a cookie file
    is no longer portable between users or machines, which is the behaviour change this fix
    deliberately makes - see the PR for issue #21.

    The module refuses to load on non-Windows (OmadaWeb.PS.psm1), so DPAPI is always available here.

    .PARAMETER Path
    Full path of the file to write. Overwritten if it exists.

    .PARAMETER AuthCookie
    The cookie object to store, as held in $SessionContext.AuthCookie.

    .OUTPUTS
    [bool] $true when the file was written. $false when it could not be, which is never fatal: a
    cookie that cannot be cached costs a login, not a failed request.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowNull()]
        $AuthCookie
    )

    try {
        $CookieObject = [PSCustomObject]@{
            OmadaWebAuthCookie = $AuthCookie
        }

        # PSSerializer rather than Export-Clixml directly: the whole object graph has to become one
        # string before it can go into a SecureString.
        $CookieCliXmlContent = [System.Management.Automation.PSSerializer]::Serialize($CookieObject, [int]::MaxValue)
        $SecureCookieCliXml = ConvertTo-SecureString -String $CookieCliXmlContent -AsPlainText -Force
        $SecureCookieCliXml | Export-Clixml -Path $Path -Force

        "{0} - Wrote protected cookie file: {1}" -f $MyInvocation.MyCommand, $Path | Write-Verbose
        return $true
    }
    catch [System.UnauthorizedAccessException] {
        "Unable to write the cookie file due to insufficient permissions in folder '{0}'" -f (Split-Path -Path $Path) | Write-Warning
        return $false
    }
    catch {
        "Unable to write the cookie file '{0}': {1}" -f $Path, $PSItem.Exception.Message | Write-Warning
        return $false
    }
}
