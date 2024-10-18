Properties {
    $Date = Get-Date
    $ModuleName = "OmadaWeb.PS"
    $ParentPath = (Get-Item -Path $PSScriptRoot -Verbose:$false).Parent.FullName
    $ModuleSource = Join-Path -Path $ParentPath -ChildPath 'src'
    $TestSource = Join-Path -Path $ParentPath -ChildPath 'tests'
    $OutputDir = Join-Path -Path $ParentPath -ChildPath 'output'
}


Task default -depends Analyze, Test, Build, ImportModule
Task DeployOnly -depends Build, Deploy

Task Analyze {

    $Profile = @{
        Severity     = @('Error', 'Warning')
        IncludeRules = '*'
        ExcludeRules = '*WriteHost', '*UseDeclaredVarsMoreThanAssignments*', '*AvoidUsingEmptyCatchBlock*', '*ReviewUnusedParameter*', '*UseShouldProcessForStateChangingFunctions*', '*UseSingularNouns*', '*AvoidOverwritingBuiltInCmdlets*', '*UseToExportFieldsInManifest*', '*UseProcessBlockForPipelineCommand*', '*ConvertToSecureStringWithPlainText*'
    }
    $saResults = Invoke-ScriptAnalyzer -Path $ModuleSource -Severity @('Error', 'Warning') -Recurse -Profile $Profile -Verbose:$false
    if ($saResults) {
        $saResults | Format-Table
        Write-Error -Message 'One or more Script Analyzer errors/warnings where found. Build cannot continue!'
    }
}

Task Test -depends Analyze {
}

Task Build -depends Test {

    $FormattingSettings = @{
        IncludeRules = @("PSPlaceOpenBrace", "PSUseConsistentIndentation", "PsAvoidUsingCmdletAliases", "PSUseConsistentWhitespace", "PSAlignAssignmentStatement", "PSPlaceCloseBrace")
        Rules        = @{
            PSPlaceOpenBrace           = @{
                Enable             = $true
                OnSameLine         = $true
                NewLineAfter       = $true
                IgnoreOneLineBlock = $true
            }
            PSUseConsistentIndentation = @{
                Enable = $true
            }
            PsAvoidUsingCmdletAliases  = @{
                Enable = $true
            }
            PSUseConsistentWhitespace  = @{
                Enable                                  = $false
                CheckInnerBrace                         = $true
                CheckOpenBrace                          = $false
                CheckOpenParen                          = $false
                CheckOperator                           = $true
                CheckPipe                               = $true
                CheckPipeForRedundantWhitespace         = $false
                CheckSeparator                          = $true
                CheckParameter                          = $true
                IgnoreAssignmentOperatorInsideHashTable = $false
            }
            PSAlignAssignmentStatement = @{
                Enable         = $true
                CheckHashtable = $true
            }
            PSPlaceCloseBrace          = @{
                Enable             = $true
                NoEmptyLineBefore  = $false
                IgnoreOneLineBlock = $true
                NewLineAfter       = $true
            }
        }
    }


    $OutputDirFile = Join-Path -Path $OutputDir -ChildPath ("{0}.psm1" -f $ModuleName)
    $ModuleContent = "#requires -Version 5.1`n`nWrite-Verbose ""Loading {0} Module""`n[boolean]`$Script:Connected = `$false`n`n" -f $ModuleName

    $PublicModules = @()
    $Public = @(Get-ChildItem -Path $ModuleSource\Public\*.ps1 -Recurse)
    $Private = @(Get-ChildItem -Path $ModuleSource\Private\*.ps1)

    Foreach ($import in $Private) {
        $Content = Get-Content $import.FullName -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*#requires' }
        $ModuleContent += $Content -join "`n"
        $ModuleContent += "`n`n"
    }

    Foreach ($import in $Public) {
        $Content = Get-Content $import.FullName -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*#requires' }
        $ModuleContent += $Content -join "`n"
        $ModuleContent += "`n`n"
        $PublicModules += $import.Basename
    }

    # Export all the functions
    $Content = "Export-ModuleMember -Function @(""{0}"") -Alias *`n`n" -f ($PublicModules -join '", "')
    $ModuleContent += $Content -join "`n`n"

    $ModuleContent = $ModuleContent -replace "`r?`n", "`r`n" | Invoke-Formatter -Settings $FormattingSettings
    Set-Content -Path $OutputDirFile -Encoding UTF8 -Force -Value $ModuleContent

    $ModulePsd1 = Import-PowerShellDataFile (Join-Path $ModuleSource -ChildPath ("{0}.psd1" -f $ModuleName))
    $ModulePsd1.FunctionsToExport = $PublicModules

    $ModulePsd1.Add("Path", (Join-Path $OutputDir -ChildPath ("{0}.psd1" -f $ModuleName)))

    try {
        $CurrentModulePsd1 = Import-PowerShellDataFile (Join-Path -Path $OutputDir -ChildPath ("{0}.psd1" -f $ModuleName))
    }
    catch {
        $CurrentModulePsd1 = $null
    }
    [version]$NewVersion = $Date.ToString('yyyy.MM.dd.001')
    if ($CurrentModulePsd1) {
        [version]$CurrentModuleVersion = $CurrentModulePsd1.ModuleVersion
        if ($CurrentModuleVersion -ge $NewVersion) {
            $NewVersion = [version]$CurrentModuleVersion
            $NewVersion = New-Object System.Version($NewVersion.Major, $NewVersion.Minor, $NewVersion.Build, ($NewVersion.Revision + 1))
        }
    }

    $ModulePsd1.ModuleVersion = $NewVersion

    New-ModuleManifest @Modulepsd1
    (Get-Content $($ModulePsd1.Path) -Raw) -replace "`r?`n", "`r`n" | Invoke-Formatter -Settings $FormattingSettings | Set-Content -Path $($ModulePsd1.Path) -Encoding UTF8 -Force
}

Task ImportModule -depends Build {
    $Test = Import-Module -name "$OutputDir\$ModuleName.psd1" -Force -PassThru
    if ($Test) {
        "Module loaded successfully" | Write-Verbose
        Remove-Module -name $Test.Name -Force
    }
    else {
        "Module failed to load" | Write-Error -ErrorAction Stop
    }
}




