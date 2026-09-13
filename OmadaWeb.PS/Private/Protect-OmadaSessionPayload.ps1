function Protect-OmadaSessionPayload {
    <#
    .SYNOPSIS
    Turn the private half of an exported session into one DPAPI-protected string.

    .DESCRIPTION
    The counterpart of Unprotect-OmadaSessionPayload, and the in-memory sibling of
    Export-OmadaCookieFile: the same PSSerializer-into-SecureString protection, but returning the
    protected text instead of writing it to a file.

    Export-OmadaSession hands a caller something it will move between runspaces and may well put
    somewhere - a queue, a job argument, a variable it forgets about. What it holds is a live bearer
    token, so the token never appears in the object at all; this string does, and it is ciphertext
    bound by DPAPI to the current user on the current machine. A copy taken off the machine is inert.

    The same binding is why the state is not portable between users or machines, which is the
    intended limit: seeding another user's session is not a scenario this module supports.

    The module refuses to load on non-Windows (OmadaWeb.PS.psm1), so DPAPI is always available here.

    .PARAMETER Payload
    The object to protect. Serialized whole, so it may be a hashtable or a PSCustomObject holding
    the session key, the cookie and whatever else the state has to carry.

    .OUTPUTS
    [string] the protected text, as produced by ConvertFrom-SecureString.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The plaintext is the serialized session, held in memory for the length of this call; -AsPlainText is the only way to put an existing string under DPAPI protection. This mirrors Export-OmadaCookieFile.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        $Payload
    )

    # PSSerializer rather than Export-Clixml: the whole object graph has to become one string before
    # it can go into a SecureString, and nothing here should touch the file system.
    $PayloadCliXml = [System.Management.Automation.PSSerializer]::Serialize($Payload, [int]::MaxValue)
    $SecurePayload = ConvertTo-SecureString -String $PayloadCliXml -AsPlainText -Force

    return ($SecurePayload | ConvertFrom-SecureString)
}
