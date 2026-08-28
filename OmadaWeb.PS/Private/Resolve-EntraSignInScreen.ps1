function Resolve-EntraSignInScreen {
    <#
    .SYNOPSIS
        Decides which Entra ID sign-in screen the browser is on, and what to do about it.

    .DESCRIPTION
        This is the whole judgement of the Microsoft sign-in automation, kept apart from the browser
        so it can be tested without one. It is given a snapshot of the page - the JSON document
        Get-EntraSignInProbeScript's JavaScript produces - and returns one decision:
        which screen this is, and the single action that moves the sign-in forward from it.

        Nothing in the snapshot is text a user reads. The Entra sign-in app is served fully
        localized, and the previous implementation recognized the 'Stay signed in?' screen by
        comparing its two buttons to the words 'Yes' and 'No', which is why credential autofill did
        nothing at all on a tenant served in any other language, and did it silently. Every rule
        below keys on something the server decides rather than something a translator does: the
        stable element ids of the sign-in app, the numeric error code in the page's own $Config
        object, the authMethodId values in its proofs array, and - only as a last resort - the shape
        of the form itself.

        The order of the rules is not arbitrary, because several screens share element ids:

          1. An error code outranks everything. A page can carry a perfectly ordinary password field
             and still be reporting that the previous password was wrong, and acting on the field
             before reading the code is exactly how an account gets locked out.
          2. 'Stay signed in?' is recognized by its checkbox, which no other screen carries. It has
             to be tested before the submit button it shares with the username and password screens.
          3. The password screen, which for a credential that has no password is not a password
             screen at all but a prompt to sign in another way.
          4. The approval number - passwordless sign-in and Authenticator number match both show one,
             in two different elements, and both are read here. Only the first was read before.
          5. The remaining screens, ending with the username screen, which is the most generic.

        Anything not recognized returns the action 'Wait'. That is deliberate rather than lazy: a
        page caught mid-navigation is indistinguishable from a page this module has never seen, so
        the decision of when an unrecognized page has stopped being a temporary one belongs to
        Test-LoginAutomationStalled, and the explanation this function puts in Reason is what
        Switch-ToManualLogin then reports.

        The password is never part of the returned decision. A verdict that carried it would be one
        Write-Verbose call away from a support log; instead the decision says only that the value to
        type comes from the credential's password, and the caller - which holds the credential
        anyway - reads it.

    .PARAMETER PageState
        The deserialized snapshot of the page, as produced by the script from
        Get-EntraSignInProbeScript.

    .PARAMETER UserName
        The user name from the credential, used to fill the username field and to pick the matching
        tile on the 'Pick an account' screen.

    .PARAMETER HasPassword
        Whether the credential carries a password. A credential without one is a passwordless
        account, and the password screen is then answered by switching to another sign-in method
        rather than by submitting an empty string.

    .PARAMETER PreferredMfaMethod
        The authMethodId the caller asked for through -PreferredMfaMethod, when there was one.

    .PARAMETER MfaRequestDisplayed
        Whether an approval number has already been shown to the user for this sign-in. It is what
        tells a resend link that follows a failed approval from one that is merely offered next to a
        request still waiting.

    .OUTPUTS
        PSCustomObject with the members Screen, Action, ElementId, SubmitId, Index, Value,
        ValueSource, Code, Reason and IsTerminal.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        $PageState,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$UserName,

        [switch]$HasPassword,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$PreferredMfaMethod,

        [switch]$MfaRequestDisplayed
    )

    $Id = $Script:EntraSignInElementId

    $Decision = [pscustomobject]@{
        Screen      = "Unknown"
        Action      = "Wait"
        ElementId   = $null
        SubmitId    = $null
        Index       = -1
        Value       = $null
        ValueSource = $null
        Code        = $null
        Reason      = $null
        IsTerminal  = $false
    }

    if ($null -eq $PageState) {
        $Decision.Reason = "The sign-in page could not be read."
        return $Decision
    }

    # A snapshot from an older or a partly failed read may not carry every member, and Set-StrictMode
    # turns a plain property access on a missing member into a terminating error. Reading the whole
    # snapshot once, through the property bag, keeps a missing member a missing value - which is what
    # the rules below are written to handle.
    $Value = @{}
    foreach ($Property in $PageState.PSObject.Properties) {
        $Value[$Property.Name] = $Property.Value
    }

    $Present = @()
    if ($null -ne $Value["ids"]) {
        $Present = @($Value["ids"] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $Visible = @()
    if ($null -ne $Value["visibleIds"]) {
        $Visible = @($Value["visibleIds"] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    # 1. Whatever else the page shows, a failure reported by the server decides first.
    $ReportedCode = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$Value["errorCode"])) {
        $ReportedCode = [string]$Value["errorCode"]
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$Value["errorCodeText"])) {
        $ReportedCode = [string]$Value["errorCodeText"]
    }

    $ErrorVerdict = Get-EntraErrorVerdict -ErrorCode $ReportedCode
    if ($ErrorVerdict.IsError) {
        $Decision.Screen = "SignInError"
        $Decision.Code = $ErrorVerdict.Code
        $Decision.Reason = $ErrorVerdict.Reason
        $Decision.IsTerminal = $ErrorVerdict.IsTerminal
        $Decision.Action = "Wait"
        if ($ErrorVerdict.Action -eq "Stop") {
            $Decision.Action = "Stop"
        }

        return $Decision
    }

    # 2. A failed approval offers to send a new one. Recognized before the approval screen itself,
    #    because a resend link and an approval number can be on the page at the same time.
    $HasResendLink = ($Id.MfaResendTotp -in $Present) -or ($Id.MfaResendDs -in $Present)
    $HasApprovalNumber = ($Id.PasswordlessNumber -in $Present) -or ($Id.NumberMatch -in $Present)
    if ($MfaRequestDisplayed -and $HasResendLink -and -not $HasApprovalNumber) {
        $Decision.Screen = "MfaRetry"
        $Decision.Action = "Retry"
        $Decision.Reason = "The sign-in request was not approved, so Entra ID is offering to send a new one."
        return $Decision
    }

    # 3. 'Stay signed in?'. Its checkbox is on no other screen, and the back button is its decline
    #    action - which is what the two localized button labels used to be compared for.
    if ($Id.KeepMeSignedIn -in $Present -and $Id.Back -in $Present) {
        $Decision.Screen = "StaySignedIn"
        $Decision.Action = "Click"
        $Decision.ElementId = $Id.Back
        $Decision.Reason = "Declining to stay signed in."
        return $Decision
    }

    # 4. The password screen - or, for a passwordless credential, the screen to leave.
    if ($Id.Password -in $Visible) {
        if ($HasPassword) {
            $Decision.Screen = "PasswordEntry"
            $Decision.Action = "SetValueAndClick"
            $Decision.ElementId = $Id.Password
            $Decision.SubmitId = $Id.Submit
            $Decision.ValueSource = "Password"
            return $Decision
        }

        # The credential names an account but carries no password, so this account signs in another
        # way. Submitting an empty password would spend one of the attempts before smart lockout on
        # a value that cannot be right.
        foreach ($SwitchId in @($Id.SwitchToCredPicker, $Id.SignInAnotherWay)) {
            if ($SwitchId -in $Present) {
                $Decision.Screen = "SwitchToPasswordless"
                $Decision.Action = "Click"
                $Decision.ElementId = $SwitchId
                $Decision.Reason = "The credential has no password, so another sign-in method is chosen instead of submitting an empty one."
                return $Decision
            }
        }

        $Decision.Screen = "PasswordRequired"
        $Decision.Action = "Wait"
        $Decision.Reason = "The credential has no password and this page offers no way to sign in without one. An empty password is deliberately not submitted."
        return $Decision
    }

    # 5. The approval number. Passwordless sign-in shows it in one element and Authenticator number
    #    match in another; both mean the same thing to the user, so both are read.
    if ($HasApprovalNumber) {
        $NumberElementId = $Id.PasswordlessNumber
        if ($Id.PasswordlessNumber -notin $Present) {
            $NumberElementId = $Id.NumberMatch
        }

        $Decision.Screen = "ApprovalNumber"
        $Decision.Action = "ReadNumber"
        $Decision.ElementId = $NumberElementId
        if (-not [string]::IsNullOrWhiteSpace([string]$Value["displaySign"])) {
            $Decision.Value = [string]$Value["displaySign"]
        }

        return $Decision
    }

    # 6. A one-time code has to be read off a device and typed, so there is nothing to automate -
    #    but saying so beats a window that looks frozen.
    if ($Id.OneTimeCode -in $Visible) {
        $Decision.Screen = "OneTimeCode"
        $Decision.Action = "Wait"
        $Decision.Reason = "Entra ID is asking for a one-time code, which has to be entered by hand."
        return $Decision
    }

    # 7. 'Choose a way to sign in'. The proofs array names the offered methods; the container holds
    #    one clickable option per entry, in the same order.
    $Proof = @()
    if ($null -ne $Value["proofs"]) {
        $Proof = @($Value["proofs"])
    }

    $HasProofScreen = ($Id.ProofsContainer -in $Present) -or ($Id.MethodPicker -in $Present) -or $Proof.Count -gt 0
    if ($HasProofScreen) {
        $Decision.Screen = "MethodPicker"

        $OptionCount = 0
        if ($null -ne $Value["proofOptionCount"]) {
            $OptionCount = [int]$Value["proofOptionCount"]
        }

        $Chosen = Select-EntraMfaMethod -Proof $Proof -PreferredMethod $PreferredMfaMethod
        if ($null -eq $Chosen) {
            $Decision.Reason = "Entra ID is asking which verification method to use, but the page did not say which methods are offered."
            return $Decision
        }

        # The option that gets clicked is identified only by its position, so a page whose list of
        # options no longer lines up with its list of methods is a page to leave alone.
        if ($OptionCount -ne $Proof.Count -or $Chosen.Index -ge $OptionCount) {
            $Decision.Reason = "Entra ID offered {0} verification methods but {1} options to click, so the method cannot be selected safely." -f $Proof.Count, $OptionCount
            return $Decision
        }

        $Decision.Action = "ClickProofOption"
        $Decision.Index = $Chosen.Index
        $Decision.Value = $Chosen.AuthMethodId
        $Decision.Reason = "Selecting verification method '{0}'." -f $Chosen.AuthMethodId
        return $Decision
    }

    # 8. 'Pick an account'. Tested before the username screen, which that screen does not show.
    $Tile = @()
    if ($null -ne $Value["accountTiles"]) {
        $Tile = @($Value["accountTiles"])
    }

    $HasOtherTile = $false
    if ($null -ne $Value["hasOtherTile"]) {
        $HasOtherTile = [bool]$Value["hasOtherTile"]
    }

    if (($Tile.Count -gt 0 -or $HasOtherTile) -and $Id.UserName -notin $Visible) {
        $Decision.Screen = "AccountPicker"

        $WantedUserName = ""
        if (-not [string]::IsNullOrWhiteSpace($UserName)) {
            $WantedUserName = $UserName.Trim()
        }

        $Match = @($Tile | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.testId) -and [string]$_.testId -eq $WantedUserName })
        if ($Match.Count -gt 0) {
            $Decision.Action = "ClickAccountTile"
            $Decision.Value = [string]$Match[0].testId
            $Decision.Reason = "Selecting the tile of the account the credential names."
            return $Decision
        }

        if ($HasOtherTile) {
            $Decision.Action = "ClickUseAnotherAccount"
            $Decision.Reason = "The account the credential names is not among the tiles, so another account is entered instead."
            return $Decision
        }

        $Decision.Reason = "Entra ID is asking which account to use, but neither a matching tile nor the option to use another account is on the page."
        return $Decision
    }

    # 9. The username screen, the most generic of the sign-in screens and therefore the last one.
    if ($Id.UserName -in $Visible -and $Id.Submit -in $Present) {
        $Decision.Screen = "UsernameEntry"
        $Decision.Action = "SetValueAndClick"
        $Decision.ElementId = $Id.UserName
        $Decision.SubmitId = $Id.Submit
        $Decision.ValueSource = "UserName"
        $Decision.Value = $UserName
        return $Decision
    }

    # 10. Nothing was recognized by id. The shape of the form still says which screen this is, which
    #     turns "no scenario matched" into a diagnostic naming the element that has been renamed -
    #     the single most useful thing to report when Microsoft changes the sign-in app.
    if ($Value["hasVisiblePasswordInput"]) {
        $Decision.Screen = "UnrecognizedPasswordScreen"
        $Decision.Reason = "This is a password screen - it has a visible password field - but the field is not the one this module knows as '{0}'." -f $Id.Password
        return $Decision
    }

    if ($Value["hasVisibleEmailInput"]) {
        $Decision.Screen = "UnrecognizedUserNameScreen"
        $Decision.Reason = "This is an account screen - it has a visible e-mail field - but the field is not the one this module knows as '{0}'." -f $Id.UserName
        return $Decision
    }

    $Decision.Reason = "The page carries none of the elements this module recognizes."
    return $Decision
}
