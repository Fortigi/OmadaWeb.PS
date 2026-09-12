function Get-OmadaSessionContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [AllowNull()]
        [string]$AuthorityHost
    )

    if ($Script:OmadaSessions.ContainsKey($Key)) {
        return $Script:OmadaSessions[$Key]
    }

    "{0} - Creating new session context for key: {1}" -f $MyInvocation.MyCommand, $Key | Write-Verbose

    # Every reusable piece of authentication state used to live in single, unkeyed $Script: variables
    # shared by the whole process. This context replaces those with one instance per (base URL, auth
    # type, identity) key so concurrent sessions in the same Runspace no longer clobber each other.
    $KeyHash = Get-OmadaShortHash -Value $Key

    $AuthCookie = $null
    if ($null -ne $Script:OmadaWebAuthCookie -and -not [string]::IsNullOrEmpty($Script:OmadaWebAuthCookie.domain) -and -not [string]::IsNullOrWhiteSpace($AuthorityHost)) {
        # Preserve the legacy `Import-Module OmadaWeb.PS -ArgumentList @{ Parameters = @{ OmadaWebAuthCookie = ... } }`
        # seed by handing it only to the session whose host it actually matches (mirroring the old domain-match
        # check in Invoke-BrowserAuthentication.ps1), not just whichever session happens to be created first -
        # otherwise a seed for tenant A could be silently discarded if tenant B's session is created first.
        # AuthorityHost is passed in by the caller (from System.Uri.Host) rather than re-parsed out of $Key here,
        # since naively splitting $Key on ":" breaks for IPv6 authorities (e.g. "[::1]:8443").
        if ($AuthorityHost.ToLowerInvariant() -eq $Script:OmadaWebAuthCookie.domain.ToLowerInvariant()) {
            $AuthCookie = $Script:OmadaWebAuthCookie
            $Script:OmadaWebAuthCookie = $null
        }
    }

    $SessionContext = [pscustomobject]@{
        Key                 = $Key
        BaseUrl             = $null
        AuthCookie          = $AuthCookie
        Credential          = $null
        # The account this session signs in as, from -UserName or from the user name of -Credential.
        # It is what the sign-in request is told to ask for, so it has to outlive the call that
        # supplied it: the WebView2 window runs in a blocking dialog that cannot see the call stack.
        UserName            = $null
        SelectAccount       = $false
        # Whether this sign-in has already been given its one window with an account picker on it
        # after being refused for the wrong account. Reset at the start of every sign-in, so the
        # allowance is per call and not per PowerShell session.
        AccountRecoveryAttempted = $false
        PreferredMfaMethod  = $null
        LastSessionType     = $null
        WebView2Used        = $false
        ForceAuthentication = $false
        # Set by Import-OmadaSession on a session seeded from another runspace, and read alongside
        # the -NoInteractiveAuthentication switch wherever that switch is honoured. A seeded session
        # belongs to a worker that has no desktop to put a sign-in window on and no user watching it,
        # so the refusal has to be a property of the session rather than something every call site
        # has to remember to ask for. Import-OmadaSession -AllowInteractiveAuthentication clears it.
        NoInteractiveAuthentication = $false
        # Whether this context was seeded by Import-OmadaSession rather than signed in here. Used
        # only to say so in the refusal message, which is the difference between a caller thinking
        # their session expired and knowing the state they imported was already dead.
        Seeded              = $false
        BrowserDataCleared  = $false
        CookieCacheFilePath = $null
        LoginRetryCount     = 0
        LoginCount          = 0
        WebView2ProfilePath = (Join-Path $Script:WebView2UserProfileBasePath ("OmadaWebView2Profile_{0}" -f $KeyHash.Substring(0, 16)))
        WebViewEnv          = $null
        # Which way single sign-on with the Windows account was configured when WebViewEnv was
        # created. A CoreWebView2Environment cannot be reconfigured after the fact, so a later call
        # that asks for a different answer has to be given a new one - see Start-WebView2Login.
        WebViewEnvSingleSignOn = $null
    }

    $Script:OmadaSessions[$Key] = $SessionContext
    return $SessionContext
}
