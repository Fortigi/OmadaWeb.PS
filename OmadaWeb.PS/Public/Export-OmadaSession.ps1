function Export-OmadaSession {
    <#
    .SYNOPSIS
        Captures an authenticated Omada session so another runspace can reuse it.

    .DESCRIPTION
        Returns the session this PowerShell session already signed in with, as one opaque object
        that can be handed to a background runspace and replayed there with Import-OmadaSession.
        The worker then makes its requests against the same session, without signing in and without
        a browser window ever opening.

        This exists because authentication state is per module instance. A background runspace
        imports its own copy of OmadaWeb.PS, so it starts with no session at all and would try to
        sign in interactively even though the calling application authenticated seconds earlier.

        Nothing is written to disk. The session cookie is a live bearer token, so it never appears
        in the returned object: it is encrypted with DPAPI for the current user on the current
        machine and carried in the ProtectedState property as ciphertext. The object can therefore
        be passed through a job argument, a queue or a variable without leaking the token, and a
        copy that leaves this machine is inert. The same binding is the limit of what this supports:
        a session can be seeded into another runspace of the same user on the same machine, not into
        another user's session and not onto another computer.

        The command reads the session that is already there. It never creates one, and it never
        signs in: when there is no authenticated session for the arguments given, it says so and
        stops. The arguments are the same ones that identified the session when it was created -
        the Omada URL, the authentication type, and whichever of -UserName, -Credential or
        -SessionKey the original call used - because sessions are keyed by all three.

        Omada session cookies are short lived. Export the session close to where it is used rather
        than holding one for a long time, and expect Import-OmadaSession to refuse one whose cookie
        has already expired.

    .PARAMETER Uri
        The Omada URL the session was established against. Only the scheme, host and port are used,
        so the URL of any request made against that environment will do.

    .PARAMETER AuthenticationType
        The authentication type the session was established with. Defaults to WebView2, the same
        default Invoke-OmadaRestMethod and Invoke-OmadaWebRequest use.

    .PARAMETER UserName
        The account the session signs in as, when the original call named one with -UserName.

    .PARAMETER Credential
        The credential the original call used. Only its user name identifies the session; the
        password is not read and is never part of the exported state.

    .PARAMETER SessionKey
        The value the original call passed as -SessionKey, when it used one to keep several
        sessions to the same environment apart.

    .INPUTS
        None. This command does not accept pipeline input.

    .OUTPUTS
        PSCustomObject with the type name OmadaWeb.PS.SessionState. Its properties are BaseUrl,
        SessionId (a hash that identifies the session in logs without naming the account),
        CreatedOn, ExpiresOn (the cookie's own expiry, or $null when it does not declare one),
        StateVersion and ProtectedState.

    .EXAMPLE
        $State = Export-OmadaSession -Uri "https://example.omada.cloud"

        Captures the session of the default authentication type, ready to be handed to a worker.

    .EXAMPLE
        $State = Export-OmadaSession -Uri "https://example.omada.cloud" -UserName "someone@example.com"

        Captures the session belonging to one specific account, on an environment where more than
        one account is signed in. The account has to be named the same way the original request
        named it, because that is part of what identifies the session.

    .EXAMPLE
        $PowerShell = [PowerShell]::Create()
        $null = $PowerShell.AddScript({
                param($State, $Uri)
                Import-Module OmadaWeb.PS
                Import-OmadaSession -State $State
                Invoke-OmadaRestMethod -Uri $Uri
            }).AddArgument((Export-OmadaSession -Uri "https://example.omada.cloud")).AddArgument("https://example.omada.cloud/api/v2/identity")
        $PowerShell.Invoke()

        Runs a request on a background runspace against the session this session signed in with. The
        worker never signs in: no browser window can open, and nothing is written to disk.

    .LINK
        Import-OmadaSession

    .LINK
        Invoke-OmadaRestMethod

    .LINK
        https://github.com/Fortigi/OmadaWeb.PS#reusing-a-session-in-another-runspace
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [System.Uri]$Uri,

        [Parameter()]
        [ValidateSet("OAuth", "Integrated", "Basic", "Browser", "WebView2", "Windows", "None")]
        [string]$AuthenticationType = "WebView2",

        [Parameter()]
        [string]$UserName,

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter()]
        [string]$SessionKey
    )

    process {
        "{0} - Exporting session for {1}" -f $MyInvocation.MyCommand, $Uri.Authority | Write-Verbose

        # The same refusal Invoke-OmadaRequest makes, for the same reason: both name the account,
        # and Get-OmadaSessionKey reads only the first of them. Accepting both here would hand back
        # the session of whichever one happened to win, which is not something a caller can see.
        if (-not [string]::IsNullOrWhiteSpace($UserName) -and $null -ne $Credential -and -not [string]::IsNullOrWhiteSpace($Credential.UserName)) {
            "{0} - Cannot combine -UserName with -Credential: both name the account whose session to export. Supply the account either as -UserName or as the user name of -Credential." -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
        }

        $Key = Get-OmadaSessionKey -Uri $Uri -AuthenticationType $AuthenticationType -Credential $Credential -SessionKey $SessionKey -UserName $UserName

        # Read straight out of the table rather than through Get-OmadaSessionContext, which creates a
        # context when it does not find one. Creating an empty session here would turn "you are not
        # signed in" into an export that looks successful and fails in the worker instead.
        if (-not $Script:OmadaSessions.ContainsKey($Key)) {
            $Message = "There is no authenticated Omada session for '{0}' with -AuthenticationType {1}{2}. Make a request first, then export the session it establishes." -f $Uri.GetLeftPart([System.UriPartial]::Authority), $AuthenticationType, $(if ([string]::IsNullOrWhiteSpace($UserName) -and $null -eq $Credential -and [string]::IsNullOrWhiteSpace($SessionKey)) { "" } else { " and the account or session key given" })
            throw (New-OmadaSessionExpiredError -Message $Message -BaseUrl $Uri.GetLeftPart([System.UriPartial]::Authority))
        }

        $SessionContext = $Script:OmadaSessions[$Key]

        # A context exists for every session the module has touched, including ones that never
        # completed a sign-in, so the cookie - not the context - is what says there is a session.
        $HasCookie = $null -ne $SessionContext.AuthCookie -and
            $null -ne $SessionContext.AuthCookie.PSObject.Properties['Value'] -and
            -not [string]::IsNullOrWhiteSpace([string]$SessionContext.AuthCookie.Value)

        if (-not $HasCookie) {
            $Message = "The Omada session for '{0}' holds no authentication cookie, so there is nothing to export. Make a request first, then export the session it establishes." -f $SessionContext.BaseUrl
            throw (New-OmadaSessionExpiredError -Message $Message -BaseUrl $SessionContext.BaseUrl)
        }

        $ExpiresOn = Get-OmadaCookieExpiry -AuthCookie $SessionContext.AuthCookie
        if ($null -ne $ExpiresOn -and $ExpiresOn -le [datetime]::UtcNow) {
            # Refused here rather than left for the worker to discover. The two are the same failure,
            # but only this one can still be acted on by the code that owns the sign-in.
            $Message = "The Omada session for '{0}' expired at {1:u}, so it would be of no use to another runspace. Sign in again, then export the new session." -f $SessionContext.BaseUrl, $ExpiresOn
            throw (New-OmadaSessionExpiredError -Message $Message -BaseUrl $SessionContext.BaseUrl)
        }

        # Everything that identifies or authenticates the session goes into the protected half - the
        # session key included, because its last segment is the account name or the caller's own
        # -SessionKey value. The module already keeps that out of its logs by hashing it, and an
        # object a caller may hand around deserves the same treatment.
        $Payload = @{
            SessionKey      = $Key
            BaseUrl         = $SessionContext.BaseUrl
            AuthCookie      = $SessionContext.AuthCookie
            UserName        = $SessionContext.UserName
            WebView2Used    = $SessionContext.WebView2Used
            LastSessionType = $SessionContext.LastSessionType
        }

        $State = [PSCustomObject]@{
            PSTypeName     = "OmadaWeb.PS.SessionState"
            BaseUrl        = $SessionContext.BaseUrl
            # The same short hash the verbose log uses, so a state object and a log line can be
            # matched up without either of them naming the account.
            SessionId      = (Get-OmadaShortHash -Value $Key).Substring(0, 16)
            CreatedOn      = [datetime]::UtcNow
            ExpiresOn      = $ExpiresOn
            # The shape of ProtectedState, not the module's version. It is what Import-OmadaSession
            # has to understand, and it changes only when that shape does.
            StateVersion   = 1
            ProtectedState = (Protect-OmadaSessionPayload -Payload $Payload)
        }

        "{0} - Exported session {1} for {2}, expiring {3}" -f $MyInvocation.MyCommand, $State.SessionId, $State.BaseUrl, $(if ($null -eq $ExpiresOn) { "(not declared)" } else { "{0:u}" -f $ExpiresOn }) | Write-Verbose

        return $State
    }
}
