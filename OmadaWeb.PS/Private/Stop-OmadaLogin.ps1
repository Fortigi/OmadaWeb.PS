function Stop-OmadaLogin {
    <#
    .SYNOPSIS
        Ends a sign-in that cannot succeed, and records why.

    .DESCRIPTION
        Both login drivers are built to keep trying: WebView2 waits for the Omada response watchdog
        and then re-opens its window, Edge WebDriver polls until its retry count runs out. That is
        the right behaviour for a sign-in that is merely slow, and the wrong one for a sign-in the
        identity provider has already refused - there the module spends three watchdog timeouts, half
        an hour, re-opening a window that lands on the same error page every time.

        This is the single place that ends such a sign-in. It records the refusal in
        $Script:LoginAbortReason, which is what Get-DataFromWebView2 and Get-DataFromWebDriver check
        instead of starting another attempt, and prints the error the page carried so the user knows
        what to do about it rather than being told only that authentication failed.

        It does not close any window itself: the two drivers own very different objects (a WinForm
        and a WebDriver session) and each closes its own once it sees the recorded reason.

        Like Switch-ToManualLogin this guards against repeating itself, because the WebView2 timer
        ticks every 150 ms and would otherwise print the same page error dozens of times before the
        window is gone.

        Only the path of the page URL is reported, and the message goes through Protect-LogMessage:
        this text is written to streams users routinely capture into support logs, and a logon page
        can quote the request that got it there.

    .PARAMETER Message
        The error text read off the page.

    .PARAMETER Code
        Identity-provider error code found in that text, such as AADSTS50178, when there was one.

    .PARAMETER Reason
        What the error means for the caller, from Test-OmadaLogonPageError.

    .PARAMETER Url
        The page the browser was on.

    .PARAMETER Engine
        Which login driver hit this, for the diagnostic.

    .PARAMETER Category
        What kind of refusal this is, from Test-OmadaLogonPageError. It selects the closing advice
        and is recorded on $Script:LoginAbortReason, where the WebView2 driver reads it to decide
        whether offering the user another account could get past this.

    .OUTPUTS
        System.Boolean. True when this call recorded the refusal, false when one was already
        recorded for this sign-in.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Code,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Reason,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Url,

        [ValidateSet("WebView2", "EdgeWebDriver")]
        [string]$Engine = "WebView2",

        [ValidateSet("WrongAccount", "Authorization", "AppRegistration", "IdentityProvider", "Unknown", "None")]
        [string]$Category = "Unknown"
    )

    if ($null -ne $Script:LoginAbortReason) {
        "Sign-in was already stopped for this attempt - not reporting again" | Write-Verbose
        return $false
    }

    $PageAddress = "unknown"
    if (-not [string]::IsNullOrWhiteSpace($Url)) {
        try {
            $PageAddress = ([System.Uri]::New($Url)).GetLeftPart([System.UriPartial]::Path)
        }
        catch {
            # Not a parsable URI, so there is no path to ask for. Cut the string at the first '?'
            # or '#' by hand: whatever follows is query or fragment, and that is exactly the part
            # that carries tokens and must never reach the warning.
            $PageAddress = Protect-LogMessage -Message ($Url -split '[?#]')[0]
        }
    }

    $SafeMessage = Protect-LogMessage -Message $Message

    # The identifiers Entra names in a cross-tenant refusal, lifted out of the sentence so they can
    # be reported as facts. Nothing is invented when they are absent: Detail.HasDetail is false and
    # not a line of this is printed.
    $Detail = Get-EntraTenantMismatchDetail -Message $Message

    $Script:LoginAbortReason = [pscustomobject]@{
        Message  = $SafeMessage
        Code     = $Code
        Reason   = $Reason
        Url      = $PageAddress
        Engine   = $Engine
        Category = $Category
        Detail   = $Detail
    }

    # Autofill has nothing left to do on a sign-in that is over, and leaving it armed would let the
    # Microsoft scenarios act on whatever page the browser shows while the window closes.
    $Script:MicrosoftOnlineLogin = $false
    $Script:LoginFailed = $true
    $Script:LoginSubState = $null
    $Script:LoginTask = $null

    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add("Sign-in was refused and will not be retried.")
    if (-not [string]::IsNullOrWhiteSpace($Code)) {
        $Lines.Add("  Error code : {0}" -f $Code)
    }
    $Lines.Add("  Page URL   : {0}" -f $PageAddress)
    $Lines.Add("  Engine     : {0}" -f $Engine)
    $Lines.Add("  Message    : {0}" -f $SafeMessage)
    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        $Lines.Add("  Meaning    : {0}" -f $Reason)
    }

    # Everything below is quoted straight out of the page's own error text, which the drivers only
    # ever read off login pages, so there is no secret here to redact - and every line of it is
    # something the reader has to type into a portal search box to get any further.
    if ($Detail.HasDetail) {
        if (-not [string]::IsNullOrWhiteSpace($Detail.AccountTenantId)) {
            $Lines.Add("  Account in : tenant {0}" -f $Detail.AccountTenantId)
        }
        if (-not [string]::IsNullOrWhiteSpace($Detail.ResourceTenant)) {
            $Lines.Add("  Needed in  : tenant '{0}'" -f $Detail.ResourceTenant)
        }
        if (-not [string]::IsNullOrWhiteSpace($Detail.ApplicationId)) {
            $Application = $Detail.ApplicationId
            if (-not [string]::IsNullOrWhiteSpace($Detail.ApplicationName)) {
                $Application = "{0} ({1})" -f $Detail.ApplicationName, $Detail.ApplicationId
            }
            $Lines.Add("  Application: {0}" -f $Application)
        }
        if (-not [string]::IsNullOrWhiteSpace($Detail.CorrelationId)) {
            $Lines.Add("  Correlation: {0}" -f $Detail.CorrelationId)
        }
        if (-not [string]::IsNullOrWhiteSpace($Detail.TraceId)) {
            # Not the identifier the sign-in logs are searched by - that is the correlation id above -
            # but the one Microsoft support asks for, and it costs a line to keep both together.
            $Lines.Add("  Trace      : {0}" -f $Detail.TraceId)
        }
        if (-not [string]::IsNullOrWhiteSpace($Detail.Timestamp)) {
            $Lines.Add("  Timestamp  : {0}" -f $Detail.Timestamp)
        }
    }

    if ($Category -eq "WrongAccount") {
        # The one refusal where the remedy is the user's to apply, so it is spelled out instead of
        # being left as "resolve this with the account or the application registration".
        $TenantName = "the application's tenant"
        if (-not [string]::IsNullOrWhiteSpace($Detail.ResourceTenant)) {
            $TenantName = "tenant '{0}'" -f $Detail.ResourceTenant
        }

        $Lines.Add("This account cannot be used for this application however often the sign-in is repeated, so no further attempts are made. Sign in with an account of {0}, or have this account invited into it as a guest, and try again." -f $TenantName)

        if ($Detail.AccountNameWithheld) {
            # Saying this out loud saves the next reader from looking for a name that was never sent.
            $Lines.Add("Entra ID withholds the account name from this message because it identifies an end user. Look the attempt up by its correlation ID in the sign-in logs of the tenant that refused it to see which account was used.")
        }
    }
    else {
        $Lines.Add("Opening the sign-in window again would land on this same page, so no further attempts are made. Resolve this with the account or the application registration - for example by signing in with an account from the application's own tenant - and then retry, using -ForceAuthentication to start from a clean sign-in.")
    }

    ($Lines -join [System.Environment]::NewLine) | Write-Warning

    if (-not [string]::IsNullOrWhiteSpace($Url)) {
        "Stop-OmadaLogin - Full page URL: {0}" -f (Protect-LogMessage -Message $Url) | Write-Verbose
    }

    return $true
}
