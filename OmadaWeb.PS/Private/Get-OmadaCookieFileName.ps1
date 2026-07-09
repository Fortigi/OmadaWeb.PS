function Get-OmadaCookieFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Uri]$Uri,

        [AllowNull()]
        [System.Management.Automation.PSCredential]$Credential,

        [AllowNull()]
        [string]$SessionKey
    )

    # Matches Get-OmadaSessionKey's identity resolution, so a given session's -CookiePath file name
    # is unique when a Credential/-SessionKey distinguishes it from other sessions on the same host -
    # otherwise it keeps the plain "<Authority>.cookie" name used before per-session keying existed.
    $Identity = $null
    if ($null -ne $Credential -and -not [string]::IsNullOrWhiteSpace($Credential.UserName)) {
        $Identity = $Credential.UserName.Trim()
    }
    elseif (-not [string]::IsNullOrWhiteSpace($SessionKey)) {
        $Identity = $SessionKey.Trim()
    }

    if ([string]::IsNullOrEmpty($Identity)) {
        return "{0}.cookie" -f $Uri.Authority
    }

    $IdentityHash = (Get-OmadaShortHash $Identity).Substring(0, 8)
    return "{0}_{1}.cookie" -f $Uri.Authority, $IdentityHash
}
