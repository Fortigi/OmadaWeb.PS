param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Test-SignInAccountRecovery' -Tag 'Unit' {

    Context 'The one case worth another window' {
        It 'Offers the account picker when the tenant did not know the account the browser chose' {
            InModuleScope 'OmadaWeb.PS' {
                Test-SignInAccountRecovery -Category 'WrongAccount' -UserInteractive $true | Should -BeTrue
            }
        }
    }

    Context 'Refusals another account cannot answer' {
        It 'Does not offer it for any other category' {
            InModuleScope 'OmadaWeb.PS' {
                foreach ($Category in @('Authorization', 'AppRegistration', 'IdentityProvider', 'Unknown', 'None', '')) {
                    Test-SignInAccountRecovery -Category $Category -UserInteractive $true |
                        Should -BeFalse -Because "'$Category' answers every account the same way"
                }
            }
        }
    }

    Context 'Refusals the user already answered' {
        It 'Does not overrule an account the caller named' {
            # The picker asks exactly the question -UserName already answered, and the account it
            # named is the one the tenant rejected.
            InModuleScope 'OmadaWeb.PS' {
                Test-SignInAccountRecovery -Category 'WrongAccount' -UserName 'mark@example.com' -UserInteractive $true | Should -BeFalse
            }
        }

        It 'Offers it once and never twice' {
            # A second refusal is the tenant repeating itself, and a window that keeps reappearing is
            # worse than an error message.
            InModuleScope 'OmadaWeb.PS' {
                Test-SignInAccountRecovery -Category 'WrongAccount' -RecoveryAttempted -UserInteractive $true | Should -BeFalse
            }
        }
    }

    Context 'Nobody at the keyboard' {
        It 'Does not open a picker in a session with no interactive desktop' {
            # A scheduled task would hang on a window nobody will ever click, where it used to fail
            # with a message that says what is wrong.
            InModuleScope 'OmadaWeb.PS' {
                Test-SignInAccountRecovery -Category 'WrongAccount' -UserInteractive $false | Should -BeFalse
            }
        }
    }
}
