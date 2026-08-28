function Get-RetryAfterDelay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Exception,
        # A negative cap would make Math.Min below return a negative delay, which reads as
        # "retry immediately" and prints as a nonsense verbose line. Zero stays valid: it means
        # honour Retry-After by retrying without waiting.
        [ValidateRange(0, [double]::MaxValue)]
        [double]$MaximumDelaySec = 300
    )

    # Returns the delay in seconds the server asked for through the Retry-After response header, or
    # $null when the header is absent, empty or not parseable - in which case the caller falls back
    # to its own exponential backoff. Both forms defined by RFC 9110 are supported: delay-seconds
    # ("Retry-After: 120") and HTTP-date ("Retry-After: Wed, 21 Oct 2026 07:28:00 GMT").
    if ($null -eq $Exception) {
        return $null
    }

    $ResponseProperty = $Exception.PSObject.Properties['Response']
    if (-not $ResponseProperty -or $null -eq $ResponseProperty.Value) {
        return $null
    }

    $HeadersProperty = $ResponseProperty.Value.PSObject.Properties['Headers']
    if (-not $HeadersProperty -or $null -eq $HeadersProperty.Value) {
        return $null
    }
    $Headers = $HeadersProperty.Value

    $RetryAfter = $null
    if ($Headers -is [System.Net.WebHeaderCollection]) {
        # Windows PowerShell 5.1: WebException.Response is an HttpWebResponse whose headers are a
        # WebHeaderCollection, which returns the raw header value straight from its indexer.
        $RetryAfter = $Headers['Retry-After']
    }
    else {
        # PowerShell 7: HttpResponseException.Response is an HttpResponseMessage whose headers are
        # an HttpResponseHeaders, enumerating as key/value pairs where the value is a collection of
        # strings. A plain dictionary needs GetEnumerator() to enumerate as pairs rather than as a
        # single object, which is also what makes this branch reachable from the unit tests.
        $Entries = $Headers
        if ($Headers -is [System.Collections.IDictionary]) {
            $Entries = $Headers.GetEnumerator()
        }
        foreach ($Entry in $Entries) {
            $KeyProperty = $Entry.PSObject.Properties['Key']
            if ($KeyProperty -and $KeyProperty.Value -eq 'Retry-After') {
                $RetryAfter = @($Entry.Value)[0]
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($RetryAfter)) {
        return $null
    }
    $RetryAfter = ([string]$RetryAfter).Trim()

    # delay-seconds is 1*DIGIT, so it is matched with a regex rather than a culture-sensitive
    # numeric parse - a decimal-comma culture must not change how a wire format is read.
    if ($RetryAfter -match '^\d+$') {
        # Parsed rather than cast. Nothing stops a server sending more digits than a double can
        # represent, and on Windows PowerShell 5.1 casting one of those throws - which would turn
        # the very failure being handled into a hard error, from inside the retry path. A value too
        # large to represent is simply capped, which is what the cap is for. PowerShell 7 parses the
        # same input to Infinity, and Math.Min reduces that to the cap on its own.
        $DelaySec = 0.0
        if (-not [double]::TryParse($RetryAfter, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$DelaySec)) {
            return $MaximumDelaySec
        }
        return [math]::Min($DelaySec, $MaximumDelaySec)
    }

    $RetryAfterDate = [datetime]::MinValue
    $DateStyles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([datetime]::TryParse($RetryAfter, [System.Globalization.CultureInfo]::InvariantCulture, $DateStyles, [ref]$RetryAfterDate)) {
        # A date already in the past means "retry now", not "wait a negative amount of time".
        $DelaySec = ($RetryAfterDate - [datetime]::UtcNow).TotalSeconds
        if ($DelaySec -lt 0) {
            $DelaySec = 0
        }
        return [math]::Min($DelaySec, $MaximumDelaySec)
    }

    return $null
}
