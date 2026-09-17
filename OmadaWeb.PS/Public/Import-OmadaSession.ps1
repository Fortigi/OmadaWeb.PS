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

        The state is protected with DPAPI for the Windows user account that exported it: any process
        already running as that account can decrypt it, whether it runs on this machine or on another
        one where the account's DPAPI keys roam through a roaming profile or credential roaming. It
        does not stop another process running as that same account, so an exported state is a secret
        and should be handled like one. A state that cannot be read at all - because it belongs to a
        different user, or was damaged or altered in transit - is refused as one error rather than
        silently ignored.

        The protected contents are also the authority on which environment the session belongs to,
        and on when it expires. The BaseUrl and ExpiresOn properties beside them are a convenience for
        the caller and sit outside the protection, so if either disagrees with what is inside - by
        accident or by an edit - the state is not trusted on that point: BaseUrl is refused outright,
        and expiry is decided from the protected copy rather than the visible one, so editing the
        visible ExpiresOn cannot make an already-dead session look current.

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

                # The type name alone is not enough. Nothing stops a caller building an object that
                # carries it, and every property read below would then fail as "property ... cannot
                # be found" under the StrictMode this module runs with - which says nothing about
                # what was actually wrong with the argument. Checked here so the complaint names the
                # parameter and the missing property instead.
                $Missing = @(foreach ($Required in @("SessionId", "StateVersion", "ProtectedState", "BaseUrl")) {
                        if ($null -eq $_.PSObject.Properties[$Required]) { $Required }
                    })
                if ($Missing.Count -gt 0) {
                    throw ("-State is missing the {0} property. Pass the object returned by Export-OmadaSession unchanged." -f ($Missing -join ", "))
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
        # Indexer reads with Contains checks, not dot notation: a crafted payload can decrypt to a
        # hashtable that simply omits a key, and under this module's StrictMode dot notation throws
        # PropertyNotFoundStrict on a missing key instead of answering $null - which would escape
        # this guard as an unhandled error rather than the OmadaSessionStateUnreadable it means to be.
        if ($null -eq $Payload -or $Payload -isnot [System.Collections.IDictionary] -or
            -not $Payload.Contains('SessionKey') -or $null -eq $Payload['SessionKey'] -or
            -not $Payload.Contains('AuthCookie') -or $null -eq $Payload['AuthCookie']) {
            # One message for every way this can fail, because a caller cannot act on the difference:
            # the protection is bound to the Windows user account that exported it, so anything
            # unreadable means the state did not come from that account, and the answer is always to
            # export it again where it is used.
            $Exception = [System.Security.Cryptography.CryptographicException]::new(
                "The exported Omada session could not be read. It is protected for the Windows user account that exported it, so it cannot be imported by another user, or after being altered in transit."
            )
            throw [System.Management.Automation.ErrorRecord]::new(
                $Exception,
                "OmadaSessionStateUnreadable",
                [System.Management.Automation.ErrorCategory]::SecurityError,
                $State.SessionId
            )
        }

        # Read once, by indexer, and used everywhere below instead of $Payload.SessionKey /
        # $Payload.AuthCookie: the guard above only proves $Payload is an IDictionary, not that it is
        # a [hashtable] specifically, and dot notation on some other IDictionary implementation is
        # not guaranteed the same StrictMode-safe-when-present behaviour a hashtable gives it.
        $PayloadSessionKey = $Payload['SessionKey']
        $PayloadAuthCookie = $Payload['AuthCookie']

        # The protected payload is the authority on which environment this session belongs to, and
        # everything below reads it from there. The BaseUrl property beside it is a convenience for
        # the caller, outside the protection, so the two can disagree - by an accident on the way
        # here, or by an edit. Either way the state is not the one that was exported, and importing
        # it would seed one environment while every message about it named another.
        # Past the guard above, SessionKey and AuthCookie are known to be there; BaseUrl is not
        # guaranteed the same way, so it gets the same Contains-guarded read.
        $BaseUrl = [string]$(if ($Payload.Contains('BaseUrl')) { $Payload['BaseUrl'] } else { $null })
        $VisibleBaseUrl = [string]$State.BaseUrl

        # Both have to be there and agree. An empty visible BaseUrl used to skip the comparison,
        # which weakened the check for no reason: an absent value is no more the exported one than a
        # different value is.
        $Mismatch = $null
        if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
            $Mismatch = "the session inside it names no environment at all"
        }
        elseif ([string]::IsNullOrWhiteSpace($VisibleBaseUrl)) {
            $Mismatch = "it names no environment, where the session inside it is for '{0}'" -f $BaseUrl
        }
        elseif ($VisibleBaseUrl -ne $BaseUrl) {
            $Mismatch = "it names '{0}', where the session inside it is for '{1}'" -f $VisibleBaseUrl, $BaseUrl
        }

        # TryCreate rather than the constructor: a payload that decrypts but carries something that
        # is not an absolute URL would otherwise raise UriFormatException from here and escape the
        # contract this block exists to keep. Every way the environment can be wrong ends in the
        # same error.
        $ParsedBaseUrl = $null
        if ($null -eq $Mismatch -and -not [System.Uri]::TryCreate($BaseUrl, [System.UriKind]::Absolute, [ref]$ParsedBaseUrl)) {
            $Mismatch = "the environment it names, '{0}', is not a valid URL" -f $BaseUrl
        }

        if ($null -eq $Mismatch -and [string]::IsNullOrWhiteSpace($ParsedBaseUrl.Host)) {
            $Mismatch = "the environment it names, '{0}', has no host" -f $BaseUrl
        }

        if ($null -ne $Mismatch) {
            $Exception = [System.InvalidOperationException]::new(
                ("The exported Omada session does not match its own protected contents and was not imported: {0}. Export it again in the runspace that signed in." -f $Mismatch)
            )
            throw [System.Management.Automation.ErrorRecord]::new(
                $Exception,
                "OmadaSessionStateMismatch",
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $State.SessionId
            )
        }

        $AuthorityHost = $ParsedBaseUrl.Host

        # Checked before the session is seeded, so a runspace handed a dead session is left with no
        # session at all rather than one that looks usable until the first request comes back 401.
        #
        # Read from the protected payload, not from the visible State.ExpiresOn: that property sits
        # outside the protection next to BaseUrl, so anything with the object could push it into the
        # future and make an already-dead session look current. The payload is what Export-OmadaSession
        # actually measured. A payload produced before it started carrying its own expiry - an older
        # or pre-release build - falls back to the AuthCookie's own expiry, also read from inside the
        # payload; only when neither is present is the session treated as not declaring an expiry at
        # all, exactly as a session cookie without one is today. ConvertTo-OmadaExpiryMoment is used
        # rather than a cast for the same reason it is used on the cookie's own expiry: a cast raises
        # a FormatException on anything it cannot read, and this command's contract is to raise
        # OmadaSessionExpired. An expiry that cannot be read is treated as one that was never
        # declared - the session is then left to the server, which answers 401 and produces the same
        # error by the other route.
        # $Payload always comes back as a [hashtable]: Protect-OmadaSessionPayload serializes it with
        # PSSerializer, and Unprotect-OmadaSessionPayload deserializes with the same serializer, so
        # this is the only shape that ever reaches here - unlike SessionKey or AuthCookie, ExpiresOn
        # is not present on every payload (a state exported before this change carries none), and
        # under this module's StrictMode a hashtable's dot notation throws PropertyNotFoundStrict on
        # a key that is not there, rather than answering $null the way it does outside StrictMode.
        $RawPayloadExpiry = if ($Payload.Contains('ExpiresOn')) { $Payload['ExpiresOn'] } else { $null }
        $ExpiresOn = ConvertTo-OmadaExpiryMoment -Value $RawPayloadExpiry
        if ($null -eq $ExpiresOn) {
            $ExpiresOn = Get-OmadaCookieExpiry -AuthCookie $PayloadAuthCookie
        }

        if ($null -ne $ExpiresOn -and $ExpiresOn -le [datetime]::UtcNow) {
            $Message = "The exported Omada session for '{0}' expired at {1:u} and was not imported. Export a fresh session from the runspace that signed in." -f $BaseUrl, $ExpiresOn
            throw (New-OmadaSessionExpiredError -Message $Message -BaseUrl $BaseUrl)
        }

        $SessionContext = Get-OmadaSessionContext -Key ([string]$PayloadSessionKey) -AuthorityHost $AuthorityHost
        $SessionContext.BaseUrl = $BaseUrl
        $SessionContext.AuthCookie = $PayloadAuthCookie
        # UserName, WebView2Used and LastSessionType are optional on the payload - a state exported
        # by an older build, or a crafted one, can omit any of them - so they get the same
        # Contains-guarded read as BaseUrl above, rather than dot notation.
        $SessionContext.UserName = if ($Payload.Contains('UserName')) { $Payload['UserName'] } else { $null }
        # Carried across so the worker's first request behaves the way the original session did
        # rather than falling back to the defaults: which engine this session runs on, and whether
        # it was an InPrivate one - both of which reset the cookie when they change underneath it.
        $SessionContext.WebView2Used = [bool]$(if ($Payload.Contains('WebView2Used')) { $Payload['WebView2Used'] } else { $false })
        $SessionContext.LastSessionType = if ($Payload.Contains('LastSessionType')) { $Payload['LastSessionType'] } else { $null }
        $SessionContext.Seeded = $true
        $SessionContext.NoInteractiveAuthentication = -not $AllowInteractiveAuthentication

        "{0} - Seeded session {1} for {2}; interactive authentication is {3}" -f $MyInvocation.MyCommand, $State.SessionId, $BaseUrl, $(if ($AllowInteractiveAuthentication) { "allowed" } else { "refused" }) | Write-Verbose

        if ($PassThru) {
            return [PSCustomObject]@{
                PSTypeName                     = "OmadaWeb.PS.SeededSession"
                BaseUrl                        = $BaseUrl
                SessionId                      = $State.SessionId
                # The normalized moment actually evaluated - from the protected payload, with the
                # same fallback applied - not the raw State.ExpiresOn property: this is what the
                # import judged the session by, so a state whose visible expiry disagreed, or arrived
                # as a string, or was absent, reports the value that decided its fate.
                ExpiresOn                      = $ExpiresOn
                AllowInteractiveAuthentication = [bool]$AllowInteractiveAuthentication
            }
        }
    }
}
