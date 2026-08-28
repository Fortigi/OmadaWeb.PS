param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Show-EntraApprovalNumber' -Tag 'Unit' {

    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            $Script:MfaRequestDisplayed = $false
            $Script:MfaWaitLastReported = $null
            $Script:MfaWaitReportInterval = 10
        }
    }

    Context 'Showing the number' {
        It 'Shows the number once and records that it has been shown' {
            InModuleScope 'OmadaWeb.PS' {
                Mock Get-Process { @() }
                Mock Write-Host {}

                Show-EntraApprovalNumber -Number '42' | Should -BeTrue

                $Script:MfaRequestDisplayed | Should -BeTrue
                Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like '*42*' }
            }
        }

        It 'Puts the number on the clipboard when Phone Link is running' {
            InModuleScope 'OmadaWeb.PS' {
                Mock Get-Process { @([PSCustomObject]@{ ProcessName = 'PhoneExperienceHost' }) }
                Mock Set-Clipboard {}
                Mock Write-Host {}

                Show-EntraApprovalNumber -Number '42' | Out-Null

                Should -Invoke Set-Clipboard -Times 1 -Exactly
                Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like '*clipboard*' }
            }
        }

        It 'Asks for the one process by name instead of enumerating every process' {
            # This runs on the WebView2 UI thread. Filtering the whole process table to answer a
            # yes/no question about a single process is work the timer does not need to do.
            InModuleScope 'OmadaWeb.PS' {
                Mock Get-Process { @() }
                Mock Write-Host {}

                Show-EntraApprovalNumber -Number '42' | Out-Null

                Should -Invoke Get-Process -Times 1 -Exactly -ParameterFilter { $Name -eq 'PhoneExperienceHost' }
            }
        }

        It 'Still shows the number when the clipboard cannot be set' {
            # The number is the one piece of information the user needs; a clipboard failure must
            # not cost them it.
            InModuleScope 'OmadaWeb.PS' {
                Mock Get-Process { @([PSCustomObject]@{ ProcessName = 'PhoneExperienceHost' }) }
                Mock Set-Clipboard { throw 'clipboard unavailable' }
                Mock Write-Host {}

                Show-EntraApprovalNumber -Number '42' | Should -BeTrue

                Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like '*42*' }
            }
        }

        It 'Does nothing when the page carried no number' {
            InModuleScope 'OmadaWeb.PS' {
                Mock Write-Host {}

                Show-EntraApprovalNumber -Number '' | Should -BeFalse
                Show-EntraApprovalNumber -Number $null | Should -BeFalse

                $Script:MfaRequestDisplayed | Should -BeFalse
                Should -Invoke Write-Host -Times 0 -Exactly
            }
        }
    }

    Context 'Waiting for the approval' {
        It 'Does not show the number again on every timer tick' {
            InModuleScope 'OmadaWeb.PS' {
                Mock Get-Process { @() }
                Mock Write-Host {}

                Show-EntraApprovalNumber -Number '42' | Out-Null
                Show-EntraApprovalNumber -Number '42' | Should -BeFalse
                Show-EntraApprovalNumber -Number '42' | Should -BeFalse

                Should -Invoke Write-Host -Times 1 -Exactly
            }
        }

        It 'Reports that it is still waiting, so a multi-minute wait does not look frozen' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:MfaRequestDisplayed = $true
                # Last reported longer ago than the interval, which is what a real wait produces
                # between two heartbeats.
                $Script:MfaWaitLastReported = [DateTime]::Now.AddSeconds(-($Script:MfaWaitReportInterval + 1))

                $Verbose = @(Show-EntraApprovalNumber -Number '42' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })

                ($Verbose -join "`n") | Should -BeLike '*Still waiting*42*'
            }
        }

        It 'Holds the heartbeat back until the interval has passed' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:MfaRequestDisplayed = $true
                $Script:MfaWaitLastReported = [DateTime]::Now

                $Verbose = @(Show-EntraApprovalNumber -Number '42' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })

                ($Verbose | Measure-Object).Count | Should -Be 0
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
