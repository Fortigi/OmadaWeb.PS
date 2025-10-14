Properties {
    $Version = $BuildVersion
    $Date = Get-Date
    $ModuleName = "OmadaWeb.PS"
    $ParentPath = (Get-Item -Path $PSScriptRoot -Verbose:$false).Parent.FullName
    $ModuleSource = Join-Path -Path $ParentPath -ChildPath 'OmadaWeb.PS'
    $TestSource = Join-Path -Path $ParentPath -ChildPath 'tests'
    $OutputDir = Join-Path -Path $ParentPath -ChildPath 'buildoutput\OmadaWeb.PS'
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
        Write-Error -Message 'One or more Script Analyzer errors/warnings where found. Build cannot continue!' -ErrorAction "Stop"
    }
}

Task Test -depends Analyze {
    $Tests = Get-ChildItem ..\Tests -Filter *.Tests.ps1 -Recurse
    if ($Tests.Count -eq 0) {
        'No tests found' | Write-Warning
    }
    foreach ($Test in $Tests) {
        "{0} - Running tests from file: {1}" -f $MyInvocation.MyCommand, $Test.FullName | Write-Host -ForegroundColor Magenta
        . $Test.FullName
    }
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
        param(
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


    try {
        $CurrentModulePsd1 = Import-PowerShellDataFile (Join-Path -Path $OutputDir -ChildPath ("{0}.psd1" -f $ModuleName))
    }
    catch {
        $CurrentModulePsd1 = $null
    }

    if (![String]::IsNullOrWhiteSpace($Version)) {
        [System.Version]$NewVersion = "{0}" -f $Version
    }
    else {
        [System.Version]$NewVersion = $Date.ToString('yyyy.MM.dd.001')
        if ($CurrentModulePsd1) {
            [System.Version]$CurrentModuleVersion = $CurrentModulePsd1.ModuleVersion
            if ($CurrentModuleVersion -ge $NewVersion) {
                $NewVersion = [System.Version]$CurrentModuleVersion
                $NewVersion = New-Object System.Version($NewVersion.Major, $NewVersion.Minor, $NewVersion.Build, ($NewVersion.Revision + 1))
            }
        }
    }

    $ModulePsd1.ModuleVersion = $NewVersion
    $ModulePsd1.Copyright = $ModulePsd1.Copyright -f $Date.ToString("yyyy")

    #Work-around for the bug in New-ModuleManifest that breaks the PrivateData key (Source: https://github.com/PowerShell/PowerShell/issues/5922)
    $PrivateData = $ModulePsd1.PrivateData | ConvertTo-Json | ConvertFrom-Json -AsHashtable
    $ModulePsd1.Remove("PrivateData")

    $SerializedContent = $PrivateData.GetEnumerator() | ForEach-Object {
        if ($_ -is [System.Collections.DictionaryEntry]) {
            $String = "$($_.Key) = @{"
            if ($_.Value -is [System.Collections.Hashtable]) {
                # Serialize nested hashtables into a string
                $_.Value.GetEnumerator() | ForEach-Object {
                    $String += "`n"
                    if (($_.Value | Measure-Object).Count -gt 1) {
                        $String += "{0} = @({1})" -f $_.Key, (($_.Value | ForEach-Object { "`"{0}`"" -f $_ }) -join ",")
                    }
                    else {
                        $String += "{0} = `"{1}`"" -f $($_.Key) , $($_.Value)
                    }
                }
                return $String
            }
        }
    }

    $ModulePsd1Path = (Join-Path $OutputDir -ChildPath ("{0}.psd1" -f $ModuleName))
    New-ModuleManifest -Path $ModulePsd1Path @ModulePsd1
    (Get-Content -Path $ModulePsd1Path) -replace 'PSData = @{', $SerializedContent | Set-Content -Path $ModulePsd1Path -Encoding UTF8 -Force

    #    New-ModuleManifest @Modulepsd1
    "Module psd1 output file: {0}" -f $($ModulePsd1Path) | Write-Host -ForegroundColor Magenta
    (Get-Content $($ModulePsd1Path) -Raw) -replace "`r?`n", "`r`n" | Invoke-Formatter -Settings $FormattingSettings | Set-Content -Path $($ModulePsd1Path) -Encoding UTF8 -Force

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
    $FunctionsAdded = $false
    foreach ($Line in $ScriptContent) {
        if ($Line -match "#region\s+$RegionName") {
            $ExcludeRegion = $true
            continue
        }
        elseif ($Line -match "#endregion") {
            if ($ExcludeRegion) {
                $ExcludeRegion = $false
                #break
            }
        }
        if (!$ExcludeRegion) {
            $ModuleContent += ($Line | Where-Object { $_ -notmatch '^\s*#' }) + "`n"
        }
        elseif ($ExcludeRegion -and !$FunctionsAdded) {
            "Adding functions" | Write-Host -ForegroundColor Magenta
            $PublicModules = @()
            $Public = @(Get-ChildItem -Path $ModuleSource\Public\*.ps1 -Recurse)
            $Private = @(Get-ChildItem -Path $ModuleSource\Private\*.ps1)

            $ModuleContent += "#region public functions`n"
            foreach ($import in $Public) {
                $Content = Get-Content $import.FullName -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*#requires' -and $_ -notmatch '^\s*#' }
                $ModuleContent += $Content.Trim() -join "`n"
                $ModuleContent += "`n`n"
                $PublicModules += $import.Basename
            }
            $ModuleContent += "#endregion`n`n#region private functions`n"
            foreach ($import in $Private) {
                $Content = Get-Content $import.FullName -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*#requires' -and $_ -notmatch '^\s*#' }
                $ModuleContent += $Content.Trim() -join "`n"
                $ModuleContent += "`n`n"
            }
            $ModuleContent += "#endregion`n`n"
            $FunctionsAdded = $true
        }
    }

    "Processing included lines after added functions" | Write-Host -ForegroundColor Magenta
    # Export all the functions
    $ModuleContent += ($Line | Where-Object { $_ -notmatch '^\s*#' }) + "`n"
    $Content = "Export-ModuleMember -Function @(""{0}"") -Alias *`n`n" -f ($PublicModules -join '", "')
    $ModuleContent += $Content -join "`n`n"

    $ModuleContent = $ModuleContent -replace "`r?`n", "`r`n" | Invoke-Formatter -Settings $FormattingSettings
    if (($ModuleContent | Select-String -SimpleMatch "Wait-Debugger" -AllMatches | Measure-Object).Count -gt 0) {
        "Use of 'Wait-Debugger' command found in script:{0}. This must be removed before building the module" -f $_.Name | Write-Error -ErrorAction Stop
    }
    "Module psm1 output file: {0}" -f $OutputDirFile | Write-Host -ForegroundColor Magenta
    $ModuleContent | Out-File -Path $OutputDirFile -Encoding UTF8 -Force

    "Copy nuspec file" | Write-Host -ForegroundColor Magenta
    Copy-Item -Path "$ParentPath\OmadaWeb.PS.nuspec" -Destination "$OutputDir" -Force

}

Task ImportModule -depends Build {

    try {
        $ScriptBlock = {
            param (
                [string]$OutputDir,
                [string]$ModuleName
            )

            $ErrorActionPreference = "Stop"
            $WarningPreference = "Continue"
            $VerbosePreference = "Continue"
            $InformationPreference = "Continue"
            try {
                Test-ModuleManifest -Path "$OutputDir\$ModuleName.psd1"

                Set-StrictMode -Version Latest

                $Test = Import-Module "$OutputDir\$ModuleName.psd1" -Force -PassThru
                if ($Test) {
                    "Module loaded successfully" | Write-Verbose
                    Remove-Module -Name $Test.Name -Force
                }
                else {
                    "Module failed to load" | Write-Error -ErrorAction Stop
                }
                Set-StrictMode -Off
            }
            catch {
                $PSCmdlet.ThrowTerminatingError($PSItem)
            }
        }

        "Testing module on Windows PowerShell" | Write-Host -ForegroundColor Magenta
        & (Get-Command powershell.exe).Source -NoProfile -NoLogo -Command $ScriptBlock -Args @($OutputDir, $ModuleName) -ExecutionPolicy Unrestricted
        "Testing module on PowerShell Core" | Write-Host -ForegroundColor Magenta
        & (Get-Command pwsh.exe).Source -NoProfile -NoLogo -Command $ScriptBlock -Args @($OutputDir, $ModuleName) -ExecutionPolicy Unrestricted
    }
    catch {
        Write-Host "Error importing module: $_" -ForegroundColor Red
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}