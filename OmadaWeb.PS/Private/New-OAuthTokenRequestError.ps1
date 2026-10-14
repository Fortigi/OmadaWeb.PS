function New-OAuthTokenRequestError {
    <#
    .SYNOPSIS
        Builds the terminating error for a failed OAuth2 client-credentials token request.

    .DESCRIPTION
        Invoke-OAuth2Authentication used to let a failed or empty token response through as an empty
        bearer value, so the caller's actual request went to Omada and came back as an unexplained 401
        instead of whatever the identity provider had actually said. This builds that explanation
        instead: the identity provider's own 'error'/'error_description'/'error_codes' from the
        response body when the caught exception carries one, falling back to the exception's own
        message, or to a supplied message for a response that came back successfully but without an
        access_token. The result always goes through Protect-LogMessage, because the response body can
        just as easily echo something secret-looking back - a bad client_secret, an over-verbose
        provider error - as it can carry the two-line explanation this exists to surface.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [string]$OAuthUri,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message
    )

    $IdpErrorText = $null

    if ($null -ne $ErrorRecord) {
        $Body = $null

        # PowerShell 7's Invoke-RestMethod surfaces a non-success response body on ErrorDetails.Message
        # without the response stream having to be reopened. Windows PowerShell 5.1 never populates
        # ErrorDetails for a WebException, so the body is read from the response stream instead - the
        # only place it still exists on that engine.
        if ($null -ne $ErrorRecord.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) {
            $Body = $ErrorRecord.ErrorDetails.Message
        }
        elseif ($ErrorRecord.Exception -is [System.Net.WebException] -and $null -ne $ErrorRecord.Exception.Response) {
            $StreamReader = $null
            try {
                $StreamReader = [System.IO.StreamReader]::new($ErrorRecord.Exception.Response.GetResponseStream())
                $Body = $StreamReader.ReadToEnd()
            }
            catch {
                $Body = $null
            }
            finally {
                if ($null -ne $StreamReader) {
                    $StreamReader.Dispose()
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($Body)) {
            $ParsedBody = $null
            try {
                $ParsedBody = $Body | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                $ParsedBody = $null
            }

            if ($null -ne $ParsedBody -and $ParsedBody.PSObject.Properties['error'] -and -not [string]::IsNullOrWhiteSpace([string]$ParsedBody.error)) {
                $Parts = [System.Collections.Generic.List[string]]::new()
                $Parts.Add([string]$ParsedBody.error)

                if ($ParsedBody.PSObject.Properties['error_description'] -and -not [string]::IsNullOrWhiteSpace([string]$ParsedBody.error_description)) {
                    $Parts.Add([string]$ParsedBody.error_description)
                }

                if ($ParsedBody.PSObject.Properties['error_codes']) {
                    $Parts.Add(("error_codes: {0}" -f (@($ParsedBody.error_codes) -join ', ')))
                }

                $IdpErrorText = $Parts -join ': '
            }
            else {
                # Not a recognisable OAuth error document - the raw body is still more useful than
                # nothing, and is redacted the same as every other branch below.
                $IdpErrorText = $Body
            }
        }

        if ([string]::IsNullOrWhiteSpace($IdpErrorText)) {
            $IdpErrorText = $ErrorRecord.Exception.Message
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Message)) {
        $IdpErrorText = $Message
    }

    if ([string]::IsNullOrWhiteSpace($IdpErrorText)) {
        $IdpErrorText = "no further details were provided"
    }

    $FullMessage = Protect-LogMessage -Message ("The OAuth token request to '{0}' failed: {1}" -f $OAuthUri, $IdpErrorText)

    if ($null -ne $ErrorRecord) {
        $Exception = [System.Security.Authentication.AuthenticationException]::new($FullMessage, $ErrorRecord.Exception)
    }
    else {
        $Exception = [System.Security.Authentication.AuthenticationException]::new($FullMessage)
    }

    # The error id is the documented half of the contract, matching the convention used by
    # New-OmadaSessionExpiredError - callers match 'OmadaOAuthTokenRequestFailed' rather than for
    # equality, because ThrowTerminatingError appends the throwing function's name to it on its way out.
    return [System.Management.Automation.ErrorRecord]::new(
        $Exception,
        "OmadaOAuthTokenRequestFailed",
        [System.Management.Automation.ErrorCategory]::AuthenticationError,
        $OAuthUri
    )
}
