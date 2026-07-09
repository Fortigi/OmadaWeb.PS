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

    # Matches Get-OmadaSessionKey's identity resolution (including case normalization), so a given
    # session's -CookiePath file name is unique when a Credential/-SessionKey distinguishes it from
    # other sessions on the same host, and two calls that resolve to the same session key in memory
    # (e.g. differing only by casing) always resolve to the same on-disk file name too.
    # ":" (present in Uri.Authority for any non-default port, e.g. "localhost:8443") is illegal in
    # Windows filenames, so it's replaced rather than passed through.
    $Authority = $Uri.Authority.ToLowerInvariant() -replace ":", "_"
    $Identity = $null
    if ($null -ne $Credential -and -not [string]::IsNullOrWhiteSpace($Credential.UserName)) {
        $Identity = $Credential.UserName.Trim().ToLowerInvariant()
    }
    elseif (-not [string]::IsNullOrWhiteSpace($SessionKey)) {
        $Identity = $SessionKey.Trim().ToLowerInvariant()
    }

    if ([string]::IsNullOrEmpty($Identity)) {
        return "{0}.cookie" -f $Authority
    }

    $IdentityHash = (Get-OmadaShortHash $Identity).Substring(0, 8)
    return "{0}_{1}.cookie" -f $Authority, $IdentityHash
}
