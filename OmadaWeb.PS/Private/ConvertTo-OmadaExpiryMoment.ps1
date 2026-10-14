function ConvertTo-OmadaExpiryMoment {
    <#
    .SYNOPSIS
    Turn whatever a value claims to be an expiry into a UTC moment, or into nothing.

    .DESCRIPTION
    The single rule for reading an expiry, used both by Get-OmadaCookieExpiry for a cookie's own
    expiry and by Import-OmadaSession for the one recorded on an exported session.

    An expiry arrives in whatever shape it survived in. A live cookie carries a DateTime; one that
    has been through a serialization round trip can carry a string; WebView2's own surface counts
    seconds since the Unix epoch. All of those are understood.

    Anything else is answered with $null, which reads as "this does not declare an expiry" - never
    as "expired". That matters in both directions. A session cookie genuinely has no expiry, and
    refusing it would break exactly the sessions this is meant to protect; and a value that cannot
    be understood must not be allowed to throw a FormatException out of a caller whose contract is
    to raise OmadaSessionExpired. A session that slips past this check because its expiry could not
    be read is not trusted as a result - it is simply left to the server, which answers 401 and
    produces the same error by the other route.

    .PARAMETER Value
    The value to read. $null is accepted and answered $null.

    .OUTPUTS
    [datetime] in UTC, or $null when the value does not declare a usable expiry.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    $Expiry = $null
    if ($Value -is [datetime]) {
        $Expiry = $Value
    }
    elseif ($Value -is [System.DateTimeOffset]) {
        $Expiry = $Value.UtcDateTime
    }
    elseif ($Value -is [double] -or $Value -is [int] -or $Value -is [long] -or $Value -is [decimal]) {
        # WebView2's own surface reports the expiry as seconds since the Unix epoch, and a cookie
        # that has been through a serialization round trip can surface it that way too.
        try {
            $Expiry = [System.DateTimeOffset]::FromUnixTimeSeconds([long]$Value).UtcDateTime
        }
        catch {
            return $null
        }
    }
    else {
        $Parsed = [datetime]::MinValue
        # InvariantCulture with AssumeUniversal: an expiry is defined in UTC, so a string without an
        # offset must not be read as local time on a machine that is not. TryParse rather than a
        # cast, because a cast raises a FormatException on anything it cannot read and the callers'
        # contract is to answer with their own error, not that one.
        $Styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
        if ([datetime]::TryParse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, $Styles, [ref]$Parsed)) {
            $Expiry = $Parsed
        }
        else {
            return $null
        }
    }

    # Both sentinels mean "no expiry was recorded": MinValue is what a session cookie carries, and
    # MaxValue is what one that never expires carries. Treating MinValue as a date would make every
    # session cookie look like it died in the year one.
    if ($Expiry -eq [datetime]::MinValue -or $Expiry -eq [datetime]::MaxValue) {
        return $null
    }

    if ($Expiry.Kind -eq [System.DateTimeKind]::Unspecified) {
        return [datetime]::SpecifyKind($Expiry, [System.DateTimeKind]::Utc)
    }

    return $Expiry.ToUniversalTime()
}
