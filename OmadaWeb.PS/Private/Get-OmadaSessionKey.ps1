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
        [string]$SessionKey
    )

    $Identity = ""
    if ($null -ne $Credential -and -not [string]::IsNullOrWhiteSpace($Credential.UserName)) {
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
