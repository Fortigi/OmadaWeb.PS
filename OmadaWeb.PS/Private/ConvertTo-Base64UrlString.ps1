function ConvertTo-Base64UrlString {
    <#
    .SYNOPSIS
        Encodes bytes as base64url, the alphabet JSON Web Tokens are written in.

    .DESCRIPTION
        A JWT is three base64url segments joined by dots, and base64url is not the same alphabet as
        base64: '+' becomes '-', '/' becomes '_', and the '=' padding is dropped, so that the value
        survives being placed in a URL or a form body without further escaping.

        The difference is small enough to be written inline at each of the places a token needs it,
        and that is exactly why it is not: a single '+' left unconverted produces a token the
        identity provider rejects with a signature error, which reads like a key problem rather than
        an encoding one.

    .PARAMETER Byte
        The bytes to encode.

    .OUTPUTS
        System.String. The base64url representation, without padding.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]]$Byte
    )

    return [Convert]::ToBase64String($Byte).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}
