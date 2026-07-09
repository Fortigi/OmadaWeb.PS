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
        LastSessionType     = $null
        WebView2Used        = $false
        ForceAuthentication = $false
        BrowserDataCleared  = $false
        CookieCacheFilePath = $null
        LoginRetryCount     = 0
        LoginCount          = 0
        WebView2ProfilePath = (Join-Path $Script:WebView2UserProfileBasePath ("OmadaWebView2Profile_{0}" -f $KeyHash.Substring(0, 16)))
        WebViewEnv          = $null
    }

    $Script:OmadaSessions[$Key] = $SessionContext
    return $SessionContext
}
