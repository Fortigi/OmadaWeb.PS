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
    "{0} - Session key: {1}" -f $MyInvocation.MyCommand, $Key | Write-Verbose
    return $Key
}
