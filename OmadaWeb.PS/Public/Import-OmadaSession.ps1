function Import-OmadaSession {
    <#
    .SYNOPSIS
        Seeds this runspace with a session captured by Export-OmadaSession.

    .DESCRIPTION
        Takes the state object Export-OmadaSession produced in the runspace that signed in, and
        installs it here. The next Invoke-OmadaRestMethod or Invoke-OmadaWebRequest made against
        the same environment, with the same authentication type and the same account or session
        key, reuses that session instead of authenticating.

        Nothing is read from or written to disk, and no request is made: this only puts the session
        in place.

        A seeded session may not sign in. Everything that could open a browser window is refused for
        it, whether or not the call asked for -NoInteractiveAuthentication, because a worker
        runspace usually has no desktop to put a window on and nobody watching it. When the session
        turns out to be dead - refused here because its cookie has already expired, or refused later
        because the server answers HTTP 401 - the caller gets a terminating error it can catch: an
        AuthenticationException whose FullyQualifiedErrorId starts with OmadaSessionExpired. The
        third example below shows the shape. Use -AllowInteractiveAuthentication only where a
        sign-in window would actually be welcome.

        The state is protected with DPAPI, so it can only be imported by the user who exported it,
        on the machine it was exported from. A state that cannot be read - from another user, from
        another machine, or damaged in transit - is refused as one error rather than silently
        ignored.

    .PARAMETER State
        The object returned by Export-OmadaSession. Accepted from the pipeline.

    .PARAMETER AllowInteractiveAuthentication
        Allow this session to sign in interactively after all, if it turns out to be expired.
        Without it - the default - nothing under the seeded session can open a browser window, and
        an unusable session raises a terminating error instead.

    .PARAMETER PassThru
        Return a summary of the session that was seeded. Without it the command returns nothing.

    .INPUTS
        PSCustomObject with the type name OmadaWeb.PS.SessionState, as produced by
        Export-OmadaSession.

    .OUTPUTS
        None by default. With -PassThru, a PSCustomObject reporting the BaseUrl, SessionId,
        ExpiresOn and whether interactive authentication is allowed for the seeded session.

    .EXAMPLE
        Import-OmadaSession -State $State

        Seeds this runspace with the session captured elsewhere. The next request against that
        environment reuses it, and cannot open a sign-in window.

    .EXAMPLE
        $State | Import-OmadaSession -PassThru

        Seeds the session and reports what was seeded, which is useful in a worker whose output is
        the only place its state can be observed from.

    .EXAMPLE
        try {
            Import-OmadaSession -State $State
        }
        catch [System.Security.Authentication.AuthenticationException] {
            "The exported session has already expired; asking the caller for a fresh one." | Write-Warning
        }

        Distinguishes a session that is still good from one that is already dead, without making a
        request and without any chance of a prompt.

    .LINK
        Export-OmadaSession

    .LINK
        Invoke-OmadaRestMethod

    .LINK
        https://github.com/Fortigi/OmadaWeb.PS#reusing-a-session-in-another-runspace
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingVerbs', '', Justification = 'Import-OmadaSession only adds an in-memory session to the current runspace; there is nothing to confirm and nothing to undo.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # Not [PSTypeName("OmadaWeb.PS.SessionState")]: that attribute matches the type name
        # exactly, and a state that has crossed a process boundary - Start-Job, a remote session -
        # arrives wearing "Deserialized.OmadaWeb.PS.SessionState" instead. Both are the same object
        # as far as this command is concerned, since everything it reads is a plain property.
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [ValidateScript({
                $TypeNames = @($_.PSObject.TypeNames)
                if ($TypeNames -notcontains "OmadaWeb.PS.SessionState" -and $TypeNames -notcontains "Deserialized.OmadaWeb.PS.SessionState") {
                    throw "-State expects the object returned by Export-OmadaSession."
                }

                $true
            })]
        $State,

        [Parameter()]
        [switch]$AllowInteractiveAuthentication,

        [Parameter()]
        [switch]$PassThru
    )

    process {
        "{0} - Importing session {1}" -f $MyInvocation.MyCommand, $State.SessionId | Write-Verbose

        # StateVersion describes the shape of ProtectedState. An older module meeting a newer state
        # has to say so rather than half-read it, because what it would be half-reading is the piece
        # that decides which session the worker acts as.
        if ($State.StateVersion -ne 1) {
            "{0} - This session state was produced by a different version of OmadaWeb.PS (state version {1}, expected 1). Export it again with the version that is importing it." -f $MyInvocation.MyCommand, $State.StateVersion | Write-Error -ErrorAction "Stop"
        }

        $Payload = Unprotect-OmadaSessionPayload -ProtectedPayload $State.ProtectedState
        if ($null -eq $Payload -or $null -eq $Payload.SessionKey -or $null -eq $Payload.AuthCookie) {
            # One message for every way this can fail, because a caller cannot act on the difference:
            # the protection is bound to a user and a machine, so anything unreadable means the state
            # did not come from here, and the answer is always to export it again where it is used.
            $Exception = [System.Security.Cryptography.CryptographicException]::new(
                "The exported Omada session could not be read. It is protected for the user and machine that exported it, so it cannot be imported by another user, on another computer, or after being altered in transit."
            )
            throw [System.Management.Automation.ErrorRecord]::new(
                $Exception,
                "OmadaSessionStateUnreadable",
                [System.Management.Automation.ErrorCategory]::SecurityError,
                $State.SessionId
            )
        }

        # Checked before the session is seeded, so a runspace handed a dead session is left with no
        # session at all rather than one that looks usable until the first request comes back 401.
        #
        # Read through the same helper the cookie's own expiry goes through, rather than cast: a
        # cast raises a FormatException on anything it cannot read, and this command's contract is
        # to raise OmadaSessionExpired. An expiry that cannot be read is treated as one that was
        # never declared, exactly as a session cookie's is - the session is then left to the server,
        # which answers 401 and produces the same error by the other route.
        $ExpiresOn = ConvertTo-OmadaExpiryMoment -Value $State.ExpiresOn
        if ($null -ne $ExpiresOn -and $ExpiresOn -le [datetime]::UtcNow) {
            $Message = "The exported Omada session for '{0}' expired at {1:u} and was not imported. Export a fresh session from the runspace that signed in." -f $State.BaseUrl, $ExpiresOn
            throw (New-OmadaSessionExpiredError -Message $Message -BaseUrl $State.BaseUrl)
        }

        $BaseUrl = [string]$Payload.BaseUrl
        $AuthorityHost = $null
        if (-not [string]::IsNullOrWhiteSpace($BaseUrl)) {
            $AuthorityHost = ([System.Uri]::new($BaseUrl)).Host
        }

        $SessionContext = Get-OmadaSessionContext -Key ([string]$Payload.SessionKey) -AuthorityHost $AuthorityHost
        $SessionContext.BaseUrl = $BaseUrl
        $SessionContext.AuthCookie = $Payload.AuthCookie
        $SessionContext.UserName = $Payload.UserName
        # Carried across so the worker's first request behaves the way the original session did
        # rather than falling back to the defaults: which engine this session runs on, and whether
        # it was an InPrivate one - both of which reset the cookie when they change underneath it.
        $SessionContext.WebView2Used = [bool]$Payload.WebView2Used
        $SessionContext.LastSessionType = $Payload.LastSessionType
        $SessionContext.Seeded = $true
        $SessionContext.NoInteractiveAuthentication = -not $AllowInteractiveAuthentication

        "{0} - Seeded session {1} for {2}; interactive authentication is {3}" -f $MyInvocation.MyCommand, $State.SessionId, $BaseUrl, $(if ($AllowInteractiveAuthentication) { "allowed" } else { "refused" }) | Write-Verbose

        if ($PassThru) {
            return [PSCustomObject]@{
                PSTypeName                     = "OmadaWeb.PS.SeededSession"
                BaseUrl                        = $BaseUrl
                SessionId                      = $State.SessionId
                ExpiresOn                      = $State.ExpiresOn
                AllowInteractiveAuthentication = [bool]$AllowInteractiveAuthentication
            }
        }
    }
}
