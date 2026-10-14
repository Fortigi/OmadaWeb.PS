function Protect-LogMessage {
    <#
    .SYNOPSIS
        Masks secret material in an already-flattened log line.

    .DESCRIPTION
        Structure-aware redaction happens in ConvertTo-RedactedLogString, which needs an object to
        walk. This function is the safety net for text that never was an object: exception messages
        raised by Invoke-RestMethod/Invoke-WebRequest and the browser stack, which routinely quote the
        request that failed - headers included.

        NOTE: this function must not log anything itself - the call sites that use it are logging
        call sites, so writing to the verbose stream from here would recurse.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message
    )

    if ([string]::IsNullOrEmpty($Message)) {
        return $Message
    }

    try {
        $Redacted = "***REDACTED***"
        $Result = $Message

        # Auth scheme followed by a token. The token is required, so a bare "AuthenticationType: Basic"
        # - which is useful diagnostic information - survives untouched. The character class is the
        # RFC 6750 b64token set (letters, digits, "-._~+/", trailing "=" padding) plus "%" and "!",
        # which real-world bearer tokens have been seen to carry, so the match consumes the whole
        # token instead of stopping partway through it.
        $Result = $Result -replace '(?i)\b(Basic|Bearer|Negotiate|NTLM|Digest)\s+([A-Za-z0-9\-._~+/%!]{8,}=*)', ('$1 {0}' -f $Redacted)

        # Bare JWTs, which turn up in OAuth2 responses and cached-token messages without a scheme prefix.
        $Result = $Result -replace '\beyJ[A-Za-z0-9_\-]{4,}\.[A-Za-z0-9_\-]{4,}\.[A-Za-z0-9_\-]*', '***REDACTED-JWT***'

        # Credentials embedded in a URL's user-info, e.g. https://user:pass@host/path or the PAT-style
        # https://token@host/path with no colon at all. Left in place, AbsoluteUri-style logging would
        # carry them straight through the rest of this function, since none of the key/value or cookie
        # patterns below look inside a URL's authority component. Requiring the "scheme://" prefix is
        # what keeps a plain-text email address such as mark@example.com untouched.
        $Result = $Result -replace '(?i)\b([a-z][a-z0-9+.\-]*://)[^/\s@]+@', ('$1{0}@' -f $Redacted)

        # JSON-style pairs whose key names a secret, e.g. {"Password": "..."} or {"X-CSRF-Token": "..."}.
        # The lookahead spares the one value ConvertTo-RedactedLogString deliberately emits for a
        # credential - "PSCredential(UserName=...)" - which carries no password and answers the first
        # question you ask of a 401. Without it the safety net would undo that upstream decision.
        # "-"/"_" separators are tolerated in the multi-word names (api-key, subscription_key, ...) so
        # this stays in step with the normalization Test-SensitiveLogName applies to member names.
        $Result = $Result -replace '(?i)("[^"]*(?:authorization|cookie|credential|password|pwd|secret|token|api[-_]?key|client[-_]?secret|session[-_]?key|csrf|assertion|private[-_]?key|connection[-_]?string|subscription[-_]?key|functions?[-_]?key|passwd|passphrase|protectedstate|signature)[^"]*"\s*:\s*)"(?!(?:PS|Network)Credential\(UserName=)[^"]*"', ('$1"{0}"' -f $Redacted)

        # JSON keys short enough that matching them as a substring would redact ordinary properties
        # (StatusCode, Keys) - see Test-SensitiveLogName. Only fires when the quoted key is exactly
        # "key" or "sig", never when it merely contains one of those words. "code" is deliberately
        # absent - see the module-scope comment on $Script:SensitiveLogNameExactPatterns.
        $Result = $Result -replace '(?i)("(?:key|sig)"\s*:\s*)"[^"]*"', ('$1"{0}"' -f $Redacted)

        # A JSON name/value pair, e.g. {"name":"oisauthtoken","value":"..."}. ConvertTo-RedactedLogString
        # masks the Value member of such a pair whatever the Name is, once it has an object to walk;
        # this is the same rule applied to text that never was one, so the two layers agree. Handles
        # both field orders.
        $Result = $Result -replace '(?i)("name"\s*:\s*"[^"]*"\s*,\s*"value"\s*:\s*)"[^"]*"', ('$1"{0}"' -f $Redacted)
        $Result = $Result -replace '(?i)("value"\s*:\s*)"[^"]*"(\s*,\s*"name"\s*:\s*"[^"]*")', ('$1"{0}"$2' -f $Redacted)

        # Query-string, form and cookie style pairs: the key names the secret and the value follows an
        # "=" up to the next separator. Matches "client_secret=abc123", "oisauthtoken=abc123" and
        # "X-CSRF-Token=abc123"; leaves "grant_type=client_credentials" alone.
        $Result = $Result -replace '(?i)\b([\w.\-]*(?:password|pwd|secret|token|api[-_]?key|client[-_]?secret|session[-_]?key|private[-_]?key|connection[-_]?string|subscription[-_]?key|functions?[-_]?key|sessionid|auth|csrf|passwd|passphrase|signature)[\w.\-]*)\s*=\s*([^\s;,&"'']+)', ('$1={0}' -f $Redacted)

        # "key" is the same short, ambiguous name as above - matched only as the whole parameter name.
        # A lookbehind, not just \b, so a name with "-" or "." directly in front of "key" - x.key,
        # some-key - is left alone rather than treated as the standalone name; "statuscode=200" and
        # "monkey=1" stay untouched either way.
        $Result = $Result -replace '(?i)(?<![\w.\-])(key)\s*=\s*([^\s;,&"'']+)', ('$1={0}' -f $Redacted)

        # OAuth authorization codes and Azure SAS signatures leak through redirect and blob URLs as
        # query-string parameters - masking that shape, and only that shape, catches the real leak
        # vector without touching a bare "Code" member (the AADSTS/sign-in error code this module
        # deliberately logs) or an unrelated "code=" pair such as "status code=401". The prefix also
        # matches "&amp;", since page source and HTML error bodies carry the query string HTML-escaped.
        $Result = $Result -replace '(?i)((?:[?&]|&amp;)code=)([^\s&#"'']+)', ('$1{0}' -f $Redacted)
        $Result = $Result -replace '(?i)((?:[?&]|&amp;)sig=)([^\s&#"'']+)', ('$1{0}' -f $Redacted)

        # Any Set-Cookie header, whatever the cookie is called.
        $Result = $Result -replace '(?i)(Set-Cookie:\s*)([^\s=;]+)=([^;\s]+)', ('$1$2={0}' -f $Redacted)

        # A request Cookie header masks every cookie it carries, whatever each one is called - unlike
        # a bare "name=value" elsewhere in a message, everything inside a Cookie header is session
        # state. [regex]::Replace with a MatchEvaluator is needed here because the number of cookies
        # varies and the -replace operator only ever substitutes the last capture of a repeated group.
        $Result = [regex]::Replace($Result, '(?i)(?<![\w-])(Cookie:\s*)([^\r\n]+)', {
                param($CookieMatch)

                $MaskedPairs = [regex]::Replace($CookieMatch.Groups[2].Value, '([^\s=;]+)=([^;\s]+)', ('$1={0}' -f $Redacted))
                return $CookieMatch.Groups[1].Value + $MaskedPairs
            })

        return $Result
    }
    catch {
        # Failing open would leak the very thing this function exists to hide.
        return "***REDACTION FAILED - MESSAGE SUPPRESSED***"
    }
}
