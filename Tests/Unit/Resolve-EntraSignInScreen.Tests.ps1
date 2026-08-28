param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    # Every snapshot the probe script produces carries all of these members, so the helper does too:
    # a test built on a half-populated object would pass for reasons the real page never reproduces.
    function New-PageState {
        param([hashtable]$Override = @{})

        $State = [ordered]@{
            ids                     = @()
            visibleIds              = @()
            errorCode               = '0'
            errorCodeText           = ''
            proofs                  = @()
            proofOptionCount        = 0
            accountTiles            = @()
            hasOtherTile            = $false
            displaySign             = $null
            hasVisiblePasswordInput = $false
            hasVisibleEmailInput    = $false
            path                    = '/common/login'
        }

        foreach ($Key in $Override.Keys) {
            $State[$Key] = $Override[$Key]
        }

        return [pscustomobject]$State
    }
}

Describe 'Resolve-EntraSignInScreen' -Tag 'Unit' {

    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            $Script:PreferredMfaMethodWarningIssued = $false
        }
    }

    Context 'Username and account discovery' {
        It 'Fills in the user name and submits it' {
            $PageState = New-PageState @{ ids = @('i0116', 'idSIButton9'); visibleIds = @('i0116', 'idSIButton9') }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                $Decision.Screen | Should -Be 'UsernameEntry'
                $Decision.Action | Should -Be 'SetValueAndClick'
                $Decision.ElementId | Should -Be 'i0116'
                $Decision.SubmitId | Should -Be 'idSIButton9'
                $Decision.ValueSource | Should -Be 'UserName'
                $Decision.Value | Should -Be 'someone@contoso.com'
            }
        }

        It 'Ignores a username field the page renders but hides' {
            # The password screen keeps i0116 in the markup, hidden. Acting on it there would retype
            # the user name over the password step.
            $PageState = New-PageState @{ ids = @('i0116', 'idSIButton9'); visibleIds = @('idSIButton9') }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                (Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword).Screen | Should -Not -Be 'UsernameEntry'
            }
        }
    }

    Context 'Pick an account' {
        It 'Selects the tile of the account the credential names' {
            $PageState = New-PageState @{
                ids          = @('idSIButton9')
                visibleIds   = @('idSIButton9')
                accountTiles = @(
                    [pscustomobject]@{ index = 0; testId = 'other@contoso.com' }
                    [pscustomobject]@{ index = 1; testId = 'someone@contoso.com' }
                )
                hasOtherTile = $true
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                $Decision.Screen | Should -Be 'AccountPicker'
                $Decision.Action | Should -Be 'ClickAccountTile'
                $Decision.Value | Should -Be 'someone@contoso.com'
            }
        }

        It 'Matches the tile whatever case Entra ID wrote the account name in' {
            # PowerShell's -eq is case-insensitive for strings, which is what this relies on, and
            # what the click helper's own toLowerCase comparison agrees with. Asserted rather than
            # assumed: -ceq is one character away, and the failure it would cause - falling through
            # to "use another account" on a tile that was right there - is not obvious from reading
            # the code.
            $PageState = New-PageState @{
                accountTiles = @([pscustomobject]@{ index = 0; testId = 'Someone@Contoso.com' })
                hasOtherTile = $true
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                $Decision.Action | Should -Be 'ClickAccountTile'
                $Decision.Value | Should -Be 'Someone@Contoso.com'
            }
        }

        It 'Falls back to "use another account" when no tile matches' {
            $PageState = New-PageState @{
                accountTiles = @([pscustomobject]@{ index = 0; testId = 'other@contoso.com' })
                hasOtherTile = $true
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                $Decision.Screen | Should -Be 'AccountPicker'
                $Decision.Action | Should -Be 'ClickUseAnotherAccount'
            }
        }

        It 'Waits and explains itself when neither a matching tile nor the fallback exists' {
            $PageState = New-PageState @{
                accountTiles = @([pscustomobject]@{ index = 0; testId = 'other@contoso.com' })
                hasOtherTile = $false
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                $Decision.Action | Should -Be 'Wait'
                $Decision.Reason | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Password' {
        It 'Fills in the password without ever putting it in the decision' {
            # The decision object reaches the verbose stream; the secret must not travel with it.
            $PageState = New-PageState @{ ids = @('i0118', 'idSIButton9'); visibleIds = @('i0118', 'idSIButton9') }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                $Decision.Screen | Should -Be 'PasswordEntry'
                $Decision.Action | Should -Be 'SetValueAndClick'
                $Decision.ElementId | Should -Be 'i0118'
                $Decision.SubmitId | Should -Be 'idSIButton9'
                $Decision.ValueSource | Should -Be 'Password'
                $Decision.Value | Should -BeNullOrEmpty
            }
        }
    }

    Context 'A screen that is not finished rendering' {
        It 'Does not type the password until the button that submits it is there' {
            # Filling the field and submitting it are two steps. Taking the first before the second
            # is possible retypes the password once per cycle with nothing to submit it, and waits
            # out the whole stall timeout instead of the tick or two the page needed.
            $PageState = New-PageState @{
                ids        = @('i0118', 'idSIButton9')
                visibleIds = @('i0118')
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                $Decision.Screen | Should -Be 'PasswordEntry'
                $Decision.Action | Should -Be 'Wait'
                $Decision.ValueSource | Should -Not -Be 'Password'
            }
        }

        It 'Does not type the user name until the button that submits it is there' {
            $PageState = New-PageState @{
                ids        = @('i0116', 'idSIButton9')
                visibleIds = @('i0116')
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                (Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword).Action | Should -Be 'Wait'
            }
        }
    }

    Context 'Passwordless credentials' {
        It 'Switches to another sign-in method rather than submitting an empty password' {
            $PageState = New-PageState @{
                ids        = @('i0118', 'idSIButton9', 'idA_PWD_SwitchToCredPicker')
                visibleIds = @('i0118', 'idSIButton9', 'idA_PWD_SwitchToCredPicker')
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com'

                $Decision.Screen | Should -Be 'SwitchToPasswordless'
                $Decision.Action | Should -Be 'Click'
                $Decision.ElementId | Should -Be 'idA_PWD_SwitchToCredPicker'
            }
        }

        It 'Uses the signInAnotherWay link when the credential picker link is absent' {
            $PageState = New-PageState @{
                ids        = @('i0118', 'idSIButton9', 'signInAnotherWay')
                visibleIds = @('i0118', 'idSIButton9', 'signInAnotherWay')
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                (Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com').ElementId | Should -Be 'signInAnotherWay'
            }
        }

        It 'Never submits a blank password, whatever the page offers' {
            # The negative criterion of issue #18: an empty-password credential must not spend one of
            # the attempts before smart lockout on a value that cannot be right.
            $Variant = @(
                @('i0118', 'idSIButton9')
                @('i0118', 'idSIButton9', 'idA_PWD_SwitchToCredPicker')
                @('i0118', 'idSIButton9', 'signInAnotherWay')
                @('i0118', 'idSIButton9', 'idA_PWD_ForgotPassword')
            )

            foreach ($Ids in $Variant) {
                $PageState = New-PageState @{ ids = $Ids; visibleIds = $Ids }

                InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                    $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com'

                    $Decision.ValueSource | Should -Not -Be 'Password'
                    ($Decision.Action -eq 'SetValueAndClick' -and $Decision.ElementId -eq 'i0118') | Should -BeFalse
                }
            }
        }

        It 'Does not click a "sign in another way" link the page is not showing' {
            # Entra keeps elements in the markup after hiding them. Clicking a hidden link does
            # nothing while reporting success, which is the shape of every silent stall on this
            # screen - and here it would also leave a passwordless account stuck on a password
            # prompt it can never answer.
            $Ids = @('i0118', 'idSIButton9', 'idA_PWD_SwitchToCredPicker', 'signInAnotherWay')
            $PageState = New-PageState @{ ids = $Ids; visibleIds = @('i0118', 'idSIButton9') }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com'

                $Decision.Screen | Should -Be 'PasswordRequired'
                $Decision.Action | Should -Be 'Wait'
                $Decision.ValueSource | Should -Not -Be 'Password'
            }
        }

        It 'Waits, saying so, when a password is required and none can be supplied' {
            $PageState = New-PageState @{ ids = @('i0118', 'idSIButton9'); visibleIds = @('i0118', 'idSIButton9') }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com'

                $Decision.Screen | Should -Be 'PasswordRequired'
                $Decision.Action | Should -Be 'Wait'
                $Decision.Reason | Should -BeLike '*empty password*'
            }
        }
    }

    Context 'Approval numbers' {
        It 'Reads the number from <ElementId>' -TestCases @(
            @{ ElementId = 'idRemoteNGC_DisplaySign' }
            @{ ElementId = 'idRichContext_DisplaySign' }
        ) {
            # Passwordless sign-in uses the first, Authenticator number match the second. Only the
            # second was ever read before, which is why passwordless sign-in stalled silently.
            $PageState = New-PageState @{ ids = @($ElementId); visibleIds = @($ElementId); displaySign = '42' }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState; ElementId = $ElementId } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com'

                $Decision.Screen | Should -Be 'ApprovalNumber'
                $Decision.Action | Should -Be 'ReadNumber'
                $Decision.ElementId | Should -Be $ElementId
                $Decision.Value | Should -Be '42'
            }
        }

        It 'Reports a failed approval as one to retry' {
            $PageState = New-PageState @{ ids = @('idA_SAASDS_Resend'); visibleIds = @('idA_SAASDS_Resend') }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -MfaRequestDisplayed

                $Decision.Screen | Should -Be 'MfaRetry'
                $Decision.Action | Should -Be 'Retry'
            }
        }

        It 'Does not mistake a resend link next to a live request for a failed one' {
            $PageState = New-PageState @{
                ids         = @('idA_SAASDS_Resend', 'idRichContext_DisplaySign')
                visibleIds  = @('idA_SAASDS_Resend', 'idRichContext_DisplaySign')
                displaySign = '42'
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                (Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -MfaRequestDisplayed).Screen | Should -Be 'ApprovalNumber'
            }
        }
    }

    Context 'One-time code' {
        It 'Waits for a code that only a person can supply, and says so' {
            $PageState = New-PageState @{
                ids        = @('idTxtBx_SAOTCC_OTC', 'idSubmit_SAOTCC_Continue')
                visibleIds = @('idTxtBx_SAOTCC_OTC', 'idSubmit_SAOTCC_Continue')
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com'

                $Decision.Screen | Should -Be 'OneTimeCode'
                $Decision.Action | Should -Be 'Wait'
                $Decision.Reason | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Choose a way to sign in' {
        It 'Clicks the option of the most secure offered method' {
            $PageState = New-PageState @{
                ids              = @('idDiv_SAOTCS_Proofs')
                visibleIds       = @('idDiv_SAOTCS_Proofs')
                proofs           = @(
                    [pscustomobject]@{ authMethodId = 'OneWaySMS'; isDefault = $true }
                    [pscustomobject]@{ authMethodId = 'PhoneAppNotification'; isDefault = $false }
                )
                proofOptionCount = 2
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com'

                $Decision.Screen | Should -Be 'MethodPicker'
                $Decision.Action | Should -Be 'ClickProofOption'
                $Decision.Index | Should -Be 1
                $Decision.Value | Should -Be 'PhoneAppNotification'
            }
        }

        It 'Honours -PreferredMfaMethod' {
            $PageState = New-PageState @{
                ids              = @('idDiv_SAOTCS_Proofs')
                visibleIds       = @('idDiv_SAOTCS_Proofs')
                proofs           = @(
                    [pscustomobject]@{ authMethodId = 'OneWaySMS'; isDefault = $true }
                    [pscustomobject]@{ authMethodId = 'PhoneAppNotification'; isDefault = $false }
                )
                proofOptionCount = 2
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                (Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -PreferredMfaMethod 'OneWaySMS').Index | Should -Be 0
            }
        }

        It 'Refuses to click by position when the options and the methods do not line up' {
            # The option elements carry no identifier naming the method, so position is the only
            # link between them. A page where that link is broken is a page to leave alone.
            $PageState = New-PageState @{
                ids              = @('idDiv_SAOTCS_Proofs')
                visibleIds       = @('idDiv_SAOTCS_Proofs')
                proofs           = @(
                    [pscustomobject]@{ authMethodId = 'OneWaySMS'; isDefault = $true }
                    [pscustomobject]@{ authMethodId = 'PhoneAppNotification'; isDefault = $false }
                )
                proofOptionCount = 5
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com'

                $Decision.Action | Should -Be 'Wait'
                $Decision.Reason | Should -BeLike '*cannot be selected safely*'
            }
        }
    }

    Context 'Stay signed in' {
        It 'Declines by clicking the back button, with no button text read at all' {
            # This is the screen that used to be recognized by comparing its buttons to the words
            # 'Yes' and 'No', which is why credential autofill did nothing on a tenant served in any
            # other language. The checkbox is on no other screen and is not localized.
            $PageState = New-PageState @{
                ids        = @('KmsiCheckboxField', 'idBtn_Back', 'idSIButton9')
                visibleIds = @('KmsiCheckboxField', 'idBtn_Back', 'idSIButton9')
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                $Decision.Screen | Should -Be 'StaySignedIn'
                $Decision.Action | Should -Be 'Click'
                $Decision.ElementId | Should -Be 'idBtn_Back'
            }
        }
    }

    Context 'Stay signed in, when the page only looks like it' {
        It 'Does not act on a back button the page is not showing' {
            # Clicking an element that is in the markup but not actionable does nothing, and this
            # rule is tested before the username and password screens - so a stale checkbox left in
            # the DOM would shadow the screen the user is actually on.
            $PageState = New-PageState @{
                ids        = @('KmsiCheckboxField', 'idBtn_Back', 'i0116', 'idSIButton9')
                visibleIds = @('i0116', 'idSIButton9')
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                $Decision.Screen | Should -Be 'UsernameEntry'
            }
        }

        It 'Still recognizes the screen when the checkbox itself is styled out of sight' {
            # The real input of a styled checkbox is routinely hidden behind its label. The checkbox
            # is the marker for this screen, so requiring it to be visible would risk not
            # recognizing the screen at all; only the button that gets clicked has to be actionable.
            $PageState = New-PageState @{
                ids        = @('KmsiCheckboxField', 'idBtn_Back', 'idSIButton9')
                visibleIds = @('idBtn_Back', 'idSIButton9')
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                $Decision.Screen | Should -Be 'StaySignedIn'
                $Decision.ElementId | Should -Be 'idBtn_Back'
            }
        }
    }

    Context 'Errors the server reports' {
        It 'Ends the sign-in on <ErrorCode> instead of retrying it' -TestCases @(
            @{ ErrorCode = '53003' }
            @{ ErrorCode = '50126' }
            @{ ErrorCode = '50053' }
            @{ ErrorCode = '50055' }
        ) {
            $PageState = New-PageState @{
                ids        = @('i0118', 'idSIButton9')
                visibleIds = @('i0118', 'idSIButton9')
                errorCode  = $ErrorCode
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState; ErrorCode = $ErrorCode } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                $Decision.Screen | Should -Be 'SignInError'
                $Decision.Action | Should -Be 'Stop'
                $Decision.IsTerminal | Should -BeTrue
                $Decision.Code | Should -Be ("AADSTS{0}" -f $ErrorCode)
            }
        }

        It 'Reads the code from sErrorCode when iErrorCode is absent' {
            $PageState = New-PageState @{ errorCode = ''; errorCodeText = '53003' }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                (Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com').Action | Should -Be 'Stop'
            }
        }

        It 'Hands <ErrorCode> back to the user at once, without ending the sign-in' -TestCases @(
            @{ ErrorCode = '50072' }
            @{ ErrorCode = '50074' }
            @{ ErrorCode = '50158' }
        ) {
            # 'Manual', not 'Wait'. Waiting is the right answer to a page this module does not
            # recognize, because it might only be mid-navigation; a screen that has named its own
            # error is not that page, and making the user watch a still window for the length of the
            # stall timeout before being told what happened is a minute spent saying nothing.
            $PageState = New-PageState @{ errorCode = $ErrorCode }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState; ErrorCode = $ErrorCode } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com'

                $Decision.Action | Should -Be 'Manual'
                $Decision.IsTerminal | Should -BeFalse
                $Decision.Code | Should -Be ("AADSTS{0}" -f $ErrorCode)
                $Decision.Reason | Should -Not -BeNullOrEmpty
            }
        }

        It 'Hands an error code it does not recognize back to the user rather than guessing' {
            $PageState = New-PageState @{ errorCode = '90210' }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com'

                $Decision.Action | Should -Be 'Manual'
                $Decision.IsTerminal | Should -BeFalse
            }
        }

        It 'Reads the error before acting on a password field that is on the same page' {
            # A refused password screen is rendered again, with the field intact. Filling it in
            # before reading the code is exactly how an account reaches smart lockout.
            $PageState = New-PageState @{
                ids        = @('i0118', 'idSIButton9', 'passwordError')
                visibleIds = @('i0118', 'idSIButton9', 'passwordError')
                errorCode  = '50126'
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                $Decision.ValueSource | Should -Not -Be 'Password'
                $Decision.Action | Should -Be 'Stop'
            }
        }
    }

    Context 'Pages this module does not recognize' {
        It 'Waits rather than guessing, so a page mid-navigation is not mistaken for a broken one' {
            $PageState = New-PageState

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                $Decision.Screen | Should -Be 'Unknown'
                $Decision.Action | Should -Be 'Wait'
                $Decision.Reason | Should -Not -BeNullOrEmpty
            }
        }

        It 'Names the renamed field when a password screen no longer carries the id it used to' {
            $PageState = New-PageState @{ hasVisiblePasswordInput = $true }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                $Decision.Screen | Should -Be 'UnrecognizedPasswordScreen'
                $Decision.Reason | Should -BeLike '*i0118*'
            }
        }

        It 'Names the renamed field when an account screen no longer carries the id it used to' {
            $PageState = New-PageState @{ hasVisibleEmailInput = $true }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                $Decision.Screen | Should -Be 'UnrecognizedUserNameScreen'
                $Decision.Reason | Should -BeLike '*i0116*'
            }
        }

        It 'Says the page could not be read when there is no snapshot at all' {
            InModuleScope 'OmadaWeb.PS' {
                $Decision = Resolve-EntraSignInScreen -PageState $null -UserName 'someone@contoso.com'

                $Decision.Action | Should -Be 'Wait'
                $Decision.Reason | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Elements the page is not showing' {
        # The sign-in app leaves elements behind after hiding them - the username field is still in
        # the markup on the password screen - so presence says nothing about which screen this is.
        # Acting on a hidden element does nothing while reporting success, which restarts the stall
        # clock, so the driver cannot tell that apart from working. Every screen below is therefore
        # given its own elements as present-but-hidden, and none of them may produce an action.
        It 'Does not act on a hidden <Screen>' -TestCases @(
            @{ Screen = 'username screen'; Ids = @('i0116', 'idSIButton9') }
            @{ Screen = 'password screen'; Ids = @('i0118', 'idSIButton9') }
            @{ Screen = 'one-time code screen'; Ids = @('idTxtBx_SAOTCC_OTC', 'idSubmit_SAOTCC_Continue') }
            @{ Screen = 'method picker'; Ids = @('idDiv_SAOTCS_Proofs') }
            @{ Screen = 'approval number'; Ids = @('idRemoteNGC_DisplaySign') }
            @{ Screen = 'stay signed in button'; Ids = @('KmsiCheckboxField', 'idBtn_Back') }
        ) {
            $PageState = New-PageState @{ ids = $Ids; visibleIds = @() }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                $Decision.Action | Should -Be 'Wait' -Because 'nothing on this page can be clicked or typed into'
            }
        }

        It 'Does not report a hidden resend link as a failed approval' {
            $PageState = New-PageState @{ ids = @('idA_SAASDS_Resend'); visibleIds = @() }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                (Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -MfaRequestDisplayed).Screen | Should -Not -Be 'MfaRetry'
            }
        }
    }

    Context 'Language independence' {
        It 'Decides identically for every screen whatever language the tenant is served in' {
            # The snapshot the decision is made from carries no rendered text at all, so a tenant
            # served in Dutch or German produces byte-identical input for the same screen. This
            # asserts the property that makes that true: no member of the snapshot is prose.
            $Screen = @(
                @{ ids = @('i0116', 'idSIButton9') }
                @{ ids = @('i0118', 'idSIButton9') }
                @{ ids = @('KmsiCheckboxField', 'idBtn_Back', 'idSIButton9') }
                @{ ids = @('idRemoteNGC_DisplaySign') }
            )

            foreach ($Definition in $Screen) {
                $PageState = New-PageState @{ ids = $Definition.ids; visibleIds = $Definition.ids }

                InModuleScope 'OmadaWeb.PS' -Parameters @{ PageState = $PageState } {
                    $Decision = Resolve-EntraSignInScreen -PageState $PageState -UserName 'someone@contoso.com' -HasPassword

                    $Decision.Screen | Should -Not -Be 'Unknown'

                    # Nothing the decision was made from is text a translator would have touched.
                    foreach ($Property in $PageState.PSObject.Properties) {
                        $Property.Name | Should -Not -BeIn @('title', 'buttonText', 'message', 'label')
                    }
                }
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
