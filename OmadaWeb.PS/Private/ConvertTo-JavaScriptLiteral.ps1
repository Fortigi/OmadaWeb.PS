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

    $Literal = [System.String]$Value | ConvertTo-Json -Compress

    # JSON permits U+2028 (LINE SEPARATOR) and U+2029 (PARAGRAPH SEPARATOR) raw, and PowerShell 7
    # leaves them raw because it does not escape non-ASCII. Before ES2019 those two terminate a
    # JavaScript string literal just like a newline does, so escape them explicitly instead of
    # relying on the engine version behind CoreWebView2. The escaped form is valid JSON as well, so
    # the literal still parses back to the original value. Both the separators and their escapes are
    # built from the code points, so this file stays pure ASCII on disk.
    $EscapeFormat = '\u{0:x4}'

    foreach ($CodePoint in 0x2028, 0x2029) {
        $Separator = [System.String][System.Char]$CodePoint
        $Literal = $Literal.Replace($Separator, ($EscapeFormat -f $CodePoint))
    }

    return $Literal
}
