function Get-OmadaCookieExpiry {
    <#
    .SYNOPSIS
    Read the expiry moment out of an authentication cookie, whichever engine produced it.

    .DESCRIPTION
    The two browser engines hand back two different objects. WebView2 builds a PSCustomObject with
    an 'expires' property (Get-WebView2Cookie.ps1), while Selenium returns an OpenQA.Selenium.Cookie
    whose expiry lives on 'Expiry' (Get-DataFromWebDriver.ps1). This finds whichever of those the
    cookie has, so callers can ask a cookie when it dies without caring which engine signed in.

    What the value is then read as is ConvertTo-OmadaExpiryMoment's business, and so is the decision
    that an unreadable or absent expiry answers $null rather than a date.

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

    return (ConvertTo-OmadaExpiryMoment -Value $Value)
}
