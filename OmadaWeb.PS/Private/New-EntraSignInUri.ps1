function New-EntraSignInUri {
    <#
    .SYNOPSIS
        Rewrites a Microsoft sign-in request so that it asks for the account the caller named.

    .DESCRIPTION
        Omada, not this module, builds the authorization request: the browser is sent to the Omada
        instance and Omada redirects it to Entra ID. Everything the module knows about which account
        should sign in therefore arrives too late to matter. Entra has already picked one - from the
        browser profile, or from the Windows account WebView2 signs in with - and by the time a
        sign-in screen could be filled in, there is no screen, only a redirect back to Omada carrying
        whichever identity was already there. That is the whole of AADSTS50178: the wrong account was
        chosen silently, before anything this module drives had a say.

        The one place to intervene is the navigation itself, and the parameters to intervene with are
        Entra's own:

          - login_hint names the account, and is paired with prompt=login so that an existing session
            for somebody else cannot answer the request instead.
          - prompt=select_account asks Entra to show the account picker, including the option to use
            an account it has never seen.

        The two are mutually exclusive: Microsoft's OpenID Connect documentation states plainly that
        login_hint and select_account cannot both be sent, so this function refuses the combination
        rather than sending a request Entra would have to resolve by guessing.

        WHAT IT WILL NOT TOUCH

          - Any host but the Microsoft sign-in hosts. The value comes from a live navigation, and a
            login_hint appended to some other identity provider's request would be handing an account
            name to a party the caller never named.
          - Any path but an authorization endpoint. A redirect chain passes through several requests
            on the same host - the credential post, the "keep me signed in" page - and none of them
            takes these parameters.
          - A request that already carries the parameter. Omada's own request may set prompt itself,
            and overriding it would be this module overruling the application it is signing in to.
          - state, nonce, redirect_uri or anything else already in the query. Only parameters are
            added, so the request Entra validates is still the request Omada built, and the
            correlation cookie the application set for it still matches.

        WS-Federation is answered with wfresh=0 instead, which is that protocol's way of saying the
        session must be re-established rather than reused. It cannot name an account, so a user name
        only turns into "sign in again" there - still the difference between choosing an account and
        being handed one.

    .PARAMETER Uri
        The URI the browser is about to navigate to.

    .PARAMETER UserName
        The account the caller named, if any.

    .PARAMETER SelectAccount
        Ask Entra ID for the account picker.

    .OUTPUTS
        System.String, the rewritten URI - or $null when this request is not one to rewrite, which is
        the ordinary case and is not a failure.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Uri,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$UserName,

        [switch]$SelectAccount
    )

    if ([string]::IsNullOrWhiteSpace($Uri)) {
        return $null
    }

    $HasUserName = -not [string]::IsNullOrWhiteSpace($UserName)
    if (-not $HasUserName -and -not $SelectAccount) {
        # Nothing was asked for, so the request Omada built is the request that is sent. This is the
        # default and it is deliberately indistinguishable from the module not being here at all.
        return $null
    }

    if ($HasUserName -and $SelectAccount) {
        # Refused rather than resolved: Entra accepts one or the other, and picking one here would
        # silently drop what the caller asked for.
        "New-EntraSignInUri - A user name and -SelectAccount cannot both be sent to Entra ID, so the request is left alone." | Write-Verbose
        return $null
    }

    $Address = $null
    try {
        $Address = [System.Uri]::new($Uri)
    }
    catch {
        return $null
    }

    if ($Address.Scheme -ne "https") {
        return $null
    }

    # The sign-in hosts this module drives. Kept as an explicit list rather than a pattern over
    # microsoft.com, because what is added to these requests is an account name.
    $SignInHost = @(
        "login.microsoftonline.com",
        "login.microsoftonline.us",
        "login.partner.microsoftonline.cn"
    )
    if ($Address.Host.ToLowerInvariant() -notin $SignInHost) {
        return $null
    }

    $Path = $Address.AbsolutePath.TrimEnd("/").ToLowerInvariant()
    $IsAuthorize = $Path.EndsWith("/oauth2/authorize") -or $Path.EndsWith("/oauth2/v2.0/authorize")
    $IsWsFederation = $Path.EndsWith("/wsfed") -or $Path.EndsWith("/wsfederation")

    if (-not $IsAuthorize -and -not $IsWsFederation) {
        return $null
    }

    $Query = $Address.Query
    if ($Query.StartsWith("?")) {
        $Query = $Query.Substring(1)
    }

    $Addition = [System.Collections.Generic.List[string]]::new()

    if ($IsWsFederation) {
        # WS-Federation has no login_hint and no account picker. wfresh=0 is what it does have: the
        # existing session is not good enough, authenticate again.
        if ($Query -match '(?i)(^|&)wfresh=') {
            return $null
        }
        $Addition.Add("wfresh=0")
    }
    else {
        $HasPrompt = $Query -match '(?i)(^|&)prompt='
        $HasLoginHint = $Query -match '(?i)(^|&)login_hint='

        if ($SelectAccount) {
            if ($HasPrompt) {
                return $null
            }
            $Addition.Add("prompt=select_account")
        }
        else {
            if ($HasLoginHint -and $HasPrompt) {
                return $null
            }

            if (-not $HasLoginHint) {
                $Addition.Add("login_hint={0}" -f [System.Uri]::EscapeDataString($UserName.Trim()))
            }

            # Without this an existing session for another account answers the request before the
            # hint is ever read, which is the failure this function exists to prevent.
            if (-not $HasPrompt) {
                $Addition.Add("prompt=login")
            }
        }
    }

    if ($Addition.Count -eq 0) {
        return $null
    }

    $Separator = "?"
    if (-not [string]::IsNullOrEmpty($Query)) {
        $Separator = "&"
    }

    # Rebuilt from the parts rather than from the string, so a fragment - which Entra does use for
    # some response modes - stays behind the query instead of swallowing what is appended.
    $Rebuilt = "{0}{1}{2}" -f $Address.GetLeftPart([System.UriPartial]::Path), $Address.Query, ($Separator + ($Addition -join "&"))
    if (-not [string]::IsNullOrEmpty($Address.Fragment)) {
        $Rebuilt = "{0}{1}" -f $Rebuilt, $Address.Fragment
    }

    return $Rebuilt
}
