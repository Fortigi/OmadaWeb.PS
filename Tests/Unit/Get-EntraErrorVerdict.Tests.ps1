param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-EntraErrorVerdict' -Tag 'Unit' {

    Context 'Pages that report no failure' {
        It 'Reports no error for <Description>' -TestCases @(
            @{ Description = 'a healthy page, which writes iErrorCode 0'; ErrorCode = '0' }
            @{ Description = 'an empty value'; ErrorCode = '' }
            @{ Description = 'a missing value'; ErrorCode = $null }
            @{ Description = 'a value carrying no digits at all'; ErrorCode = 'none' }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ ErrorCode = $ErrorCode } {
                $Verdict = Get-EntraErrorVerdict -ErrorCode $ErrorCode

                $Verdict.IsError | Should -BeFalse
                $Verdict.Action | Should -Be 'None'
                $Verdict.IsTerminal | Should -BeFalse
            }
        }
    }

    Context 'The page reporting that it found no session to sign in silently with' {
        # AADSTS50058 is not a failed sign-in. Entra's page attempts a silent single sign-on when it
        # loads, and when the browser holds no session it leaves that result in $Config while
        # rendering the ordinary username prompt underneath. A cold browser profile always sees it -
        # a first sign-in, a -ForceAuthentication run, and every single run of the scheduled canary,
        # which is how it was found (issue #79). Treated as an error, it handed the sign-in to a
        # manual fallback before the username had even been typed.
        It 'Reports no error for <Description>' -TestCases @(
            @{ Description = 'the number itself'; ErrorCode = 50058 }
            @{ Description = 'the number as a string'; ErrorCode = '50058' }
            @{ Description = 'the AADSTS form'; ErrorCode = 'AADSTS50058' }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ ErrorCode = $ErrorCode } {
                $Verdict = Get-EntraErrorVerdict -ErrorCode $ErrorCode

                $Verdict.IsError | Should -BeFalse
                $Verdict.Action | Should -Be 'None'
                $Verdict.IsTerminal | Should -BeFalse
            }
        }

        It 'Does not hand the sign-in to the user over it' {
            # The point of the fix: the automation carries on and fills the username field that is
            # sitting on the page, instead of stepping aside from a page it could have driven.
            InModuleScope 'OmadaWeb.PS' {
                (Get-EntraErrorVerdict -ErrorCode 'AADSTS50058').Action | Should -Not -Be 'Manual'
            }
        }

        It 'Still treats a neighbouring code as an error, so the exemption is not a hole' {
            InModuleScope 'OmadaWeb.PS' {
                (Get-EntraErrorVerdict -ErrorCode '50059').IsError | Should -BeTrue
            }
        }
    }

    Context 'Failures that a retry cannot turn into a success' {
        # Every one of these ends the sign-in through Stop-OmadaLogin instead of opening another
        # browser window. 50126 is in this group on purpose: resubmitting a credential Entra ID has
        # just refused is what drives an account into smart lockout.
        It 'Stops the sign-in on <ErrorCode>' -TestCases @(
            @{ ErrorCode = '50126' }
            @{ ErrorCode = '50053' }
            @{ ErrorCode = '50055' }
            @{ ErrorCode = '53003' }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ ErrorCode = $ErrorCode } {
                $Verdict = Get-EntraErrorVerdict -ErrorCode $ErrorCode

                $Verdict.IsError | Should -BeTrue
                $Verdict.IsTerminal | Should -BeTrue
                $Verdict.Action | Should -Be 'Stop'
                $Verdict.Code | Should -Be ("AADSTS{0}" -f $ErrorCode)
                $Verdict.Reason | Should -Not -BeNullOrEmpty
            }
        }

        It 'Explains a Conditional Access block as one that will be refused every time' {
            InModuleScope 'OmadaWeb.PS' {
                (Get-EntraErrorVerdict -ErrorCode '53003').Reason | Should -BeLike '*Conditional Access*'
            }
        }

        It 'Explains that a wrong password is not sent again, to avoid smart lockout' {
            InModuleScope 'OmadaWeb.PS' {
                (Get-EntraErrorVerdict -ErrorCode '50126').Reason | Should -BeLike '*smart lockout*'
            }
        }
    }

    Context 'Failures the user can still resolve in the open browser window' {
        It 'Hands <ErrorCode> back to the user without ending the sign-in' -TestCases @(
            @{ ErrorCode = '50072' }
            @{ ErrorCode = '50074' }
            @{ ErrorCode = '50158' }
            @{ ErrorCode = '50076' }
            @{ ErrorCode = '50079' }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ ErrorCode = $ErrorCode } {
                $Verdict = Get-EntraErrorVerdict -ErrorCode $ErrorCode

                $Verdict.IsError | Should -BeTrue
                $Verdict.Action | Should -Be 'Manual'
                $Verdict.IsTerminal | Should -BeFalse
                $Verdict.Reason | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Account selection and session conditions' {
        # Issue #76. The whole 1600x family says one thing: Entra ID cannot settle on an account by
        # itself. None of them is a fault in this module and none of them is worth a bug report, so
        # the verdict has to name them rather than let them fall into the catch-all below.
        It 'Names <ErrorCode> instead of calling it unrecognized' -TestCases @(
            @{ ErrorCode = '16000' }
            @{ ErrorCode = '16001' }
            @{ ErrorCode = '16002' }
            @{ ErrorCode = '160021' }
            @{ ErrorCode = '16003' }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ ErrorCode = $ErrorCode } {
                $Verdict = Get-EntraErrorVerdict -ErrorCode $ErrorCode

                $Verdict.IsError | Should -BeTrue
                $Verdict.Action | Should -Be 'Manual'
                $Verdict.IsTerminal | Should -BeFalse
                $Verdict.IsRecognized | Should -BeTrue
                $Verdict.Reason | Should -Not -BeNullOrEmpty
                $Verdict.Reason | Should -Not -BeLike '*does not recognize*'
            }
        }

        It 'Sends the user to the browser window that is already open' {
            InModuleScope 'OmadaWeb.PS' {
                (Get-EntraErrorVerdict -ErrorCode '16000').Reason | Should -BeLike '*browser window*'
            }
        }

        It 'Reaches the same verdict from <Description>' -TestCases @(
            @{ Description = 'the number itself'; ErrorCode = 16000 }
            @{ Description = 'the number as a string'; ErrorCode = '16000' }
            @{ Description = 'the AADSTS form'; ErrorCode = 'AADSTS16000' }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ ErrorCode = $ErrorCode } {
                $Verdict = Get-EntraErrorVerdict -ErrorCode $ErrorCode

                $Verdict.Numeric | Should -Be 16000
                $Verdict.Code | Should -Be 'AADSTS16000'
                $Verdict.Action | Should -Be 'Manual'
                $Verdict.IsRecognized | Should -BeTrue
                $Verdict.Reason | Should -Not -BeLike '*does not recognize*'
            }
        }
    }

    Context 'Codes this module has never seen' {
        # Microsoft adds error codes, so the list above cannot be exhaustive. An unrecognized code
        # has to fail safe and name itself, not be treated as a healthy page.
        It 'Fails safe and names the code' {
            InModuleScope 'OmadaWeb.PS' {
                $Verdict = Get-EntraErrorVerdict -ErrorCode '90210'

                $Verdict.IsError | Should -BeTrue
                $Verdict.Action | Should -Be 'Manual'
                $Verdict.IsTerminal | Should -BeFalse
                $Verdict.Reason | Should -BeLike '*AADSTS90210*'
            }
        }

        It 'Marks the code as one it does not know' {
            InModuleScope 'OmadaWeb.PS' {
                # The fail-safe is what keeps an unknown code from being guessed at, and the flag is
                # what lets the handover still ask for a report. Weakening either would hide the
                # next code Microsoft adds.
                $Verdict = Get-EntraErrorVerdict -ErrorCode 'AADSTS99999'

                $Verdict.Action | Should -Be 'Manual'
                $Verdict.IsRecognized | Should -BeFalse
                $Verdict.Reason | Should -BeLike '*does not recognize*'
            }
        }
    }

    Context 'The shapes the page writes the code in' {
        It 'Reads the same failure from <ErrorCode>' -TestCases @(
            @{ ErrorCode = '53003' }
            @{ ErrorCode = 'AADSTS53003' }
            @{ ErrorCode = '  53003  ' }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ ErrorCode = $ErrorCode } {
                $Verdict = Get-EntraErrorVerdict -ErrorCode $ErrorCode

                $Verdict.Numeric | Should -Be 53003
                $Verdict.Action | Should -Be 'Stop'
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
