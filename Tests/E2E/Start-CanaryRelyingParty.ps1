# Start-CanaryRelyingParty.ps1
#
# The loopback stand-in for an Omada environment used by the scheduled Entra sign-in canary
# (see .github/workflows/entra-canary.yml and docs/entra-canary.md).
#
# WHY THIS EXISTS
#
# The canary watches one thing: whether the Entra ID credential autofill tier still recognizes
# Microsoft's sign-in screens. That tier is Invoke-WebView2MicrosoftLogin driving what
# Get-EntraSignInProbeScript reads and Resolve-EntraSignInScreen judges, and the only way to know it
# still works is to point it at a live login.microsoftonline.com page.
#
# It must be the real driver, not a copy of it. A canary built on its own harness would happily go
# green while the shipping code path was broken, which is the one failure this whole exercise is
# meant to make impossible.
#
# Initialize-WebView2 navigates to the session's BaseUrl and then, on every timer tick, switches on
# the host the browser is currently on: the BaseUrl host means "look for the oisauthtoken cookie",
# and login.microsoftonline.com means "drive the sign-in". So a local listener standing in for the
# Omada host gives the entire real code path with no Omada environment involved:
#
#   1. The module navigates to http://localhost:<port>/
#   2. This listener answers 302 to the tenant's authorize endpoint for the canary app registration
#   3. The browser lands on Entra, the host no longer matches, and the real autofill driver takes over
#   4. Entra redirects back to http://localhost:<port>/canary, which sets oisauthtoken and returns 200
#   5. Get-WebView2Cookie finds the cookie, closes the window, and the request completes
#
# The authorization code is never redeemed. The canary asserts that the sign-in screens were driven,
# not that a token was issued - redeeming one would test Entra's token endpoint, which is not what
# breaks.
#
# TWO THINGS THE ROUTING HAS TO GET RIGHT
#
#   - The redirect path must not contain "logon", "login", "signin", "sign-in" or "error".
#     Get-OmadaLogonErrorScript treats a path matching those as an Omada logon page and then sweeps
#     the whole body for anything carrying an error severity, so a path like /signin-callback would
#     have the module scraping this page for a failure banner. "/canary" is deliberately none of them.
#   - The served page must carry no element whose class names an error severity, for the same reason.
#
# The listener runs in its own runspace because the WebView2 sign-in blocks the calling thread on a
# WinForms dialog: a listener on that thread would never answer the request that opens the window.

#Requires -Version 5.1

function New-CanaryPkcePair {
    <#
    .SYNOPSIS
        Returns a PKCE code verifier and its S256 challenge.

    .DESCRIPTION
        The canary never redeems the authorization code, so PKCE protects nothing here. It is sent
        anyway because a public-client registration is entitled to require it, and a canary that
        breaks the day someone ticks that box in the tenant would be reporting on the tenant's
        configuration rather than on Microsoft's sign-in page.

        Base64url per RFC 7636: standard base64 with '+' and '/' swapped for '-' and '_', and the
        padding removed.

    .OUTPUTS
        PSCustomObject with the members Verifier and Challenge.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param()

    $RandomBytes = [byte[]]::new(32)
    $RandomNumberGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $RandomNumberGenerator.GetBytes($RandomBytes)
    }
    finally {
        $RandomNumberGenerator.Dispose()
    }

    $Verifier = [Convert]::ToBase64String($RandomBytes).Replace("+", "-").Replace("/", "_").TrimEnd("=")

    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $ChallengeBytes = $Sha256.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($Verifier))
    }
    finally {
        $Sha256.Dispose()
    }

    $Challenge = [Convert]::ToBase64String($ChallengeBytes).Replace("+", "-").Replace("/", "_").TrimEnd("=")

    return [pscustomobject]@{
        Verifier  = $Verifier
        Challenge = $Challenge
    }
}

