param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'StrictMode' -Tag 'Unit' {

    Context 'Opt-in switch' {
        BeforeAll {
            $Script:PreviousStrictModeFlag = $Env:OMADAWEBPS_STRICTMODE
        }

        AfterAll {
            # Restored, and the module re-imported under it, so the files Pester runs after this one
            # see the same module state they would have seen had this file never run.
            $Env:OMADAWEBPS_STRICTMODE = $Script:PreviousStrictModeFlag
            Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
            Import-Module $ModulePath -Force -ErrorAction Stop
        }

        It 'Should run module code under StrictMode when OMADAWEBPS_STRICTMODE is 1' {
            $Env:OMADAWEBPS_STRICTMODE = "1"
            Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
            Import-Module $ModulePath -Force -ErrorAction Stop

            InModuleScope 'OmadaWeb.PS' {
                # Built and invoked inside the module's session state, so it inherits whatever
                # StrictMode the module set on itself - which is the thing under test. A read of an
                # unset variable is an error only when StrictMode is on.
                { & { if ($NeverAssignedAnywhereInThisModule) { "reached" } } } | Should -Throw
            }
        }

        It 'Should leave module code unstrict when OMADAWEBPS_STRICTMODE is not set' {
            $Env:OMADAWEBPS_STRICTMODE = $null
            Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
            Import-Module $ModulePath -Force -ErrorAction Stop

            InModuleScope 'OmadaWeb.PS' {
                { & { if ($NeverAssignedAnywhereInThisModule) { "reached" } } } | Should -Not -Throw
            }
        }
    }

    Context 'No unassigned variable reads in the login flows' {
        BeforeDiscovery {
            # The browser login flows cannot be executed by a unit test - they drive a real Edge or
            # WebView2 window - so running the suite under StrictMode does not cover them the way it
            # covers everything else. This walks their syntax tree instead, which is what caught the
            # reads that made this file necessary.
            $Script:LoginFlowFiles = @(
                @{ File = 'Get-DataFromWebDriver.ps1'; Skip = $false; Because = '' }
                # Invoke-WebView2MicrosoftLogin.ps1 still reads an unassigned $MfaElementIds on line
                # 789. The fix is already on the branch of PR #67, which rewrites this file, so it is
                # not duplicated here - two edits to the same 800-line rewrite would only collide.
                # Flip Skip to $false once #67 has merged; the check itself is ready for it.
                @{ File = 'Invoke-WebView2MicrosoftLogin.ps1'; Skip = $true; Because = 'fixed by PR #67, which rewrites this file' }
            )
        }

        It 'Should not read an unassigned variable in <File>' -ForEach $Script:LoginFlowFiles {
            if ($Skip) {
                Set-ItResult -Skipped -Because $Because
            }

            $SourcePath = Join-Path (Split-Path (Split-Path $PSScriptRoot)) -ChildPath ('OmadaWeb.PS\Private\{0}' -f $File)
            Test-Path $SourcePath -PathType Leaf | Should -BeTrue -Because "$SourcePath should exist"

            $Tokens = $null
            $ParseErrors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($SourcePath, [ref]$Tokens, [ref]$ParseErrors)
            $ParseErrors | Should -BeNullOrEmpty

            # Anything the file assigns, binds as a parameter, or walks with foreach counts as defined.
            $Assigned = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

            $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true) |
                ForEach-Object {
                    $Target = $_.Left
                    if ($Target -is [System.Management.Automation.Language.ConvertExpressionAst]) {
                        $Target = $Target.Child
                    }

                    if ($Target -is [System.Management.Automation.Language.VariableExpressionAst]) {
                        $null = $Assigned.Add($Target.VariablePath.UserPath)
                    }
                }

            $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true) |
                ForEach-Object { $null = $Assigned.Add($_.Name.VariablePath.UserPath) }

            # An unqualified read also finds module scope, so every $Script:-scoped name the module
            # assigns anywhere counts as defined here - $WebView2 in one file is the $Script:WebView2
            # another file assigns. Without this the check would flag ordinary module state.
            Get-ChildItem -Path (Join-Path (Split-Path (Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS') -Recurse -Include '*.ps1', '*.psm1' |
                ForEach-Object {
                    $ModuleFileAst = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null)
                    $ModuleFileAst.FindAll({ $args[0] -is [System.Management.Automation.Language.VariableExpressionAst] }, $true) |
                        Where-Object { $_.VariablePath.IsScript -or $_.VariablePath.IsGlobal } |
                        ForEach-Object { $null = $Assigned.Add(($_.VariablePath.UserPath -split ':', 2)[-1]) }
                }

            $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ForEachStatementAst] }, $true) |
                ForEach-Object { $null = $Assigned.Add($_.Variable.VariablePath.UserPath) }

            # Bound by the runtime rather than by this file.
            $Automatic = @(
                '_', 'PSItem', 'true', 'false', 'null', 'args', 'input', 'this', '$', '^', '?',
                'MyInvocation', 'PSCmdlet', 'PSBoundParameters', 'PSScriptRoot', 'PSCommandPath',
                'PSVersionTable', 'ErrorActionPreference', 'VerbosePreference', 'WarningPreference',
                'InformationPreference', 'DebugPreference', 'ProgressPreference', 'Error', 'Host',
                'PWD', 'Env', 'IsWindows', 'StackTrace', 'LASTEXITCODE', 'PID'
            )
            $Automatic | ForEach-Object { $null = $Assigned.Add($_) }

            $Unassigned = $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.VariableExpressionAst] }, $true) |
                Where-Object {
                    # Only unqualified names are this file's own business: a $Script:- or $Global:-
                    # scoped name is module state assigned elsewhere, and $Env:/$Using: are not
                    # variables this file could assign at all.
                    $_.VariablePath.IsUnqualified -and
                    -not $Assigned.Contains($_.VariablePath.UserPath)
                } |
                ForEach-Object { '${0} (line {1})' -f $_.VariablePath.UserPath, $_.Extent.StartLineNumber } |
                Select-Object -Unique

            $Unassigned | Should -BeNullOrEmpty -Because ("{0} reads these without ever assigning them" -f $File)
        }
    }
}
