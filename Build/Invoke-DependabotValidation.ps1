<#
.SYNOPSIS
    Decides whether one Dependabot pull request gets PR Validation started automatically. Run by
    .github/workflows/dependabot-validation.yml.
.DESCRIPTION
    Evaluates the pull request against Build/DependabotValidation.psd1, writes the verdict as one
    comment on it, and reports the next step as step outputs:

        next_step  none | sync-lock | validate
        number     the pull request number
        branch     its head branch
        head_sha   the head that was evaluated

    It changes nothing else: refreshing the lock and starting PR Validation is the workflow's job, and
    merging stays with a maintainer. Runs on Windows PowerShell 5.1 and PowerShell 7.

    Needs GITHUB_TOKEN in the environment; pull-requests write for the comment.
.PARAMETER PullRequestNumber
    The pull request to evaluate.
.PARAMETER Branch
    Alternatively, the head branch of an open pull request - what the lock refresh knows.
.PARAMETER LockSynced
    Set by the lock refresh when it asks for this evaluation, so a refresh is never requested twice.
.PARAMETER DryRun
    Evaluate and report only, without writing the comment.
.EXAMPLE
    $env:GITHUB_TOKEN = gh auth token; ./Build/Invoke-DependabotValidation.ps1 -Repository Fortigi/OmadaWeb.PS -PullRequestNumber 120 -DryRun
#>
[CmdletBinding(DefaultParameterSetName = 'Number')]
param(
    [string]$Repository = $env:GITHUB_REPOSITORY,

    [Parameter(Mandatory = $true, ParameterSetName = 'Number')]
    [int]$PullRequestNumber,

    [Parameter(Mandatory = $true, ParameterSetName = 'Branch')]
    [string]$Branch,

    [string]$PolicyPath = (Join-Path -Path $PSScriptRoot -ChildPath 'DependabotValidation.psd1'),

    [switch]$LockSynced,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Windows PowerShell does not offer TLS 1.2 by default, and both GitHub and deps.dev require it.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

. (Join-Path -Path $PSScriptRoot -ChildPath 'DependabotValidation.ps1')

if ([string]::IsNullOrEmpty($Repository)) {
    throw 'No repository given and GITHUB_REPOSITORY is not set.'
}

if ($PSCmdlet.ParameterSetName -eq 'Branch') {
    $Owner = ($Repository -split '/')[0]
    $Uri = 'https://api.github.com/repos/{0}/pulls?state=open&head={1}' -f $Repository, [uri]::EscapeDataString(('{0}:{1}' -f $Owner, $Branch))
    $Open = @((Invoke-DependabotApi -Uri $Uri).Content) | Where-Object { $null -ne $_ }
    if (@($Open).Count -ne 1) {
        throw ('Expected exactly one open pull request for branch {0}, found {1}.' -f $Branch, @($Open).Count)
    }
    $PullRequestNumber = [int]@($Open)[0].number
}

$Response = Invoke-DependabotApi -Uri ('https://api.github.com/repos/{0}/pulls/{1}' -f $Repository, $PullRequestNumber)
if ($Response.StatusCode -ne 200) {
    throw ('Reading pull request #{0} failed with HTTP {1}.' -f $PullRequestNumber, $Response.StatusCode)
}

$Policy = Get-DependabotPolicy -Path $PolicyPath
$Evaluation = Get-DependabotEvaluation -Repository $Repository -PullRequest $Response.Content -Policy $Policy -Now ([datetime]::UtcNow)
$NextStep = Get-DependabotNextStep -Evaluation $Evaluation -Policy $Policy -LockSynced:$LockSynced
$Report = Format-DependabotReport -Evaluation $Evaluation -NextStep $NextStep

$Report | Write-Host
# AppendAllText with an explicit BOM-less encoding: Windows PowerShell's Out-File -Encoding utf8 would
# prefix a BOM, which GitHub then reads as part of the first output name.
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
if (-not [string]::IsNullOrEmpty($env:GITHUB_STEP_SUMMARY)) {
    [System.IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, $Report + "`n", $Utf8NoBom)
}
Set-DependabotComment -Repository $Repository -Number $Evaluation.Number -Body $Report -WhatIf:$DryRun

if (-not [string]::IsNullOrEmpty($env:GITHUB_OUTPUT)) {
    $Outputs = @(
        'next_step={0}' -f $NextStep
        'number={0}' -f $Evaluation.Number
        'branch={0}' -f $Evaluation.Branch
        'head_sha={0}' -f $Evaluation.HeadSha
    )
    [System.IO.File]::AppendAllText($env:GITHUB_OUTPUT, ($Outputs -join "`n") + "`n", $Utf8NoBom)
}