function New-CanaryAuthorizeUri {
    <#
    .SYNOPSIS
        Builds the Entra ID authorization request the stand-in redirects the browser to.

    .DESCRIPTION
        Every value is escaped with [System.Uri]::EscapeDataString rather than assembled by string
        concatenation, because the login hint is an account name and the redirect URI carries a
        port and a path.

        'prompt=login' is what makes the canary deterministic. Without it, a WebView2 profile that
        still holds a session cookie would be waved straight through and the sign-in screens - the
        only thing under test - would never be rendered. The canary would then pass by not testing
        anything, which is worse than failing.

        The login hint is sent so that Entra can serve the account's own sign-in experience. It does
        not skip the username screen: the automation still fills it in, which is what the canary is
        there to watch.

    .PARAMETER TenantId
        The directory (tenant) ID hosting the canary account and app registration.

    .PARAMETER ClientId
        The application (client) ID of the canary app registration.

    .PARAMETER RedirectUri
        The loopback URI Entra hands the browser back to. Must be registered on the application.

    .PARAMETER CodeChallenge
        The S256 PKCE challenge from New-CanaryPkcePair.

    .PARAMETER State
        The opaque state value echoed back on the redirect, which the listener checks.

    .PARAMETER LoginHint
        The canary account's user principal name.

    .OUTPUTS
        System.String. The absolute authorization request URI.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RedirectUri,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CodeChallenge,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$State,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$LoginHint
    )

    $QueryParameter = [ordered]@{
        client_id             = $ClientId
        response_type         = "code"
        redirect_uri          = $RedirectUri
        response_mode         = "query"
        scope                 = "openid profile User.Read"
        state                 = $State
        code_challenge        = $CodeChallenge
        code_challenge_method = "S256"
        prompt                = "login"
    }

    if (-not [string]::IsNullOrWhiteSpace($LoginHint)) {
        $QueryParameter["login_hint"] = $LoginHint
    }

    $QueryString = ($QueryParameter.GetEnumerator() | ForEach-Object {
            "{0}={1}" -f [System.Uri]::EscapeDataString($_.Key), [System.Uri]::EscapeDataString($_.Value)
        }) -join "&"

    return "https://login.microsoftonline.com/{0}/oauth2/v2.0/authorize?{1}" -f [System.Uri]::EscapeDataString($TenantId), $QueryString
}

function New-CanarySetCookieHeader {
    <#
    .SYNOPSIS
        Builds the Set-Cookie header that stands in for Omada's session cookie.

    .DESCRIPTION
        Get-WebView2Cookie looks for a cookie named 'oisauthtoken' whose domain ends with the host of
        the session's BaseUrl, and closes the sign-in window once it finds one. The cookie is written
        host-only - no Domain attribute - because a Domain of 'localhost' is rejected by parts of the
        cookie stack, and host-only still satisfies that suffix match.

        Not marked Secure: the stand-in serves plain HTTP on the loopback interface, and a Secure
        cookie would be dropped, leaving the sign-in window waiting forever for a cookie the browser
        had thrown away.

    .PARAMETER Name
        The cookie name.

    .PARAMETER Value
        The cookie value.

    .PARAMETER Path
        The cookie path.

    .OUTPUTS
        System.String. The Set-Cookie header value.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Value,

        [string]$Path = "/"
    )

    return "{0}={1}; Path={2}; HttpOnly; SameSite=Lax" -f $Name, $Value, $Path
}

