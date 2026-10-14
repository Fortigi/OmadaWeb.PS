#Requires -Version 7.0

<#
.SYNOPSIS
    Runs one attempt of an Entra canary and writes its result as JSON.
.DESCRIPTION
    The canary workflow runs this in a child process with a deadline rather than calling Invoke-Pester
    directly, and that is the whole reason it exists as a separate script.

    The deadline is what the sign-in canary needs; the service-principal canary, which opens no
    browser and cannot hang waiting for a user, uses this for the reporting rather than the deadline:
    the JSON summary, the JUnit result and the diagnostic file are what the workflow reads to build
    its report either way.

    A browser sign-in has no natural end when nobody is driving it. If the automation hands over to
    manual - which is exactly what a selector break makes it do - it then waits for a user who does
    not exist on a runner. The first canary run after the console-handle fix (issue #79) did precisely
    that: the window opened, the timer ticked for 29 minutes, and the job timeout killed the step. A
    killed step reports nothing: no assertions, no diagnostic, no alert. The canary was silent about
    the very failure it exists to catch.

    In-process there is nothing to interrupt, because the WinForms dialog blocks the thread it is
    shown on. A child process can simply be killed, which turns a hang into a reported failure - and
    that is the difference between a canary and a job that sometimes times out.

    Verbose is on. The module's own trace is the product when a sign-in stalls: without it, all a
    stalled run leaves behind is a line of progress dots. Protect-LogMessage covers the module's
    streams and the workflow masks the four canary secrets before this runs, so this does not widen
    what is exposed.
.PARAMETER ModulePath
    The built OmadaWeb.PS.psm1 the canary signs in with.
.PARAMETER ResultPath
    Where the JUnit test result is written.
.PARAMETER SummaryPath
    Where the JSON summary the caller reads is written. Absent afterwards means the attempt died
    without reporting, which the caller treats as a failure rather than as a pass.
.PARAMETER DiagnosticPath
    Passed to the test as OMADAWEBPS_CANARY_DIAGNOSTIC_PATH, where Switch-ToManualLogin's diagnostic
    is written when there is one.
.PARAMETER TestFile
    Which canary to run, as a file name in this directory. Defaults to the sign-in canary. The
    service-principal canary is a separate file because it shares nothing with the sign-in one except
    this runner and the loopback stand-in, but it wants the same deadline, the same JSON summary and
    the same diagnostic file - so it is the same attempt mechanism, pointed at another test.
.PARAMETER Scenario
    Which case to drive.

    For the sign-in canary: 'PasswordAutofill' is the sign-in that completes - the original canary.
    'UserNameOnly' and 'NoUserName' are the two that are not meant to complete: they watch what the
    module does when it is given an account but no password, and when it is given neither. Each needs
    its own browser window, so each is its own attempt.

    For the service-principal canary: which credential form authenticates the client. Each is its own
    attempt because supplying two credentials at once means only one of them is under test.
.EXAMPLE
    ./Tests/E2E/Invoke-CanaryAttempt.ps1 -ModulePath ./buildoutput/OmadaWeb.PS/OmadaWeb.PS.psm1 `
        -ResultPath ./buildoutput/CanaryResults-1.xml -SummaryPath $env:RUNNER_TEMP/summary-1.json `
        -DiagnosticPath $env:RUNNER_TEMP/diagnostic-1.txt
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ModulePath,

    [Parameter(Mandatory)]
    [string]$ResultPath,

    [Parameter(Mandatory)]
    [string]$SummaryPath,

    [Parameter(Mandatory)]
    [string]$DiagnosticPath,

    [ValidateSet('EntraSignInCanary.Tests.ps1', 'EntraServicePrincipalCanary.Tests.ps1')]
    [string]$TestFile = 'EntraSignInCanary.Tests.ps1',

    [ValidateSet('PasswordAutofill', 'UserNameOnly', 'NoUserName', 'OAuthClientSecret', 'OAuthCertificateStore', 'OAuthCertificateFile', 'OAuthCertificateObject')]
    [string]$Scenario = 'PasswordAutofill'
)

$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

$Env:OMADAWEBPS_CANARY_DIAGNOSTIC_PATH = $DiagnosticPath

$Container = New-PesterContainer -Path (Join-Path $PSScriptRoot $TestFile) -Data @{ ModulePath = $ModulePath; Scenario = $Scenario }

$Configuration = New-PesterConfiguration
$Configuration.Run.Container = $Container
$Configuration.Run.PassThru = $true
$Configuration.Filter.Tag = "E2E"
$Configuration.Output.Verbosity = "Detailed"
$Configuration.TestResult.Enabled = $true
$Configuration.TestResult.OutputFormat = "JUnitXml"
$Configuration.TestResult.OutputPath = $ResultPath

$Result = Invoke-Pester -Configuration $Configuration

$Summary = [ordered]@{
    Scenario = $Scenario
    Failed  = [int]$Result.FailedCount
    Passed  = [int]$Result.PassedCount
    Skipped = [int]$Result.SkippedCount
    Failure = @($Result.Failed | ForEach-Object {
            $Name = if ([string]::IsNullOrWhiteSpace($_.ExpandedPath)) { $_.Name } else { $_.ExpandedPath }
            "- {0}: {1}" -f $Name, $_.ErrorRecord.Exception.Message
        })
}

$Summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
