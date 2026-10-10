Properties {
    $Version = $BuildVersion
    $Date = Get-Date
    $ModuleName = "OmadaWeb.PS"
    $ParentPath = (Get-Item -Path $PSScriptRoot -Verbose:$false).Parent.FullName
    $ModuleSource = Join-Path -Path $ParentPath -ChildPath 'OmadaWeb.PS'
    $TestSource = Join-Path -Path $ParentPath -ChildPath 'tests'
    $OutputDir = Join-Path -Path $ParentPath -ChildPath 'buildoutput\OmadaWeb.PS'
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
    $QualityOutputDir = Join-Path -Path $ParentPath -ChildPath 'buildoutput\quality'
    $ComplexityBaseline = 'complexity-baseline.json'
    $MutationConfig = 'psmutant.config.json'
    $MaxCyclomatic = 15
    $MaxCognitive = 15
}


# Build produces a complete package on its own - assemblies bundled, contents verified against the
# manifest - so every task list below and every caller of `build.ps1 -Task Build` gets the same
# thing.
Task default -depends Analyze, Build, ImportModule, TestHelp, Test
Task DeployOnly -depends Build, Deploy
Task TestBuildOnly -depends Analyze, Build, ImportModule, TestHelp, Test

# Complexity (PSComplexity) and test strength (PSMutant), see issue #91. Two scopes:
#
# - QualityChanged runs on a pull request and only judges the files the pull request changed: new or
#   touched code meets the bar, pre-existing debt elsewhere does not block it.
# - Complexity and Mutate judge the whole tree. They run weekly (.github/workflows/quality-weekly.yml),
#   which files a bug when either falls below the bar.
#
# Both tools require PowerShell 7.0+, so every task below is skipped under Windows PowerShell 5.1,
# which keeps the powershell leg of PR validation unaffected.
Task QualityChanged -depends MutationConfigCheck, ComplexityChanged, MutateChanged

Task Analyze {

    $Profile = @{
        Severity     = @('Error', 'Warning')
        IncludeRules = '*'
        # AvoidGlobalVars is deliberately NOT excluded here, so that a new, unjustified global fails
        # this task instead of passing unnoticed under a blanket exclusion. The module's one global,
        # $Global:OmadaWebPSCurrentBaseUrl, has three touch points: it is initialized by
        # Initialize-OmadaCurrentBaseUrl (OmadaWeb.PS.psm1), maintained by Set-OmadaCurrentBaseUrl,
        # and cleared by Clear-OmadaWebCache. The first two carry an inline suppression and exist as
        # separate small functions only so that the attribute - which has no per-variable suppression
        # ID and therefore always covers its whole scope - covers a few lines rather than a whole
        # file or a 400-line function. Clear-OmadaWebCache needs no suppression because it goes
        # through Set-Variable -Scope Global, a form this rule does not flag.
        ExcludeRules = '*WriteHost', '*AvoidUsingEmptyCatchBlock*', '*UseShouldProcessForStateChangingFunctions*', '*AvoidOverwritingBuiltInCmdlets*', '*UseToExportFieldsInManifest*', '*UseProcessBlockForPipelineCommand*', '*ConvertToSecureStringWithPlainText*'
    }
    $saResults = Invoke-ScriptAnalyzer -Path $ModuleSource -Severity @('Error', 'Warning') -Recurse -Profile $Profile -Verbose:$false
    if ($saResults) {
        $saResults | Format-Table
        Write-Error -Message 'One or more Script Analyzer errors/warnings where found. Build cannot continue!' -ErrorAction "Stop"
    }
}

