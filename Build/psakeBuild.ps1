Properties {
    $Version = $BuildVersion
    $Date = Get-Date
    $ModuleName = "OmadaWeb.PS"
    $ParentPath = (Get-Item -Path $PSScriptRoot -Verbose:$false).Parent.FullName
    $ModuleSource = Join-Path -Path $ParentPath -ChildPath 'OmadaWeb.PS'
    $TestSource = Join-Path -Path $ParentPath -ChildPath 'tests'
    $OutputDir = Join-Path -Path $ParentPath -ChildPath 'output\OmadaWeb.PS'
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}


Task default -depends Analyze, Test, Build, ImportModule
Task DeployOnly -depends Build, Deploy

Task Analyze {

    $Profile = @{
        Severity     = @('Error', 'Warning')
        IncludeRules = '*'
        ExcludeRules = '*WriteHost', '*AvoidUsingEmptyCatchBlock*', '*UseShouldProcessForStateChangingFunctions*', '*AvoidOverwritingBuiltInCmdlets*', '*UseToExportFieldsInManifest*', '*UseProcessBlockForPipelineCommand*', '*ConvertToSecureStringWithPlainText*'
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

    function New-HeaderRow {
        PARAM(
            [string]$Text,
            [int]$Length = 100,
            [char]$BeginChar = "#",
            [char]$FillChar = " ",
            [char]$EndChar = "#"
        )
        $HeaderRow = $null
        $HeaderRow = "{0}{1}" -f $BeginChar, $FillChar
        $HeaderRow += $Text

        do {
            $HeaderRow += $FillChar
        }
        until ($HeaderRow.Length -gt ($Length - 1))
        $HeaderRow += "{0}`n" -f $EndChar
        return $HeaderRow

    }
    $ModulePsd1 = Import-PowerShellDataFile (Join-Path $ModuleSource -ChildPath ("{0}.psd1" -f $ModuleName))
    $ModulePsd1.FunctionsToExport = $PublicModules

    $ModulePsd1.Add("Path", (Join-Path $OutputDir -ChildPath ("{0}.psd1" -f $ModuleName)))

    try {
        $CurrentModulePsd1 = Import-PowerShellDataFile (Join-Path -Path $OutputDir -ChildPath ("{0}.psd1" -f $ModuleName))
    }
    catch {
        $CurrentModulePsd1 = $null
    }

    if (![String]::IsNullOrWhiteSpace($Version)) {
        [version]$NewVersion = "{0}" -f $Version
    }
    else {
        [version]$NewVersion = $Date.ToString('yyyy.MM.dd.001')
        if ($CurrentModulePsd1) {
            [version]$CurrentModuleVersion = $CurrentModulePsd1.ModuleVersion
            if ($CurrentModuleVersion -ge $NewVersion) {
                $NewVersion = [version]$CurrentModuleVersion
                $NewVersion = New-Object System.Version($NewVersion.Major, $NewVersion.Minor, $NewVersion.Build, ($NewVersion.Revision + 1))
            }
        }
    }

    $ModulePsd1.ModuleVersion = $NewVersion

    New-ModuleManifest @Modulepsd1
    (Get-Content $($ModulePsd1.Path) -Raw) -replace "`r?`n", "`r`n"  | Invoke-Formatter -Settings $FormattingSettings | Set-Content -Path $($ModulePsd1.Path) -Encoding UTF8 -Force


    $Length = 150
    $ModuleContent = $null
    $ModuleContent = New-HeaderRow -Text "" -Length $Length -FillChar "#"
    $ModuleContent += New-HeaderRow -Text  "WARNING: DO NOT EDIT THIS FILE AS IT IS GENERATED AND WILL BE OVERWRITTEN ON THE NEXT UPDATE!" -Length $Length -FillChar " "
    $ModuleContent += New-HeaderRow -Text  "" -Length $Length -FillChar " "
    $ModuleContent += New-HeaderRow -Text  ('Generated via psake on: {0}' -f $Date.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")) -Length $Length -FillChar " "
    $ModuleContent += New-HeaderRow -Text  ("Version: {0}" -f $NewVersion.ToString()) -Length $Length -FillChar " "
    $ModuleContent += New-HeaderRow -Text  ("Copyright Fortigi (C) {0}" -f $Date.ToString("yyyy")) -Length $Length -FillChar " "
    $ModuleContent += New-HeaderRow -Text  "" -Length $Length -FillChar "#"
    $ModuleContent += "`n`n"

    $OutputDirFile = Join-Path -Path $OutputDir -ChildPath ("{0}.psm1" -f $ModuleName)

    $RegionName = "exclude"
    $ScriptContent = Get-Content -Path $ModuleSource\OmadaWeb.PS.psm1 -Encoding UTF8 -ErrorAction Stop
    $ExcludeRegion = $false
    foreach ($Line in $ScriptContent) {
        if ($Line -match "#region\s+$RegionName") {
            $ExcludeRegion = $true
            continue
        }
        elseif ($Line -match "#endregion") {
            if ($ExcludeRegion) {
                $ExcludeRegion = $false
                break
            }
        }
        if (!$ExcludeRegion) {
            $ModuleContent += ($Line | Where-Object { $_ -notmatch '^\s*#' }) + "`n"
        }
        elseif ($ExcludeRegion) {
            $PublicModules = @()
            $Public = @(Get-ChildItem -Path $ModuleSource\Public\*.ps1 -Recurse)
            $Private = @(Get-ChildItem -Path $ModuleSource\Private\*.ps1)

            $ModuleContent += "#region public functions`n"
            Foreach ($import in $Public) {
                $Content = Get-Content $import.FullName -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*#requires' -and $_ -notmatch '^\s*#' }
                $ModuleContent += $Content.Trim() -join "`n"
                $ModuleContent += "`n`n"
                $PublicModules += $import.Basename
            }
            $ModuleContent += "#endregion`n`n#region private functions`n"
            Foreach ($import in $Private) {
                $Content = Get-Content $import.FullName -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*#requires' -and $_ -notmatch '^\s*#' }
                $ModuleContent += $Content.Trim() -join "`n"
                $ModuleContent += "`n`n"
            }
            $ModuleContent += "#endregion`n`n"

            # Export all the functions
            $Content = "Export-ModuleMember -Function @(""{0}"") -Alias *`n`n" -f ($PublicModules -join '", "')
            $ModuleContent += $Content -join "`n`n"
        }
    }

    $ModuleContent = $ModuleContent -replace "`r?`n", "`r`n" | Invoke-Formatter -Settings $FormattingSettings
    $ModuleContent | Out-File -Path $OutputDirFile -Encoding UTF8 -Force

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