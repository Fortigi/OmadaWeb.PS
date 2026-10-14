function Test-OmadaLogonPageError {
    <#
    .SYNOPSIS
        Decides whether an error shown on an Omada logon page can be retried.

    .DESCRIPTION
        Get-OmadaLogonErrorScript reads whatever error Omada put on its logon landing page. This
        function is the judgement on it, kept apart from the two drivers so the rule is written once
        and can be tested without a browser.

        Not every error there is terminal. Typing a wrong password into Omada's own logon form
        produces one, and the right answer is to leave the window alone and let the user type it
        again. A federated sign-in that came back with 'AADSTS50178: User account ... does not exist
        in tenant ...' produces one too, and there the right answer is the opposite: no number of new
        browser windows will turn that account into a member of the tenant, so the module has to stop
        rather than spend three watchdog timeouts - half an hour - re-opening a window that lands on
        the same page every time.

        Two things make an error terminal:

          - Its text carries a signature of an identity-provider failure that a retry cannot change:
            an AADSTS code, an OpenID Connect error response, or a statement that the account is
            unknown to, or not permitted in, the tenant the Omada application lives in. Errors that
            genuinely can pass - 'server_error', 'temporarily_unavailable', 'interaction_required' -
            are deliberately absent from that list.
          - Or the sign-in page shows an error and offers nothing to retry with. A logon page without
            a visible credential field is a page the user cannot act on, which is the general shape of
            "the identity provider sent the browser back here with a failure" - and the widening this
            rule exists for, since Omada versions and themes do not agree on the exact wording. It is
            deliberately limited to a sign-in page: an error on an ordinary Omada page says nothing
            about a sign-in that may still be in progress, so there only the first rule applies.

        A terminal error is also classified, because "this will never work" and "this will never work
        with this account" are not the same message and do not deserve the same answer. Category is
        one of WrongAccount, Authorization, AppRegistration, IdentityProvider, Unknown or None, and
        Recoverable is true for exactly one of them: WrongAccount, where the account signing in is
        simply not an account of the application's tenant and signing in as somebody else is the
        whole fix. Nothing in this function acts on that - it is the caller that decides whether to
        offer the user another go - but the classification is written here because this is where the
        evidence is.

    .PARAMETER Message
        The error text read off the page. An empty value means no error was shown.

    .PARAMETER Source
        Identifier of the element the text came from, carried through to the diagnostic.

    .PARAMETER HasLogonForm
        Whether the page still offers a visible way to sign in.

    .PARAMETER OnLogonPage
        Whether the browser is on a sign-in page, which is what makes the shape of the page evidence
        about the sign-in rather than about the application.

    .OUTPUTS
        PSCustomObject with the members IsError, IsFatal, Message, Code, Reason, Source, Category and
        Recoverable. IsError is false when the page shows no error at all.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Source,

        [switch]$HasLogonForm,

        [switch]$OnLogonPage
    )

    $Verdict = [pscustomobject]@{
        IsError     = $false
        IsFatal     = $false
        Message     = $null
        Code        = $null
        Reason      = $null
        Source      = $Source
        Category    = "None"
        Recoverable = $false
    }

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $Verdict
    }

    # The page text arrives with the line breaks and indentation of the markup around it.
    $Text = ($Message -replace '\s+', ' ').Trim()
    if ($Text.Length -gt 2000) {
        $Text = "{0}..." -f $Text.Substring(0, 2000)
    }

    $Verdict.IsError = $true
    $Verdict.Message = $Text

    # An AADSTS code is what a Microsoft support article is indexed by, so it is worth naming
    # separately from the sentence it sits in.
    $CodeMatch = [regex]::Match($Text, '(?i)\bAADSTS\d{3,}\b')
    if (-not $CodeMatch.Success) {
        $CodeMatch = [regex]::Match($Text, '(?i)\b(invalid_request|invalid_client|unauthorized_client|unsupported_response_type|access_denied|consent_required|invalid_grant|server_error|temporarily_unavailable|interaction_required|login_required)\b')
    }
    if ($CodeMatch.Success) {
        $Verdict.Code = $CodeMatch.Value
    }

    # Ordered so the most specific explanation wins: 'does not exist in tenant' says more about what
    # to do next than the AADSTS number it is quoted with.
    # PowerShell's -match is case-insensitive, which is what these are matched with below.
    $FatalSignature = [ordered]@{
        'does not exist in tenant'                                           = @{ Category = "WrongAccount"; Reason = "The account that signed in is not known in the tenant the Omada application is registered in." }
        'needs to be added as an external user'                              = @{ Category = "WrongAccount"; Reason = "The account that signed in has to be invited into the application's tenant as a guest first." }
        # The codes for the same condition, matched after the English sentences and before anything
        # more general: a sign-in page served in another language carries the number and not the
        # words, and reporting that as a refusal nobody can act on would lose the one remedy that
        # works. AADSTS50020 and AADSTS50178 are both emitted for an account of another tenant, and
        # AADSTS51004 is the same fact stated from the directory's side.
        '\bAADSTS(50020|50178|51004)\b'                                      = @{ Category = "WrongAccount"; Reason = "The account that signed in is not known in the tenant the Omada application is registered in." }
        'cannot access the application'                                      = @{ Category = "Authorization"; Reason = "The account that signed in is not permitted to use the Omada application." }
        '\bconsent_required\b|\bAADSTS65001\b|\bAADSTS90094\b'               = @{ Category = "AppRegistration"; Reason = "The application needs consent that this account cannot grant." }
        '\baccess_denied\b'                                                  = @{ Category = "IdentityProvider"; Reason = "The identity provider denied the sign-in." }
        '\b(invalid_client|unauthorized_client|unsupported_response_type)\b' = @{ Category = "AppRegistration"; Reason = "The identity provider rejected the application registration behind this sign-in." }
        '\binvalid_request\b'                                                = @{ Category = "IdentityProvider"; Reason = "The identity provider rejected the sign-in request." }
        'OpenIdConnectMessage\.Error'                                        = @{ Category = "IdentityProvider"; Reason = "The identity provider returned an error instead of a token." }
        '\bAADSTS\d{3,}\b'                                                   = @{ Category = "IdentityProvider"; Reason = "Microsoft Entra ID refused the sign-in." }
    }

    foreach ($Signature in $FatalSignature.Keys) {
        if ($Text -match $Signature) {
            $Verdict.IsFatal = $true
            $Verdict.Reason = $FatalSignature[$Signature].Reason
            $Verdict.Category = $FatalSignature[$Signature].Category

            # The one category a second sign-in can get past. Everything else answers every account
            # the same way, so re-opening a window for it would only spend the user's time.
            $Verdict.Recoverable = $Verdict.Category -eq "WrongAccount"
            return $Verdict
        }
    }

    if ($OnLogonPage -and -not $HasLogonForm) {
        $Verdict.IsFatal = $true
        $Verdict.Category = "Unknown"
        $Verdict.Reason = "The logon page reports an error and offers no way to sign in again, so a new browser window would land on the same page."
        return $Verdict
    }

    $Verdict.Reason = "The page reports an error that this module cannot tell is final, so the sign-in is left to you."
    return $Verdict
}
