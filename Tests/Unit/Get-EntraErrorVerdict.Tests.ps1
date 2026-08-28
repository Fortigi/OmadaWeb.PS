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
