function Test-SensitiveLogName {
    <#
    .SYNOPSIS
        Decides whether a member or header name is sensitive enough to redact its value.

    .DESCRIPTION
        Matches against two pattern sets on a normalized form of the name (lowercased, with "-" and
        "_" removed, so X-API-Key, x_api_key and ApiKey are all treated the same way).

        Substring patterns are long and unambiguous words such as "apikey" or "signature" - safe to
        match anywhere in the name. Exact patterns such as "key" and "sig" are short enough that
        matching them as substrings would redact ordinary members like StatusCode or Keys, so
        they are matched only when they are the whole normalized name. The exact names are "key"
        and "sig"; "code" is deliberately not a member-name pattern here, because a sign-in error's
        Code member is a diagnostic, and is masked only as a URL query parameter by Protect-LogMessage.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Name,
        [AllowEmptyCollection()]
        [string[]]$SubstringPatterns = @(),
        [AllowEmptyCollection()]
        [string[]]$ExactPatterns = @()
    )

    $NormalizedName = $Name.ToLowerInvariant() -replace '[-_]', ''

    foreach ($Pattern in $SubstringPatterns) {
        if ($NormalizedName -like "*$Pattern*") {
            return $true
        }
    }

    foreach ($Pattern in $ExactPatterns) {
        if ($NormalizedName -eq $Pattern) {
            return $true
        }
    }

    return $false
}
