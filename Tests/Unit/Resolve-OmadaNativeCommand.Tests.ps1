param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

# Resolving the native cmdlet had two ways to fail and handled one. Get-Command throws when nothing
# matches the name, which was caught and recovered from by importing the module; but it returns
# nothing at all, without error, when the name resolves and the module named by the version filter
# is not loaded as a module in this session state. A bare runspace on Windows PowerShell 5.1 is in
# exactly that state - which is the runspace a worker created with [powershell]::Create() gets, and
# so the one Import-OmadaSession exists to serve. The silent miss left $CommandInfo null and the
# request died reading .Source off it under StrictMode.

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Resolve-OmadaNativeCommand' -Tag 'Unit' {
    BeforeEach {
        # The same specification Invoke-OmadaRequest builds, including the edition-dependent version:
        # Windows PowerShell's Microsoft.PowerShell.Utility is 3.1.0.0, PowerShell 7's is 7.0.0.
        InModuleScope 'OmadaWeb.PS' {
            $Script:TestModuleSpec = @{
                ModuleName    = "Microsoft.PowerShell.Utility"
                Guid          = [guid]"1da87e53-152b-403e-98dc-74d7b4d63d59"
                ModuleVersion = [Version]"7.0.0"
            }
            if ($PSVersionTable.PSEdition -eq "Desktop") {
                $Script:TestModuleSpec.ModuleVersion = [Version]"3.1.0.0"
            }
        }
    }

    Context 'The command resolves straight away' {
        It 'Should return the native cmdlet' {
            InModuleScope 'OmadaWeb.PS' {
                $Command = Resolve-OmadaNativeCommand -Name 'Invoke-RestMethod' -FullyQualifiedModule $Script:TestModuleSpec

                $Command | Should -Not -BeNullOrEmpty
                $Command.Name | Should -Be 'Invoke-RestMethod'
                $Command.Source | Should -Be 'Microsoft.PowerShell.Utility'
            }
        }

        It 'Should return a single command, never an array' {
            # The caller reads .Source, .Name and .Version off the result and hands it to
            # Invoke-OmadaRetryableRequest. An array would satisfy none of that, and under StrictMode
            # reading .Source off one is the same failure this function exists to prevent.
            InModuleScope 'OmadaWeb.PS' {
                $Command = Resolve-OmadaNativeCommand -Name 'Invoke-WebRequest' -FullyQualifiedModule $Script:TestModuleSpec

                @($Command).Count | Should -Be 1
                $Command | Should -BeOfType [System.Management.Automation.CommandInfo]
            }
        }
    }

    Context 'A bare runspace' {
        It 'Should resolve the cmdlet where the qualified lookup cannot match at all' {
            # The condition itself, rather than a mocked imitation of it: a real runspace created the
            # way a background worker creates one. There the native cmdlets come from the initial
            # session state, so Get-Module returns nothing for Microsoft.PowerShell.Utility and every
            # -FullyQualifiedModule lookup yields nothing - silently, which is what defeated the old
            # catch-based recovery. This is the test that would have caught the Windows PowerShell
            # 5.1 failure in PR validation.
            $FunctionPath = Join-Path (Split-Path (Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\Private\Resolve-OmadaNativeCommand.ps1'

            $PowerShell = [powershell]::Create()
            try {
                $null = $PowerShell.AddScript({
                        param($FunctionPath)
                        Set-StrictMode -Version Latest
                        . $FunctionPath

                        $Spec = @{
                            ModuleName    = "Microsoft.PowerShell.Utility"
                            Guid          = [guid]"1da87e53-152b-403e-98dc-74d7b4d63d59"
                            ModuleVersion = [Version]"7.0.0"
                        }
                        if ($PSVersionTable.PSEdition -eq "Desktop") {
                            $Spec.ModuleVersion = [Version]"3.1.0.0"
                        }

                        $Report = @{ QualifiedLookupCount = @(Get-Command Invoke-RestMethod -FullyQualifiedModule $Spec -ErrorAction SilentlyContinue).Count }
                        try {
                            $Command = Resolve-OmadaNativeCommand -Name 'Invoke-RestMethod' -FullyQualifiedModule $Spec -ErrorAction Stop
                            $Report.Name = [string]$Command.Name
                            $Report.Source = [string]$Command.Source
                        }
                        catch {
                            $Report.Failure = "{0}: {1}" -f $PSItem.FullyQualifiedErrorId, $PSItem.Exception.Message
                        }

                        [PSCustomObject]$Report
                    }).AddArgument($FunctionPath)

                $Result = @($PowerShell.Invoke()) | Select-Object -Last 1
            }
            finally {
                $PowerShell.Dispose()
            }

            $Result | Should -Not -BeNullOrEmpty

            # Whether the qualified lookup matches in a fresh runspace depends on the host and the
            # edition - it does not on Windows PowerShell, where the cmdlets come from the initial
            # session state and report a version below the floor the specification asks for. That is
            # the point: resolution has to succeed either way, so the count is reported rather than
            # asserted. On the Windows PowerShell leg of PR validation this count is 0, and the
            # assertions below are then reached only through the module-scoped fallback.
            $Result.PSObject.Properties['Failure'] | Should -BeNullOrEmpty -Because ("the qualified lookup matched {0} command(s) and the worker reported: {1}" -f $Result.QualifiedLookupCount, $Result.Failure)
            $Result.Name | Should -Be 'Invoke-RestMethod'
            $Result.Source | Should -Be 'Microsoft.PowerShell.Utility'
        }
    }

    Context 'The first lookup produces nothing' {
        It 'Should import the module and ask again when Get-Command returns nothing silently' {
            # The regression itself: a return of nothing, with no error raised, which the old
            # catch-based recovery could never see.
            InModuleScope 'OmadaWeb.PS' {
                $Script:ResolveAttempt = 0
                Mock Get-Command {
                    $Script:ResolveAttempt++
                    if ($Script:ResolveAttempt -eq 1) {
                        return
                    }

                    return [PSCustomObject]@{ Name = 'Invoke-RestMethod'; Source = 'Microsoft.PowerShell.Utility'; Version = [Version]'7.0.0' }
                }
                Mock Import-Module {}

                $Command = Resolve-OmadaNativeCommand -Name 'Invoke-RestMethod' -FullyQualifiedModule $Script:TestModuleSpec

                $Command.Name | Should -Be 'Invoke-RestMethod'
                Should -Invoke Import-Module -Times 1 -Exactly
                $Script:ResolveAttempt | Should -Be 2
            }
        }

        It 'Should import the module and ask again when Get-Command throws' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:ResolveAttempt = 0
                Mock Get-Command {
                    $Script:ResolveAttempt++
                    if ($Script:ResolveAttempt -eq 1) {
                        throw "no such command"
                    }

                    return [PSCustomObject]@{ Name = 'Invoke-RestMethod'; Source = 'Microsoft.PowerShell.Utility'; Version = [Version]'7.0.0' }
                }
                Mock Import-Module {}

                $Command = Resolve-OmadaNativeCommand -Name 'Invoke-RestMethod' -FullyQualifiedModule $Script:TestModuleSpec

                $Command.Name | Should -Be 'Invoke-RestMethod'
                Should -Invoke Import-Module -Times 1 -Exactly
            }
        }

        It 'Should fall back to a module-scoped lookup when the qualified one never matches' {
            # The bare-runspace case. There the native cmdlets come from the initial session state
            # rather than an imported module, so no -FullyQualifiedModule lookup can ever match -
            # and on Windows PowerShell the cmdlet reports 3.0.0.0, under the 3.1.0.0 the spec asks
            # for, so the version floor is unsatisfiable there however the module is loaded.
            InModuleScope 'OmadaWeb.PS' {
                Mock Import-Module {}
                Mock Get-Command {
                    # Only the module-scoped form produces anything, exactly as in a bare runspace.
                    if ($null -ne $FullyQualifiedModule) {
                        return
                    }

                    return [PSCustomObject]@{
                        Name        = 'Invoke-RestMethod'
                        Source      = 'Microsoft.PowerShell.Utility'
                        Version     = [Version]'3.0.0.0'
                        CommandType = 'Cmdlet'
                    }
                }

                $Command = Resolve-OmadaNativeCommand -Name 'Invoke-RestMethod' -FullyQualifiedModule $Script:TestModuleSpec

                $Command.Name | Should -Be 'Invoke-RestMethod'
                $Command.Source | Should -Be 'Microsoft.PowerShell.Utility'

                # Still scoped to the module and still restricted to cmdlets, which is what stops a
                # function the caller defined called Invoke-RestMethod from taking the call.
                Should -Invoke Get-Command -ParameterFilter {
                    $Module -contains 'Microsoft.PowerShell.Utility' -and $CommandType -contains 'Cmdlet'
                } -Times 1 -Exactly
            }
        }

        It 'Should not accept a command from somewhere other than the module asked for' {
            InModuleScope 'OmadaWeb.PS' {
                Mock Import-Module {}
                Mock Get-Command {
                    if ($null -ne $FullyQualifiedModule) {
                        return
                    }

                    return [PSCustomObject]@{
                        Name        = 'Invoke-RestMethod'
                        Source      = 'Some.Other.Module'
                        Version     = [Version]'1.0.0.0'
                        CommandType = 'Cmdlet'
                    }
                }

                { Resolve-OmadaNativeCommand -Name 'Invoke-RestMethod' -FullyQualifiedModule $Script:TestModuleSpec -ErrorAction Stop } |
                    Should -Throw -ExpectedMessage "*Could not resolve 'Invoke-RestMethod'*"
            }
        }

        It 'Should fail with a message naming the command when it cannot be resolved at all' {
            # Better than the StrictMode property error the caller used to raise, which said only
            # that 'Source' was missing and nothing about a module that was never imported.
            InModuleScope 'OmadaWeb.PS' {
                Mock Get-Command { return }
                Mock Import-Module {}

                { Resolve-OmadaNativeCommand -Name 'Invoke-RestMethod' -FullyQualifiedModule $Script:TestModuleSpec -ErrorAction Stop } |
                    Should -Throw -ExpectedMessage "*Could not resolve 'Invoke-RestMethod'*"
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
