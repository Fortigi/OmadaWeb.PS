function ConvertTo-JavaScriptLiteral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]$Value
    )

    # Never concatenate caller-supplied text straight into a script string. ConvertTo-Json returns a
    # complete JSON string literal - surrounding double quotes included - and escapes the backslash,
    # the double quote and every control character, which is exactly the JavaScript string literal
    # grammar. Windows PowerShell additionally emits \uXXXX for non-ASCII and for < > & ' which is
    # equally valid JavaScript.
    if ($null -eq $Value) {
        return "null"
    }

    return ([System.String]$Value | ConvertTo-Json -Compress)
}
