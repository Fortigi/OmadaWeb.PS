function Import-OmadaCookieFile {
    <#
    .SYNOPSIS
    Read an authentication cookie written by Export-OmadaCookieFile.

    .DESCRIPTION
    The single reader for every cookie file this module produces, matching Export-OmadaCookieFile.

    Only a protected file is read. Anything else - an unprotected file written by a version of this
    module that predates issue #21, a file that cannot be decrypted because it was copied from
    another machine or profile, or a corrupt one - is treated the same way: no cookie. The caller
    authenticates, and the next successful sign-in overwrites the file protected.

    There is deliberately no migration of an unprotected file. Omada session cookies are short lived,
    so one written by an older version has almost certainly expired anyway; reading it would buy at
    most a few minutes of not signing in, in exchange for a code path that exists solely to consume
    the format this change set out to stop producing.

    .PARAMETER Path
    Full path of the file to read.

    .OUTPUTS
    The stored cookie object, or $null when there is nothing usable. $null is a normal answer - every
    caller treats it as "no cookie yet" and authenticates.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (!(Test-Path -Path $Path -PathType Leaf)) {
        return $null
    }

    if (!(Test-OmadaCookieCacheFile -Path $Path)) {
        "The cookie file '{0}' is not in the protected format and is ignored; authenticating instead." -f $Path | Write-Verbose
        return $null
    }

    # SecureStringToBSTR allocates unmanaged memory holding the decrypted document. It is not garbage
    # collected and it is not zeroed on release, so without the finally below the plaintext cookie
    # would sit in the process's unmanaged heap until the process exits - and turn up in any memory
    # dump taken meanwhile. Decrypting a protected file only to leave the plaintext lying about would
    # defeat the point of protecting it.
    $Bstr = [System.IntPtr]::Zero
    try {
        $Bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR((Import-Clixml -Path $Path))

        # PtrToStringBSTR, not PtrToStringAuto: SecureStringToBSTR returns a length-prefixed BSTR, so
        # this is the marshaller that reads exactly the right number of characters.
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
