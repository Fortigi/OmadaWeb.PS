function Get-OmadaShortHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $Md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        return ([System.Guid]($Md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value)))).Guid -replace "-", ""
    }
    finally {
        $Md5.Dispose()
    }
}