function Start-CanaryRelyingParty {
    <#
    .SYNOPSIS
        Starts the loopback stand-in and returns the state the canary asserts against.

    .DESCRIPTION
        Serves three routes:

          /canary   - the registered redirect URI. Records the hit, sets oisauthtoken, returns 200.
          /api/*    - the resource the module requests once it holds the cookie. Returns JSON.
          anything  - 302 to the authorization request.

        The catch-all redirect is deliberate. Test-EnvironmentSuspended probes the BaseUrl with its
        own HttpClient before the browser ever opens, and that client follows redirects, so it will
        fetch the Entra sign-in page and find no suspension notice. That is harmless, and it is why
        the redirect has to be stateless: a listener that redirected only once would already have
        spent its redirect by the time the browser asked.

        The returned object is a synchronized hashtable so the listener thread and the test thread
        can both touch it. The test reads RedirectHitCount and CallbackError after the sign-in;
        ListenerError carries anything the loop itself threw.

    .PARAMETER TenantId
        The directory (tenant) ID hosting the canary account and app registration.

    .PARAMETER ClientId
        The application (client) ID of the canary app registration.

    .PARAMETER LoginHint
        The canary account's user principal name.

    .PARAMETER Port
        The loopback port to listen on. Must be covered by a registered redirect URI; Entra ignores
        the port when matching a localhost redirect URI on a public client, so any port that a
        registration already covers with the same path will do.

    .OUTPUTS
        System.Collections.Hashtable, synchronized.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$LoginHint,

        [ValidateRange(1024, 65535)]
        [int]$Port = 8400
    )

    $Prefix = "http://localhost:{0}/" -f $Port
    $RedirectUri = "http://localhost:{0}/canary" -f $Port
    $Pkce = New-CanaryPkcePair
    $StateValue = [guid]::NewGuid().ToString("N")

    $AuthorizeUri = New-CanaryAuthorizeUri -TenantId $TenantId -ClientId $ClientId -RedirectUri $RedirectUri -CodeChallenge $Pkce.Challenge -State $StateValue -LoginHint $LoginHint

    $CookieName = "oisauthtoken"
    $CookieValue = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("canary-cookie-value"))

    $Listener = [System.Net.HttpListener]::new()
    $Listener.Prefixes.Add($Prefix)
    $Listener.Start()

    # The authorization URI and the Set-Cookie header are built here rather than inside the loop
    # because a runspace does not inherit this session's functions: anything the loop needs from the
    # helpers above has to be computed on this side and carried across in the state.
    $RelyingParty = [hashtable]::Synchronized(@{
            Listener         = $Listener
            BaseUrl          = "http://localhost:{0}" -f $Port
            ResourceUrl      = "http://localhost:{0}/api/ping" -f $Port
            RedirectUri      = $RedirectUri
            RedirectPath     = "/canary"
            AuthorizeUri     = $AuthorizeUri
            ExpectedState    = $StateValue
            CookieName       = $CookieName
            CookieValue      = $CookieValue
            SetCookieHeader  = (New-CanarySetCookieHeader -Name $CookieName -Value $CookieValue)
            RedirectHitCount = 0
            CallbackError    = $null
            ListenerError    = $null
        })

    # Only .NET types and the state hashtable cross into the runspace - the helper functions above
    # stay on this side, because a runspace created here does not inherit this session's functions.
    $ListenerLoop = {
        param($RelyingParty)

        $Listener = $RelyingParty.Listener
        while ($Listener.IsListening) {
            $Context = $null
            try {
                $Context = $Listener.GetContext()
            }
            catch {
                # Stop-CanaryRelyingParty closes the listener, which is what unblocks GetContext.
                # Only an exception while still listening is worth recording.
                if ($Listener.IsListening) {
                    $RelyingParty.ListenerError = $_.Exception.Message
                }

                break
            }

            try {
                $Path = $Context.Request.Url.AbsolutePath
                $Body = ""
                $ContentType = "text/html; charset=utf-8"

                if ($Path -eq $RelyingParty.RedirectPath) {
                    $RelyingParty.RedirectHitCount = $RelyingParty.RedirectHitCount + 1

                    $ReturnedError = $Context.Request.QueryString["error"]
                    $ReturnedState = $Context.Request.QueryString["state"]
                    if (-not [string]::IsNullOrWhiteSpace($ReturnedError)) {
                        # The description can name the account and the tenant, so only the code is
                        # kept: this value is reported by a failing canary into a public issue.
                        $RelyingParty.CallbackError = $ReturnedError
                    }
                    elseif ($ReturnedState -ne $RelyingParty.ExpectedState) {
                        $RelyingParty.CallbackError = "state_mismatch"
                    }

                    $Context.Response.Headers.Add("Set-Cookie", $RelyingParty.SetCookieHeader)
                    $Context.Response.StatusCode = 200
                    # No element here may carry a class naming an error severity - see the header of
                    # this file for why.
                    $Body = "<html><head><title>OmadaWeb.PS canary</title></head><body><p>Canary sign-in complete.</p></body></html>"
                }
                elseif ($Path -like "/api/*") {
                    $Context.Response.StatusCode = 200
                    $ContentType = "application/json; charset=utf-8"
                    $Body = '{"canary":"ok"}'
                }
                else {
                    $Context.Response.StatusCode = 302
                    $Context.Response.Headers.Add("Location", $RelyingParty.AuthorizeUri)
                    $Body = "<html><head><title>OmadaWeb.PS canary</title></head><body><p>Redirecting.</p></body></html>"
                }

                $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
                $Context.Response.ContentType = $ContentType
                $Context.Response.ContentLength64 = $Bytes.Length
                $Context.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
                $Context.Response.Close()
            }
            catch {
                # One aborted or timed-out client must never take the listener down: the browser
                # abandons requests routinely while it navigates.
                try {
                    if ($null -ne $Context) {
                        $Context.Response.Abort()
                    }
                }
                catch {
                    # Nothing left to do for a response that cannot even be aborted.
                    $null = $_
                }
            }
        }
    }

    $Runspace = [runspacefactory]::CreateRunspace()
    $Runspace.ApartmentState = "MTA"
    $Runspace.ThreadOptions = "ReuseThread"
    $Runspace.Open()

    $PowerShellInstance = [powershell]::Create()
    $PowerShellInstance.Runspace = $Runspace
    $null = $PowerShellInstance.AddScript($ListenerLoop).AddArgument($RelyingParty)

    $RelyingParty["Runspace"] = $Runspace
    $RelyingParty["PowerShellInstance"] = $PowerShellInstance
    $RelyingParty["AsyncResult"] = $PowerShellInstance.BeginInvoke()

    return $RelyingParty
}

function Get-CanaryRelyingPartyError {
    <#
    .SYNOPSIS
        Everything that has gone wrong in the listener so far, readable while it is still running.

    .DESCRIPTION
        Two sources, because neither is complete on its own. The loop records what its own catch
        block saw into ListenerError; anything that killed the loop before or outside that catch
        lands in the runspace's error stream instead, and is only re-raised by EndInvoke - which
        cannot be called until the listener is being torn down, and therefore not before the
        assertions run.

        Reading the error stream directly is what closes that gap. Without it a listener that died on
        its first statement would serve nothing at all while the canary reported it as healthy, and
        the sign-in failure would be blamed on Microsoft.

    .PARAMETER RelyingParty
        The object returned by Start-CanaryRelyingParty.

    .OUTPUTS
        System.String[]. Empty when nothing has gone wrong.
    #>
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param(
        [AllowNull()]
        $RelyingParty
    )

    if ($null -eq $RelyingParty) {
        return @()
    }

    $Reported = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrWhiteSpace($RelyingParty.ListenerError)) {
        $Reported.Add([string]$RelyingParty.ListenerError)
    }

    # Indexed, never enumerated. Streams.Error is a PSDataCollection, and its enumerator is a
    # blocking one: while the invocation is still open it waits for the next item rather than ending,
    # so "@($collection)" on a running listener never returns. Reading Count and indexing is the
    # non-blocking form, and unlike ReadAll it leaves the records in place for EndInvoke to re-raise.
    if ($null -ne $RelyingParty.PowerShellInstance) {
        $ErrorStream = $RelyingParty.PowerShellInstance.Streams.Error
        for ($Index = 0; $Index -lt $ErrorStream.Count; $Index++) {
            $Reported.Add([string]$ErrorStream[$Index])
        }
    }

    return $Reported.ToArray()
}

function Stop-CanaryRelyingParty {
    <#
    .SYNOPSIS
        Stops the loopback stand-in and disposes its runspace.

    .DESCRIPTION
        Closing the listener is what unblocks the GetContext call the loop is parked on, so it has to
        happen before the runspace is torn down. Every step is best-effort: this runs from a Pester
        AfterAll, where throwing would replace a real test failure with a cleanup failure.

    .PARAMETER RelyingParty
        The object returned by Start-CanaryRelyingParty.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $RelyingParty
    )

    if ($null -eq $RelyingParty) {
        return
    }

    try {
        if ($null -ne $RelyingParty.Listener -and $RelyingParty.Listener.IsListening) {
            $RelyingParty.Listener.Stop()
        }
    }
    catch {
        "Stop-CanaryRelyingParty - could not stop the listener: {0}" -f $_.Exception.Message | Write-Verbose
    }

    try {
        if ($null -ne $RelyingParty.Listener) {
            $RelyingParty.Listener.Close()
        }
    }
    catch {
        "Stop-CanaryRelyingParty - could not close the listener: {0}" -f $_.Exception.Message | Write-Verbose
    }

    # EndInvoke before Dispose. Disposing a PowerShell instance without ending its invocation leaves
    # the async operation unobserved and can strand the thread, and EndInvoke is what re-raises a
    # terminating error from the listener thread - one the loop's own catch never saw because it
    # never got as far as the loop.
    #
    # Note that this runs from an AfterAll, which is after the assertions. Anything recorded here is
    # for the log, not for a test; Get-CanaryRelyingPartyError is what the assertions read.
    try {
        if ($null -ne $RelyingParty.PowerShellInstance -and $null -ne $RelyingParty.AsyncResult) {
            if ($RelyingParty.AsyncResult.AsyncWaitHandle.WaitOne([System.TimeSpan]::FromSeconds(10))) {
                $null = $RelyingParty.PowerShellInstance.EndInvoke($RelyingParty.AsyncResult)
            }
            else {
                $RelyingParty.ListenerError = "The listener thread did not finish within 10 seconds of the listener being closed."
            }
        }
    }
    catch {
        $RelyingParty.ListenerError = $_.Exception.Message
        "Stop-CanaryRelyingParty - the listener thread ended with an error: {0}" -f $_.Exception.Message | Write-Verbose
    }

    try {
        if ($null -ne $RelyingParty.PowerShellInstance) {
            $RelyingParty.PowerShellInstance.Dispose()
        }
    }
    catch {
        "Stop-CanaryRelyingParty - could not dispose the PowerShell instance: {0}" -f $_.Exception.Message | Write-Verbose
    }

    try {
        if ($null -ne $RelyingParty.Runspace) {
            $RelyingParty.Runspace.Dispose()
        }
    }
    catch {
        "Stop-CanaryRelyingParty - could not dispose the runspace: {0}" -f $_.Exception.Message | Write-Verbose
    }
}
