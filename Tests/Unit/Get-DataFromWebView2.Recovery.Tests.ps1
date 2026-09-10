param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Recovering a sign-in that was refused for the wrong account' -Tag 'Unit' {

    BeforeAll {
        InModuleScope 'OmadaWeb.PS' {
            # A refusal shaped exactly as Stop-OmadaLogin records one, without a browser having to
            # produce it.
            function Script:New-TestAbortReason {
                param([string]$Category = 'WrongAccount')

                return [PSCustomObject]@{
                    Message  = "AADSTS50178: User account does not exist in tenant 'Example productie'."
                    Code     = 'AADSTS50178'
                    Reason   = 'The account that signed in is not known in the tenant the Omada application is registered in.'
                    Url      = 'https://example.omada.cloud/logon.aspx'
                    Engine   = 'WebView2'
                    Category = $Category
                    Detail   = [PSCustomObject]@{ HasDetail = $true; ResourceTenant = 'Example productie' }
                }
            }
        }
    }

    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            # The window itself is the one thing these tests do not exercise: the driver's decisions
            # are what is under test, and they are all taken between windows.
            Mock Install-WebView2 { $true }
            Mock Add-ReflectionAssembly {}
            Mock Reset-LoginAutomationState {}

            $Script:TestWindowCount = 0
            $Script:TestSelectAccountPerWindow = @()
        }
    }

    It 'Opens one more window with the account picker, and signs in with what the user chooses' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Test-SignInAccountRecovery { $true }
            Mock Start-WebView2Login {
                $Script:TestWindowCount++
                $Script:TestSelectAccountPerWindow += $Script:CurrentWebView2Session.SelectAccount

                if ($Script:TestWindowCount -eq 1) {
                    # The first window comes back refused, exactly as a real one does.
                    $Script:LoginAbortReason = New-TestAbortReason
                    return
                }

                $Script:CurrentWebView2Session.AuthCookie = [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'cookie-value'; domain = 'localhost' }
            }

            $SessionContext = Get-OmadaSessionContext -Key 'unit-test-recovery-succeeds'
            $SessionContext.BaseUrl = 'http://localhost:19000/'
            $SessionContext.AuthCookie = $null

            Get-DataFromWebView2 -SessionContext $SessionContext -WarningAction SilentlyContinue

            $Script:TestWindowCount | Should -Be 2
            $SessionContext.AuthCookie.Value | Should -Be 'cookie-value'

            # The first window let the browser choose, the second asked. That is the entire repair.
            $Script:TestSelectAccountPerWindow[0] | Should -BeFalse
            $Script:TestSelectAccountPerWindow[1] | Should -BeTrue
        }
    }

    It 'Leaves the account picker off the session once the call is over' {
        # It belongs to the recovery, not to the session: every later sign-in would otherwise stop
        # and ask, including the ones that were working all along.
        InModuleScope 'OmadaWeb.PS' {
            Mock Test-SignInAccountRecovery { $true }
            Mock Start-WebView2Login {
                $Script:TestWindowCount++
                if ($Script:TestWindowCount -eq 1) {
                    $Script:LoginAbortReason = New-TestAbortReason
                    return
                }
                $Script:CurrentWebView2Session.AuthCookie = [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'cookie-value'; domain = 'localhost' }
            }

            $SessionContext = Get-OmadaSessionContext -Key 'unit-test-recovery-restores'
            $SessionContext.BaseUrl = 'http://localhost:19000/'
            $SessionContext.AuthCookie = $null

            Get-DataFromWebView2 -SessionContext $SessionContext -WarningAction SilentlyContinue

            $SessionContext.SelectAccount | Should -BeFalse
        }
    }

    It 'Keeps a picker the caller asked for' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Test-SignInAccountRecovery { $true }
            Mock Start-WebView2Login {
                $Script:TestWindowCount++
                $Script:CurrentWebView2Session.AuthCookie = [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'cookie-value'; domain = 'localhost' }
            }

            $SessionContext = Get-OmadaSessionContext -Key 'unit-test-recovery-keeps-caller-choice'
            $SessionContext.BaseUrl = 'http://localhost:19000/'
            $SessionContext.AuthCookie = $null
            $SessionContext.SelectAccount = $true

            Get-DataFromWebView2 -SessionContext $SessionContext -WarningAction SilentlyContinue

            $SessionContext.SelectAccount | Should -BeTrue
        }
    }

    It 'Stops after the second refusal instead of opening a third window' {
        InModuleScope 'OmadaWeb.PS' {
            # The real rule refuses a second attempt itself; this mock answers by whether one has
            # been recorded, so the driver's own bookkeeping is what decides the outcome.
            Mock Test-SignInAccountRecovery { -not $RecoveryAttempted }
            Mock Start-WebView2Login {
                $Script:TestWindowCount++
                $Script:LoginAbortReason = New-TestAbortReason
            }

            $SessionContext = Get-OmadaSessionContext -Key 'unit-test-recovery-gives-up'
            $SessionContext.BaseUrl = 'http://localhost:19000/'
            $SessionContext.AuthCookie = $null

            { Get-DataFromWebView2 -SessionContext $SessionContext -WarningAction SilentlyContinue -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*does not exist in tenant*'

            $Script:TestWindowCount | Should -Be 2
        }
    }

    It 'Does not open a second window for a refusal another account cannot answer' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Test-SignInAccountRecovery { $false }
            Mock Start-WebView2Login {
                $Script:TestWindowCount++
                $Script:LoginAbortReason = New-TestAbortReason -Category 'AppRegistration'
            }

            $SessionContext = Get-OmadaSessionContext -Key 'unit-test-recovery-not-offered'
            $SessionContext.BaseUrl = 'http://localhost:19000/'
            $SessionContext.AuthCookie = $null

            { Get-DataFromWebView2 -SessionContext $SessionContext -WarningAction SilentlyContinue -ErrorAction Stop } | Should -Throw

            $Script:TestWindowCount | Should -Be 1
        }
    }
}
