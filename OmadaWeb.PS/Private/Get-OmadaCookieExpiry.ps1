function Get-OmadaCookieExpiry {
    <#
    .SYNOPSIS
    Read the expiry moment out of an authentication cookie, whichever engine produced it.

    .DESCRIPTION
    The two browser engines hand back two different objects. WebView2 builds a PSCustomObject with
    an 'expires' property holding a DateTime (Get-WebView2Cookie.ps1), while Selenium returns an
    OpenQA.Selenium.Cookie whose expiry lives on 'Expiry' as a nullable DateTime
    (Get-DataFromWebDriver.ps1). A cookie loaded from the encrypted cache is a deserialized copy of
    either, so the value can also arrive as a string or as a number of seconds since the Unix epoch.

    This is the one place that knows about all of those, so callers can ask a cookie when it dies
    without caring which engine signed in.

    Not every cookie has an answer. A session cookie has no expiry at all, and DateTime.MinValue or
    DateTime.MaxValue mean the same thing in practice. All of those return $null, which reads as
    "this cookie does not say" - never as "expired". Refusing a session on a value the cookie never
    carried would break exactly the sessions this is meant to protect.

    .PARAMETER AuthCookie
    The cookie object, as held in $SessionContext.AuthCookie. $null is accepted and answered $null.

    .OUTPUTS
    [datetime] in UTC, or $null when the cookie does not declare an expiry.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $AuthCookie
    )

    if ($null -eq $AuthCookie) {
        return $null
    }

    # Property lookup goes through PSObject rather than a direct member access: Set-StrictMode is
    # active throughout this module and its test suite, so reading a property an object does not
    # have is a terminating error - and "does not have it" is the normal case here.
    $Value = $null
    foreach ($Name in @("expires", "Expiry", "expiry", "Expires")) {
        $Property = $AuthCookie.PSObject.Properties[$Name]
        if ($null -ne $Property -and $null -ne $Property.Value) {
            $Value = $Property.Value
            break
        }
    }

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
        # WebView2's own COM surface reports the expiry as seconds since the Unix epoch, and a
        # cookie that has been through a serialization round trip can surface it that way too.
        try {
            $Expiry = [System.DateTimeOffset]::FromUnixTimeSeconds([long]$Value).UtcDateTime
        }
        catch {
            return $null
        }
    }
    else {
        $Parsed = [datetime]::MinValue
        # InvariantCulture with AssumeUniversal: a cookie's own expiry is defined in UTC, so a
        # string without an offset must not be read as local time on a machine that is not.
        $Styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
        if ([datetime]::TryParse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, $Styles, [ref]$Parsed)) {
            $Expiry = $Parsed
        }
        else {
            return $null
        }
    }

    # Both sentinels mean "no expiry was recorded": MinValue is what a session cookie carries, and
    # MaxValue is what a cookie that never expires carries. Treating MinValue as a date would make
    # every session cookie look like it died in the year one.
    if ($Expiry -eq [datetime]::MinValue -or $Expiry -eq [datetime]::MaxValue) {
        return $null
    }

    if ($Expiry.Kind -eq [System.DateTimeKind]::Unspecified) {
        return [datetime]::SpecifyKind($Expiry, [System.DateTimeKind]::Utc)
    }

    return $Expiry.ToUniversalTime()
}
