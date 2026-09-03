function Import-OmadaCookieFile {
    <#
    .SYNOPSIS
    Read an authentication cookie written by Export-OmadaCookieFile, migrating an unprotected file
    left behind by an earlier version.

    .DESCRIPTION
    The single reader for every cookie file this module produces. Protected files are the normal
    case. An unprotected one can only be a -CookiePath file written before issue #21 was fixed, and
    it is handled rather than rejected: refusing it would strand anyone who upgrades mid-session with
    an unexplained login, and deleting it silently would do the same.

    Instead the cookie is read, the file is immediately rewritten protected, and the user is told
    once - because until that rewrite happens their token has been sitting in a readable file, and
    that is worth knowing even though the module has now fixed it.

    The rewrite is best-effort. If it fails the cookie is still returned: the caller's request should
    not fail because a cache could not be upgraded.

    .PARAMETER Path
    Full path of the file to read.

    .OUTPUTS
    The stored cookie object, or $null when the file cannot be read at all. $null is a normal answer -
    every caller treats it as "no cookie yet" and authenticates.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (!(Test-Path -Path $Path -PathType Leaf)) {
        return $null
    }

    if (Test-OmadaCookieCacheFile -Path $Path) {
        # SecureStringToBSTR allocates unmanaged memory holding the decrypted document. It is not
        # garbage collected and it is not zeroed on release, so without the finally below the
        # plaintext cookie would sit in the process's unmanaged heap until the process exits - and
        # turn up in any memory dump taken meanwhile. Decrypting a protected file only to leave the
        # plaintext lying about would defeat the point of protecting it.
        $Bstr = [System.IntPtr]::Zero
        try {
            $Bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR((Import-Clixml -Path $Path))

            # PtrToStringBSTR, not PtrToStringAuto: SecureStringToBSTR returns a length-prefixed
            # BSTR, so this is the marshaller that reads exactly the right number of characters.
            $PlainCliXml = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr)
            return ([System.Management.Automation.PSSerializer]::Deserialize($PlainCliXml)).OmadaWebAuthCookie
        }
        catch {
            # A protected file this user cannot decrypt - copied from another machine or profile - is
            # indistinguishable from a corrupt one, and both mean the same thing: authenticate.
            "Failure loading cookie from '{0}', try to create a new one." -f $Path | Write-Verbose
            return $null
        }
        finally {
            if ($Bstr -ne [System.IntPtr]::Zero) {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr)
            }
        }
    }

    # Unprotected: written by a version of this module that predates issue #21.
    try {
        $AuthCookie = (Import-Clixml -Path $Path).OmadaWebAuthCookie
    }
    catch {
        "Failure loading cookie from '{0}', try to create a new one." -f $Path | Write-Verbose
        return $null
    }

    "The cookie file '{0}' was stored unprotected by an earlier version of this module and has been re-written encrypted. The authentication token was readable by anything running as this user until now; if that file was on shared or synchronised storage, sign out of the Omada session to invalidate the token." -f $Path | Write-Warning

    if (!(Export-OmadaCookieFile -Path $Path -AuthCookie $AuthCookie)) {
        "The cookie file '{0}' could not be re-written encrypted and is still unprotected." -f $Path | Write-Warning
    }

    return $AuthCookie
}
