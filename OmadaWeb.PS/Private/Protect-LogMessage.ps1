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
        # - which is useful diagnostic information - survives untouched.
        $Result = $Result -replace '(?i)\b(Basic|Bearer|Negotiate|NTLM|Digest)\s+([A-Za-z0-9+/=._\-]{8,})', ('$1 {0}' -f $Redacted)

        # Bare JWTs, which turn up in OAuth2 responses and cached-token messages without a scheme prefix.
        $Result = $Result -replace '\beyJ[A-Za-z0-9_\-]{4,}\.[A-Za-z0-9_\-]{4,}\.[A-Za-z0-9_\-]*', '***REDACTED-JWT***'

        # JSON-style pairs whose key names a secret, e.g. {"Password": "..."} or {"X-CSRF-Token": "..."}.
        # The lookahead spares the one value ConvertTo-RedactedLogString deliberately emits for a
        # credential - "PSCredential(UserName=...)" - which carries no password and answers the first
        # question you ask of a 401. Without it the safety net would undo that upstream decision.
        $Result = $Result -replace '(?i)("[^"]*(?:authorization|cookie|credential|password|pwd|secret|token|apikey|api_key|clientsecret|sessionkey|csrf|assertion|privatekey|connectionstring)[^"]*"\s*:\s*)"(?!(?:PS|Network)Credential\(UserName=)[^"]*"', ('$1"{0}"' -f $Redacted)

        # Query-string, form and cookie style pairs: the key names the secret and the value follows an
        # "=" up to the next separator. Matches "client_secret=abc123", "oisauthtoken=abc123" and
        # "X-CSRF-Token=abc123"; leaves "grant_type=client_credentials" alone.
        $Result = $Result -replace '(?i)\b([\w.\-]*(?:password|pwd|secret|token|apikey|api_key|sessionid|sessionkey|auth|csrf)[\w.\-]*)\s*=\s*([^\s;,&"'']+)', ('$1={0}' -f $Redacted)

        # Any Set-Cookie header, whatever the cookie is called.
        $Result = $Result -replace '(?i)(Set-Cookie:\s*)([^\s=;]+)=([^;\s]+)', ('$1$2={0}' -f $Redacted)

        return $Result
    }
    catch {
        # Failing open would leak the very thing this function exists to hide.
        return "***REDACTION FAILED - MESSAGE SUPPRESSED***"
    }
}
