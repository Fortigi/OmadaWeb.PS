function Unprotect-OmadaSessionPayload {
    <#
    .SYNOPSIS
    Read back what Protect-OmadaSessionPayload produced.

    .DESCRIPTION
    The single reader for the protected half of an exported session, matching
    Protect-OmadaSessionPayload.

    Anything that cannot be read is answered the same way: $null. That covers a string this user
    cannot decrypt because it was created by someone else or on another machine, a truncated one,
    and one that was never protected text to begin with. The caller turns that single answer into
    one clear error, rather than leaking three different failures with three different messages -
    none of which the caller could act on differently anyway.

    .PARAMETER ProtectedPayload
    The protected text, as held in the ProtectedState property of an exported session.

    .OUTPUTS
    The deserialized payload, or $null when it cannot be read.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$ProtectedPayload
    )

    if ([string]::IsNullOrWhiteSpace($ProtectedPayload)) {
        return $null
    }

    # SecureStringToBSTR allocates unmanaged memory holding the decrypted document. It is not
    # garbage collected and it is not zeroed on release, so without the finally below the plaintext
    # session cookie would sit in the process's unmanaged heap until the process exits - and turn up
    # in any memory dump taken meanwhile. The same reasoning as in Import-OmadaCookieFile.
    $Bstr = [System.IntPtr]::Zero
    try {
        $SecurePayload = ConvertTo-SecureString -String $ProtectedPayload -ErrorAction Stop
        $Bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePayload)

        # PtrToStringBSTR, not PtrToStringAuto: SecureStringToBSTR returns a length-prefixed BSTR,
        # so this is the marshaller that reads exactly the right number of characters.
        $PlainCliXml = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr)
        return [System.Management.Automation.PSSerializer]::Deserialize($PlainCliXml)
    }
    catch {
        "{0} - The protected session state could not be read: {1}" -f $MyInvocation.MyCommand, $PSItem.Exception.Message | Write-Verbose
        return $null
    }
    finally {
        if ($Bstr -ne [System.IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr)
        }
    }
}