Task Build -depends Analyze {

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

    function Select-ModuleSourceLine {
        # The single .psm1 that ships to the Gallery is assembled by concatenating the source files,
        # dropping their comments to keep it compact. Comment-based help has to survive that though,
        # otherwise Get-Help returns nothing for the exported commands, so lines inside a block
        # comment are kept for the public functions (-KeepCommentBasedHelp) and dropped for
        # everything else.
        param(
            [string[]]$Line,
            [switch]$KeepCommentBasedHelp
        )

        $Output = [System.Collections.Generic.List[string]]::new()
        $InBlockComment = $false

        foreach ($CurrentLine in $Line) {
            if ($InBlockComment) {
                if ($KeepCommentBasedHelp) {
                    $Output.Add($CurrentLine)
                }
                if ($CurrentLine -match '#>') {
                    $InBlockComment = $false
                }
                continue
            }

            # Only a block comment that stays open past this line changes the state; one that opens
            # and closes on the same line, or that trails code, is handled as an ordinary line.
            if ($CurrentLine -match '^\s*<#' -and $CurrentLine -notmatch '#>') {
                $InBlockComment = $true
                if ($KeepCommentBasedHelp) {
                    $Output.Add($CurrentLine)
                }
                continue
            }

            if ($CurrentLine -match '^\s*#') {
                continue
            }

            $Output.Add($CurrentLine)
        }

        return $Output.ToArray()
    }

    # Lives in its own file so it can be unit tested; it used to be defined inline here, where a
    # PSObject-wrapping bug silently corrupted the manifest's Tags.
    . (Join-Path $ParentPath -ChildPath 'Build\ConvertTo-HashtableDeep.ps1')

    #Read Functions
    $Public = @(Get-ChildItem -Path $ModuleSource\Public\*.ps1 -Recurse)
    $Private = @(Get-ChildItem -Path $ModuleSource\Private\*.ps1)
    $PublicModules = @()
    foreach ($import in $Public) {
        $PublicModules += ($import.BaseName)
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
    # Explicit -Depth: PrivateData.PSData nests two levels today, which the default depth of 2 just
    # survives; any extra nesting would be silently dropped from the generated manifest.
    $PrivateData = ConvertTo-HashtableDeep ($ModulePsd1.PrivateData | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
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
            $ModuleContent += "#region public functions`n"
            foreach ($import in $Public) {
                $Content = Select-ModuleSourceLine -Line (Get-Content $import.FullName -Encoding UTF8) -KeepCommentBasedHelp
                # Joined before trimming so the indentation inside the comment-based help block
                # survives; only leading and trailing blank lines are removed.
                $ModuleContent += ($Content -join "`n").Trim()
                $ModuleContent += "`n`n"
            }
            $ModuleContent += "#endregion`n`n#region private functions`n"
            foreach ($import in $Private) {
                $Content = Select-ModuleSourceLine -Line (Get-Content $import.FullName -Encoding UTF8)
                $ModuleContent += ($Content -join "`n").Trim()
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
    $ModuleContent | Out-File -FilePath $OutputDirFile -Encoding UTF8 -Force

    "Copy nuspec file" | Write-Host -ForegroundColor Magenta
    Copy-Item -Path "$ParentPath\OmadaWeb.PS.nuspec" -Destination "$OutputDir" -Force

    # The lock file has to sit next to the .psm1 in the built module: the module resolves it through
    # $PSScriptRoot, and without it every runtime download fails closed.
    "Copy dependency lock file" | Write-Host -ForegroundColor Magenta
    Copy-Item -Path "$ModuleSource\DependencyLock.psd1" -Destination "$OutputDir" -Force

    # Puts the WebView2 assemblies inside the package, fetched from the pinned URL and verified
    # against the pinned SHA-256 by the module's own download code.
    #
    # This belongs to building the module rather than to a task alongside it. The manifest written
    # above declares these files in its FileList unconditionally, so a package without them is not a
    # cheaper build - it is a broken one, and it fails much later, in whatever job tries to publish
    # it. It used to be a separate BundleDependencies task pulled in by the aggregate task lists,
    # which meant `build.ps1 -Task Build` - what nightly.yml runs - produced exactly that.
    #
    # A failure here fails the build on purpose. A package that quietly shipped without these
    # assemblies would look healthy and then break the first sign-in of every user without egress to
    # nuget.org.
    "Bundle runtime dependencies" | Write-Host -ForegroundColor Magenta
    & (Join-Path $PSScriptRoot -ChildPath "Get-BundledDependency.ps1") -PackagePath $OutputDir -RepositoryRoot $ParentPath

    # Everything the manifest promises has to be on disk before anything downstream believes it.
    "Verify package contents against the manifest" | Write-Host -ForegroundColor Magenta
    & (Join-Path $PSScriptRoot -ChildPath "Confirm-PackageFileList.ps1") -PackagePath $OutputDir

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

                # Set-StrictMode here would only cover this scope. The module runs in its own session
                # state, so neither its load-time code nor its functions inherit it - the module reads
                # OMADAWEBPS_STRICTMODE and sets StrictMode on itself instead.
                $PreviousStrictMode = $Env:OMADAWEBPS_STRICTMODE
                $Env:OMADAWEBPS_STRICTMODE = "1"
                try {
                    $Test = Import-Module "$OutputDir\$ModuleName.psd1" -Force -PassThru
                }
                finally {
                    $Env:OMADAWEBPS_STRICTMODE = $PreviousStrictMode
                }

                if ($Test) {
                    "Module loaded successfully" | Write-Verbose
                    Remove-Module -name $Test.Name -Force
                }
                else {
                    "Module failed to load" | Write-Error -ErrorAction Stop
                }
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


# Checks the assembled module rather than the source files, so it also proves the comment-based help
# survived being concatenated into the single .psm1 that ships to the Gallery.
Task TestHelp -depends ImportModule {
    & (Join-Path $PSScriptRoot -ChildPath "Test-CommentBasedHelp.ps1") -ModuleManifestPath (Join-Path -Path $OutputDir -ChildPath ("{0}.psd1" -f $ModuleName))
}

Task Test -depends ImportModule {
    $Tests = Get-ChildItem ..\Tests -Filter *.Tests.ps1 -Recurse
    if ($Tests.Count -eq 0) {
        'No tests found' | Write-Warning
        return
    }

    $ModulePsm1Path = Join-Path -Path $OutputDir -ChildPath ("{0}.psm1" -f $ModuleName)
    $Container = New-PesterContainer -Path $Tests.FullName -Data @{ ModulePath = $ModulePsm1Path }

    $PesterConfiguration = New-PesterConfiguration
    $PesterConfiguration.Run.Container = $Container
    $PesterConfiguration.Run.PassThru = $true
    $PesterConfiguration.TestResult.Enabled = $true
    $PesterConfiguration.TestResult.OutputFormat = 'JUnitXml'
    $PesterConfiguration.TestResult.OutputPath = (Join-Path -Path $ParentPath -ChildPath 'buildoutput\TestResults.xml')
    # E2E tests need a real Edge/WebView2 install, a browser window and a tenant to sign in to, so
    # they are excluded here and run daily on .github/workflows/entra-canary.yml instead - the
    # scheduled pipeline this comment used to promise. See docs/entra-canary.md.
    $PesterConfiguration.Filter.ExcludeTag = 'E2E'

    # Every test run exercises the module under Set-StrictMode -Version Latest. The module picks this
    # up itself (see OmadaWeb.PS.psm1) because StrictMode does not cross into a module's session
    # state from here. It covers the InModuleScope blocks in the tests as well, so a test fixture that
    # reads a member no real caller would get is caught too.
    # Restored rather than cleared: the build runs in the developer's own session, so blanking it
    # would discard a value they had set for themselves.
    $PreviousStrictMode = $Env:OMADAWEBPS_STRICTMODE
    $Env:OMADAWEBPS_STRICTMODE = "1"
    try {
        $Result = Invoke-Pester -Configuration $PesterConfiguration
    }
    finally {
        $Env:OMADAWEBPS_STRICTMODE = $PreviousStrictMode
    }

    if ($Result.FailedCount -gt 0) {
        Write-Error -Message ("{0} Pester test(s) failed." -f $Result.FailedCount) -ErrorAction Stop
    }
}

function Get-QualityChangedFile {
    # The files the pull request changed, relative to the repository root. PR validation passes them in
    # PR_CHANGED_FILES (';'-separated, from git diff against the merge base with main); a local run falls
    # back to the same diff. Deleted files are dropped: there is nothing left to measure in them.
    param(
        [string]$RepositoryRoot
    )
    $Files = @($Env:PR_CHANGED_FILES -split ';' | Where-Object { ![string]::IsNullOrWhiteSpace($_) })
    if ($Files.Count -eq 0) {
        $MergeBase = git -C $RepositoryRoot merge-base origin/main HEAD
        if ($LASTEXITCODE -ne 0) {
            throw "PR_CHANGED_FILES is not set and the merge base with origin/main could not be determined. Run 'git fetch origin main' first."
        }
        $Files = @(git -C $RepositoryRoot diff --name-only $MergeBase HEAD)
    }
    return @($Files | Where-Object { Test-Path -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath $_) -PathType Leaf })
}

function Write-QualityVerdict {
    # One small file per gate, read by the weekly workflow to decide whether to file or update a bug.
    # Written on pass and on fail alike, so a missing file means the gate never reached a verdict.
    param(
        [string]$Path,
        [string]$Gate,
        [bool]$Passed,
        [string]$Summary,
        [string[]]$Detail = @()
    )
    New-Item -Path (Split-Path -Path $Path -Parent) -ItemType Directory -Force | Out-Null
    [PSCustomObject]@{
        gate    = $Gate
        passed  = $Passed
        summary = $Summary
        detail  = @($Detail)
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
    if ($Env:GITHUB_STEP_SUMMARY) {
        $Lines = @("### {0}: {1}" -f $Gate, $(if ($Passed) { "passed" } else { "FAILED" }), "", $Summary, "")
        $Lines += @($Detail | ForEach-Object { "- {0}" -f $_ })
        $Lines -join "`n" | Add-Content -Path $Env:GITHUB_STEP_SUMMARY -Encoding UTF8
    }
}

function Get-ComplexityViolationLine {
    param(
        [string]$ReportPath
    )
    if (!(Test-Path -LiteralPath $ReportPath)) {
        return @()
    }
    $Report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
    if (!($Report.PSObject.Properties.Name -contains 'violations')) {
        return @()
    }
    return @($Report.violations | ForEach-Object {
            "``{0}`` {1}: cyclomatic {2}, cognitive {3}" -f $_.file, $_.unit, $_.cyclomatic, $_.cognitive
        })
}

function Get-MutationResultLine {
    # The score alone is never quoted: the two shapes of a vacuous 100% (files with no candidate, and
    # files whose candidates the coverage filter removed) and the uncovered mutants are reported beside
    # it, together with the weakest files.
    param(
        $Result,
        [string]$ReportPath
    )
    $Lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $ReportPath) {
        $Report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
        $Names = $Report.PSObject.Properties.Name
        foreach ($Disclosure in 'skippedAsUncovered', 'filesWithNoMutants', 'filesWithNoCandidate') {
            if ($Names -contains $Disclosure) {
                $Lines.Add(("{0}: {1}" -f $Disclosure, @($Report.$Disclosure).Count))
            }
        }
        if ($Names -contains 'perFile') {
            foreach ($File in @($Report.perFile | Where-Object { $_.survived -gt 0 } | Select-Object -First 15)) {
                $Lines.Add(("``{0}``: {1}% ({2}/{3} killed, {4} survived)" -f $File.file, $File.score, $File.killed, $File.total, $File.survived))
            }
        }
    }
    return $Lines.ToArray()
}

Task MutationConfigCheck -precondition { $PSVersionTable.PSVersion.Major -ge 7 } {
    & (Join-Path -Path $PSScriptRoot -ChildPath "Update-MutationConfig.ps1") -Check -RepositoryRoot $ParentPath
}

Task Complexity -precondition { $PSVersionTable.PSVersion.Major -ge 7 } {
    Import-Module -Name PSComplexity -RequiredVersion 0.5.1 -Force
    $ReportPath = Join-Path -Path $QualityOutputDir -ChildPath 'complexity.json'
    New-Item -Path $QualityOutputDir -ItemType Directory -Force | Out-Null

    # The baseline records each unit already over the ceilings at its current score. It only ratchets
    # down: a recorded unit may not get worse, any other unit must stay within the ceilings, and an
    # entry that no longer describes the code (fixed, improved, renamed) fails the gate too, so it
    # cannot age into a suppression list.
    Push-Location -Path $ParentPath
    try {
        $Passed = Test-PSComplexity -Path './OmadaWeb.PS' -Recurse -MaxCyclomatic $MaxCyclomatic -MaxCognitive $MaxCognitive `
            -BaselineFile $ComplexityBaseline -ReportPath $ReportPath -SarifPath (Join-Path -Path $QualityOutputDir -ChildPath 'complexity.sarif')
        $Summary = "Whole tree, ceilings $MaxCyclomatic cyclomatic / $MaxCognitive cognitive, against $ComplexityBaseline."
        $Detail = @(Get-ComplexityViolationLine -ReportPath $ReportPath)
    }
    catch {
        $Passed = $false
        $Summary = "PSComplexity refused to reach a verdict. Most often a $ComplexityBaseline entry no longer describes the code (fixed, improved, renamed or moved), which Test-PSComplexity -Path ./OmadaWeb.PS -Recurse -BaselineFile ./$ComplexityBaseline -UpdateBaseline resolves; the reason is below."
        $Detail = @($_.Exception.Message -split '; ')
    }
    finally {
        Pop-Location
    }

    Write-QualityVerdict -Path (Join-Path -Path $QualityOutputDir -ChildPath 'complexity.verdict.json') -Gate 'Complexity' -Passed $Passed -Summary $Summary -Detail $Detail
    if (!$Passed) {
        Write-Error -Message 'The complexity gate failed, see the report above.' -ErrorAction Stop
    }
}

Task ComplexityChanged -precondition { $PSVersionTable.PSVersion.Major -ge 7 } {
    $Changed = @(Get-QualityChangedFile -RepositoryRoot $ParentPath | Where-Object { $_ -like 'OmadaWeb.PS/*' -and $_ -like '*.ps*1' })
    if ($Changed.Count -eq 0) {
        "No module source changed; the complexity gate does not apply to this change." | Write-Host
        return
    }
    Import-Module -Name PSComplexity -RequiredVersion 0.5.1 -Force
    New-Item -Path $QualityOutputDir -ItemType Directory -Force | Out-Null
    $ReportPath = Join-Path -Path $QualityOutputDir -ChildPath 'complexity.changed.json'

    # PSComplexity 0.5.1 checks every baseline entry against the units it measured, and with
    # -ChangedFile it measures only the changed files - so the entries for every other file read as
    # "renamed or moved" and the gate throws. The baseline is narrowed to the changed files first. An
    # entry for a changed file still has to match, so the ratchet holds for exactly the code under
    # review.
    $Baseline = Get-Content -LiteralPath (Join-Path -Path $ParentPath -ChildPath $ComplexityBaseline) -Raw | ConvertFrom-Json
    $Baseline.units = @($Baseline.units | Where-Object { $_.file -in $Changed })
    $ScopedBaseline = Join-Path -Path $QualityOutputDir -ChildPath 'complexity-baseline.changed.json'
    $Baseline | ConvertTo-Json -Depth 5 | Set-Content -Path $ScopedBaseline -Encoding UTF8

    Push-Location -Path $ParentPath
    try {
        $Passed = Test-PSComplexity -Path './OmadaWeb.PS' -Recurse -MaxCyclomatic $MaxCyclomatic -MaxCognitive $MaxCognitive `
            -ChangedFile $Changed -BaselineFile $ScopedBaseline -ReportPath $ReportPath
        $Summary = "Changed files only ($($Changed.Count)), ceilings $MaxCyclomatic cyclomatic / $MaxCognitive cognitive. A unit recorded in $ComplexityBaseline may not get worse; any other unit must stay within the ceilings."
        $Detail = @(Get-ComplexityViolationLine -ReportPath $ReportPath)
    }
    catch {
        $Passed = $false
        $Summary = "PSComplexity refused to reach a verdict. Most often a $ComplexityBaseline entry no longer describes the code (fixed, improved, renamed or moved), which Test-PSComplexity -Path ./OmadaWeb.PS -Recurse -BaselineFile ./$ComplexityBaseline -UpdateBaseline resolves; the reason is below."
        $Detail = @($_.Exception.Message -split '; ')
    }
    finally {
        Pop-Location
    }

    Write-QualityVerdict -Path (Join-Path -Path $QualityOutputDir -ChildPath 'complexity.changed.verdict.json') -Gate 'Complexity (changed files)' -Passed $Passed -Summary $Summary -Detail $Detail
    if (!$Passed) {
        Write-Error -Message 'The complexity gate failed for the changed files, see the report above.' -ErrorAction Stop
    }
}

Task Mutate -precondition { $PSVersionTable.PSVersion.Major -ge 7 } {
    Invoke-QualityMutation -RepositoryRoot $ParentPath -ConfigPath $MutationConfig -QualityOutputDir $QualityOutputDir
}

Task MutateChanged -precondition { $PSVersionTable.PSVersion.Major -ge 7 } {
    $Config = Get-Content -LiteralPath (Join-Path -Path $ParentPath -ChildPath $MutationConfig) -Raw | ConvertFrom-Json
    $Changed = @(Get-QualityChangedFile -RepositoryRoot $ParentPath)
    $ChangedMutate = @($Changed | Where-Object { $_ -in @($Config.mutate) })
    if ($ChangedMutate.Count -eq 0) {
        "No mutation-tested source file changed; the mutation gate does not apply to this change." | Write-Host
        return
    }
    Invoke-QualityMutation -RepositoryRoot $ParentPath -ConfigPath $MutationConfig -QualityOutputDir $QualityOutputDir -ChangedFile $ChangedMutate
}

function Invoke-QualityMutation {
    param(
        [string]$RepositoryRoot,
        [string]$ConfigPath,
        [string]$QualityOutputDir,
        [string[]]$ChangedFile = @()
    )
    Import-Module -Name PSMutant -RequiredVersion 0.5.0 -Force

    # The tests import the source module, which only turns StrictMode on when asked to. Same contract
    # as the Test task: every test run - and so every mutant - is evaluated under StrictMode.
    $PreviousStrictMode = $Env:OMADAWEBPS_STRICTMODE
    $Env:OMADAWEBPS_STRICTMODE = "1"
    Push-Location -Path $RepositoryRoot
    try {
        $Parameters = @{
            ConfigFile = $ConfigPath
            SourceRoot = $RepositoryRoot
        }
        if ($ChangedFile.Count -gt 0) {
            $Parameters.ChangedFile = $ChangedFile
        }
        $Result = Invoke-PSMutation @Parameters
    }
    finally {
        Pop-Location
        $Env:OMADAWEBPS_STRICTMODE = $PreviousStrictMode
    }

    $Config = Get-Content -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath $ConfigPath) -Raw | ConvertFrom-Json
    $ReportPath = Join-Path -Path $RepositoryRoot -ChildPath $Config.reportPath
    $Gate = 'Mutation'
    $Scope = "Whole tree ($(@($Config.mutate).Count) files)"
    if ($ChangedFile.Count -gt 0) {
        $ReportPath = [System.IO.Path]::ChangeExtension($ReportPath, '.changed.json')
        $Gate = 'Mutation (changed files)'
        $Scope = "Changed files only: $($ChangedFile -join ', ')"
    }
    $Break = $Config.thresholds.break
    $Floor = if ($null -eq $Break) { "no floor set (report-only)" } else { "floor $Break%" }
    $Summary = "{0}. Score {1}% ({2}/{3} killed), {4}. Exit reason: {5}." -f $Scope, $Result.Score, $Result.Killed, $Result.Total, $Floor, $Result.FailureReason
    $Detail = @(Get-MutationResultLine -Result $Result -ReportPath $ReportPath)
    if (@($Config.PSObject.Properties.Name) -contains '_untested' -and $ChangedFile.Count -eq 0) {
        $Detail += "Source files no test names, so not mutated at all: $(@($Config._untested).Count)"
    }

    $VerdictName = if ($ChangedFile.Count -gt 0) { 'mutation.changed.verdict.json' } else { 'mutation.verdict.json' }
    Write-QualityVerdict -Path (Join-Path -Path $QualityOutputDir -ChildPath $VerdictName) -Gate $Gate -Passed ($Result.ExitCode -eq 0) -Summary $Summary -Detail $Detail
    if ($Result.ExitCode -ne 0) {
        Write-Error -Message ("The mutation gate failed: {0}." -f $Result.FailureReason) -ErrorAction Stop
    }
}

# Task Test  {

#     $ScriptBlock = {
#         param(
#             [string]$OutputDir,
#             [string]$ModuleName,
#             [string]$BasePath
#         )
#         Set-Location -Path $BasePath
#         $Tests = Get-ChildItem ..\Tests -Filter *.Tests.ps1 -Recurse
#         if ($Tests.Count -eq 0) {
#             'No tests found' | Write-Warning
#         }
#         foreach ($Test in $Tests) {
#             "{0} - Running tests from file: {1}" -f $MyInvocation.MyCommand, $Test.FullName | Write-Host -ForegroundColor Magenta
#             . $Test.FullName -ModulePath (Join-Path -Path $OutputDir -ChildPath ("{0}.psm1" -f $ModuleName))
#         }
#     }
#     Wait-Debugger
#     $BasePath = $PSScriptRoot
#     "Run function tests on Windows PowerShell" | Write-Host -ForegroundColor Magenta
#     & (Get-Command powershell.exe).Source -NoLogo -Command $ScriptBlock -Args @($OutputDir, $ModuleName, $BasePath) -ExecutionPolicy Unrestricted
#     "Run function tests on PowerShell Core" | Write-Host -ForegroundColor Magenta
#     & (Get-Command pwsh.exe).Source -NoLogo -Command $ScriptBlock -Args @($OutputDir, $ModuleName, $BasePath) -ExecutionPolicy Unrestricted

# }