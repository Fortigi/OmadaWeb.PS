#Requires -Version 7.0

<#
.SYNOPSIS
    Checks or refreshes the mutate/tests map in psmutant.config.json.
.DESCRIPTION
    PSMutant re-runs only the test files mapped to a source file for every mutant it injects into that
    file. That per-file scoping is what keeps a mutation run affordable, and it is also what decides
    the verdict: a mutant whose covering test is missing from the map survives, and is scored as a
    gap in the tests when it is a gap in the map.

    Kept by hand, that map drifts the first time a function moves or a test file is added. This script
    derives it from the code instead, so it has exactly one source of truth:

    - every *.ps1 under OmadaWeb.PS/Public and OmadaWeb.PS/Private is a mutate candidate;
    - its covering tests are the test files under Tests/Unit and Tests/Integration that name any
      function the file defines, matched as a whole command name;
    - Tests/E2E is never mapped. Those tests need a real tenant and a real browser, so a mutant they
      would kill could never be evaluated in CI.

    A source file that no test names is not mutated - every mutant in it would survive and the score
    would measure the map rather than the tests. It is listed under "_untested" instead, so the gap is
    visible in the config and in review rather than silently absent from the denominator.

    Only "mutate", "tests" and "_untested" are written. Every other key - thresholds, operators,
    workers, equivalents, comments - is preserved as it is, so the policy stays hand-edited and the map
    stays generated.

    -Check compares the committed config with what the code says it should be, and fails on any
    difference. It is what runs on a pull request, so a new function or a new test file cannot land
    with a stale map.
.PARAMETER Check
    Report drift and exit non-zero if the committed map differs from the generated one. Changes nothing.
.PARAMETER Update
    Rewrite the mutate/tests map in the config file.
.PARAMETER RepositoryRoot
    Working tree to read the module sources and tests from. Defaults to the repository this script
    lives in.
.PARAMETER ConfigPath
    Path to the PSMutant config. Defaults to psmutant.config.json under -RepositoryRoot.
.EXAMPLE
    ./Build/Update-MutationConfig.ps1 -Check

    Fails when a function or test file was added, moved or renamed without refreshing the map.
.EXAMPLE
    ./Build/Update-MutationConfig.ps1 -Update

    Regenerates the map after such a change. Commit the result.
#>
[CmdletBinding(DefaultParameterSetName = "Check")]
param(
    [parameter(Mandatory = $false, ParameterSetName = "Check")]
    [switch]$Check,

    [parameter(Mandatory = $true, ParameterSetName = "Update")]
    [switch]$Update,

    [parameter(Mandatory = $false)]
    [string]$RepositoryRoot = (Split-Path -Path $PSScriptRoot -Parent),

    [parameter(Mandatory = $false)]
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path -Path $RepositoryRoot -ChildPath "psmutant.config.json"
}

function ConvertTo-RepositoryRelativePath {
    param(
        [string]$Path
    )
    return [System.IO.Path]::GetRelativePath($RepositoryRoot, $Path).Replace('\', '/')
}

function Get-DefinedFunctionName {
    param(
        [string]$Path
    )
    $Tokens = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$ParseErrors)
    if ($ParseErrors) {
        throw ("'{0}' does not parse: {1}" -f $Path, ($ParseErrors[0].Message))
    }
    $Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        ForEach-Object { $_.Name } |
        Sort-Object -Unique
}

