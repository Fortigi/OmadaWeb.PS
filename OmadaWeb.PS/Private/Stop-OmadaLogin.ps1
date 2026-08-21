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
        [string]$Engine = "WebView2"
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
            $PageAddress = Protect-LogMessage -Message $Url
        }
    }

    $SafeMessage = Protect-LogMessage -Message $Message

    $Script:LoginAbortReason = [pscustomobject]@{
        Message = $SafeMessage
        Code    = $Code
        Reason  = $Reason
        Url     = $PageAddress
        Engine  = $Engine
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
    $Lines.Add("Opening the sign-in window again would land on this same page, so no further attempts are made. Resolve this with the account or the application registration - for example by signing in with an account from the application's own tenant - and then retry, using -ForceAuthentication to start from a clean sign-in.")

    ($Lines -join [System.Environment]::NewLine) | Write-Warning

    if (-not [string]::IsNullOrWhiteSpace($Url)) {
        "Stop-OmadaLogin - Full page URL: {0}" -f (Protect-LogMessage -Message $Url) | Write-Verbose
    }

    return $true
}
