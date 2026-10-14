function Get-OmadaSessionKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Uri]$Uri,

        [Parameter(Mandatory)]
        [string]$AuthenticationType,

        [AllowNull()]
        [System.Management.Automation.PSCredential]$Credential,

        [AllowNull()]
        [string]$SessionKey,

        [AllowNull()]
        [string]$UserName
    )

    $Identity = ""
    # -UserName is read first because it is the more explicit of the two, and because it is the one
    # that can be supplied without a password. Two accounts against the same host must never share a
    # session: they do not share a cookie, and they must not share the browser profile that decides
    # which of them signs in silently next time.
    if (-not [string]::IsNullOrWhiteSpace($UserName)) {
        $Identity = $UserName.Trim().ToLowerInvariant()
    }
    elseif ($null -ne $Credential -and -not [string]::IsNullOrWhiteSpace($Credential.UserName)) {
        $Identity = $Credential.UserName.Trim().ToLowerInvariant()
    }
    elseif (-not [string]::IsNullOrWhiteSpace($SessionKey)) {
        $Identity = $SessionKey.Trim().ToLowerInvariant()
    }

    $Key = "{0}::{1}::{2}" -f $Uri.Authority.ToLowerInvariant(), $AuthenticationType.ToLowerInvariant(), $Identity

    # Log a short hash of the identity segment rather than the raw credential username/-SessionKey
    # value, so verbose/debug logs don't leak user-identifying data while still letting different
    # sessions be told apart in the log output.
    $LoggedIdentity = if ([string]::IsNullOrEmpty($Identity)) { "" } else { (Get-OmadaShortHash $Identity).Substring(0, 8) }
    $LoggedKey = "{0}::{1}::{2}" -f $Uri.Authority.ToLowerInvariant(), $AuthenticationType.ToLowerInvariant(), $LoggedIdentity
    "{0} - Session key: {1}" -f $MyInvocation.MyCommand, $LoggedKey | Write-Verbose
    return $Key
}