function Get-MutationMap {
    $SourceFiles = @(
        foreach ($Folder in "Public", "Private") {
            Get-ChildItem -Path (Join-Path -Path $RepositoryRoot -ChildPath "OmadaWeb.PS/$Folder") -Filter "*.ps1" -File -Recurse
        }
    ) | Sort-Object -Property { ConvertTo-RepositoryRelativePath -Path $_.FullName }

    # Read once: every source file is matched against every test file.
    $TestFiles = foreach ($Folder in "Unit", "Integration") {
        Get-ChildItem -Path (Join-Path -Path $RepositoryRoot -ChildPath "Tests/$Folder") -Filter "*.Tests.ps1" -File -Recurse |
            ForEach-Object {
                [PSCustomObject]@{
                    Path    = ConvertTo-RepositoryRelativePath -Path $_.FullName
                    Content = Get-Content -LiteralPath $_.FullName -Raw
                }
            }
    }
    $TestFiles = @($TestFiles | Sort-Object -Property Path)

    $Mutate = [System.Collections.Generic.List[string]]::new()
    $Tests = [ordered]@{}
    $Untested = [System.Collections.Generic.List[string]]::new()

    foreach ($SourceFile in $SourceFiles) {
        $RelativePath = ConvertTo-RepositoryRelativePath -Path $SourceFile.FullName
        $FunctionNames = @(Get-DefinedFunctionName -Path $SourceFile.FullName)
        if ($FunctionNames.Count -eq 0) {
            $Untested.Add($RelativePath)
            continue
        }

        # A command name is bounded by anything that cannot be part of one, so Get-Thing does not
        # match Get-ThingElse and Set-Body does not match Reset-Body.
        $Pattern = '(?<![\w-])(?:{0})(?![\w-])' -f (($FunctionNames | ForEach-Object { [regex]::Escape($_) }) -join '|')
        $Covering = @($TestFiles | Where-Object { $_.Content -match $Pattern } | ForEach-Object { $_.Path })

        if ($Covering.Count -eq 0) {
            $Untested.Add($RelativePath)
            continue
        }
        $Mutate.Add($RelativePath)
        $Tests[$RelativePath] = $Covering
    }

    return [PSCustomObject]@{
        Mutate   = $Mutate.ToArray()
        Tests    = $Tests
        Untested = $Untested.ToArray()
    }
}

if (!(Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw ("Config file '{0}' not found." -f $ConfigPath)
}

$Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -AsHashtable -Depth 20
$Map = Get-MutationMap

$Ordered = [ordered]@{}
foreach ($Key in $Config.Keys) {
    $Ordered[$Key] = $Config[$Key]
}
$Ordered["mutate"] = $Map.Mutate
$Ordered["tests"] = $Map.Tests
$Ordered["_untested"] = $Map.Untested

$Expected = ($Ordered | ConvertTo-Json -Depth 20) -replace "`r`n", "`n"
$Actual = (Get-Content -LiteralPath $ConfigPath -Raw) -replace "`r`n", "`n"

if ($Update) {
    [System.IO.File]::WriteAllText($ConfigPath, $Expected + "`n", [System.Text.UTF8Encoding]::new($false))
    "{0}: {1} file(s) mapped for mutation, {2} file(s) without a covering test." -f (Split-Path -Path $ConfigPath -Leaf), $Map.Mutate.Count, $Map.Untested.Count | Write-Host
    return
}

if ($Expected.TrimEnd() -ne $Actual.TrimEnd()) {
    $Current = $Actual | ConvertFrom-Json -AsHashtable -Depth 20
    $CurrentMutate = @(if ($Current.ContainsKey("mutate")) { $Current["mutate"] })
    $Added = @($Map.Mutate | Where-Object { $_ -notin $CurrentMutate })
    $Removed = @($CurrentMutate | Where-Object { $_ -notin $Map.Mutate })
    foreach ($Path in $Added) {
        "Not mapped yet: {0}" -f $Path | Write-Host
    }
    foreach ($Path in $Removed) {
        "Mapped but no longer a candidate: {0}" -f $Path | Write-Host
    }
    Write-Error -Message ("{0} is out of date with the code. Run ./Build/Update-MutationConfig.ps1 -Update and commit the result." -f (Split-Path -Path $ConfigPath -Leaf)) -ErrorAction "Stop"
}
"{0} is up to date: {1} file(s) mapped for mutation, {2} file(s) without a covering test." -f (Split-Path -Path $ConfigPath -Leaf), $Map.Mutate.Count, $Map.Untested.Count | Write-Host
