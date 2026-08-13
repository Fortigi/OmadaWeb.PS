#Requires -Version 5.1

<#
.SYNOPSIS
    Fails the build when an exported command is missing usable comment-based help.
.DESCRIPTION
    Get-Help is the first place a PowerShell user looks, so every exported command has to answer it
    with more than its own syntax. This script imports the module and checks each exported function
    for a synopsis, a description, a minimum number of examples and at least one related link.

    It also checks parameter help, from whichever source that command's parameters come from:

      - Standalone commands declare their parameters normally, so each non-common parameter needs a
        .PARAMETER entry in its comment-based help.
      - The Invoke-Omada* wrappers add every parameter at runtime through DynamicParam. Comment-based
        .PARAMETER entries cannot attach to those, so their help lives in the -HelpMessage strings in
        OmadaWeb.PS/Private/Set-DynamicParameter.ps1 - which is also what Get-Help and the generated
        README read. Every parameter the wrapper adds on top of the cmdlet it wraps therefore needs a
        -HelpMessage; parameters inherited from Invoke-RestMethod/Invoke-WebRequest are documented by
        Microsoft and are skipped.

    Every problem found is reported before the script throws, so one run tells you everything that
    needs fixing.
.PARAMETER ModuleManifestPath
    Module manifest to import and check. Defaults to the manifest in the working copy; the build
    passes the manifest it has just produced in buildoutput.
.PARAMETER MinimumExampleCount
    How many .EXAMPLE blocks an exported command must have. Defaults to 3.
.EXAMPLE
    ./Build/Test-CommentBasedHelp.ps1

    Checks the module in the working copy.
.EXAMPLE
    ./Build/Test-CommentBasedHelp.ps1 -ModuleManifestPath ./buildoutput/OmadaWeb.PS/OmadaWeb.PS.psd1

    Checks the assembled module, which is what the build does - it verifies that the comment-based
    help actually survived into the single .psm1 that ships to the Gallery.
#>
[CmdletBinding()]
param(
    [string]$ModuleManifestPath = (Join-Path $PSScriptRoot ".." | Join-Path -ChildPath "OmadaWeb.PS" | Join-Path -ChildPath "OmadaWeb.PS.psd1"),
    [string]$PublicCommandsPath = (Join-Path $PSScriptRoot "PublicCommands.psd1"),
    [int]$MinimumExampleCount = 3
)

$ErrorActionPreference = "Stop"

$WrappedCommands = (Import-PowerShellDataFile -Path $PublicCommandsPath).WrappedCommands

Import-Module $ModuleManifestPath -Force -ErrorAction Stop
$Manifest = Import-PowerShellDataFile -Path $ModuleManifestPath

$Problems = [System.Collections.Generic.List[string]]::new()

function Add-Problem {
    param([string]$FunctionName, [string]$Message)
    $Problems.Add(("{0}: {1}" -f $FunctionName, $Message))
}

foreach ($FunctionName in $Manifest.FunctionsToExport) {
    if (-not $WrappedCommands.ContainsKey($FunctionName)) {
        Add-Problem -FunctionName $FunctionName -Message ("is exported but not listed in '{0}'. Add it, mapping it to the cmdlet it wraps or to an empty string." -f $PublicCommandsPath)
        continue
    }

    $Command = Get-Command -Name $FunctionName -ErrorAction Stop
    $Help = Get-Help -Name $FunctionName -Full

    # A command without comment-based help still gets a Help object back, with its own syntax
    # standing in for the synopsis.
    $Synopsis = ($Help.Synopsis | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($Synopsis) -or $Synopsis -like ("{0}*" -f $FunctionName)) {
        Add-Problem -FunctionName $FunctionName -Message "has no .SYNOPSIS."
    }

    $Description = ($Help.Description | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($Description)) {
        Add-Problem -FunctionName $FunctionName -Message "has no .DESCRIPTION."
    }

    # A command without any comment-based help still comes back with one empty example, which would
    # otherwise be counted as if it were real.
    $Examples = @($Help.Examples.Example | Where-Object { -not [string]::IsNullOrWhiteSpace(($_.code | Out-String)) })
    if ($Examples.Count -lt $MinimumExampleCount) {
        Add-Problem -FunctionName $FunctionName -Message ("has {0} .EXAMPLE block(s), at least {1} are required." -f $Examples.Count, $MinimumExampleCount)
    }
    foreach ($Example in $Examples) {
        if ([string]::IsNullOrWhiteSpace(($Example.remarks | ForEach-Object { $_.Text }) -join "")) {
            Add-Problem -FunctionName $FunctionName -Message ("has an .EXAMPLE without any explanation: {0}" -f ($Example.code | Out-String).Trim())
        }
    }

    if (@($Help.relatedLinks.navigationLink).Count -lt 1) {
        Add-Problem -FunctionName $FunctionName -Message "has no .LINK."
    }

    $NativeName = $WrappedCommands[$FunctionName]
    $InheritedParameterNames = @()
    if (-not [string]::IsNullOrWhiteSpace($NativeName)) {
        $InheritedParameterNames = @((Get-Command -Name $NativeName -ErrorAction Stop).Parameters.Keys)
    }

    $CommonParameterNames = @([System.Management.Automation.Cmdlet]::CommonParameters) + @([System.Management.Automation.Cmdlet]::OptionalCommonParameters)

    foreach ($ParameterName in $Command.Parameters.Keys) {
        if ($ParameterName -in $CommonParameterNames -or $ParameterName -in $InheritedParameterNames) {
            continue
        }

        $Parameter = $Command.Parameters[$ParameterName]

        if ($Parameter.IsDynamic) {
            $Attribute = $Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Select-Object -First 1
            if ($null -eq $Attribute -or [string]::IsNullOrWhiteSpace($Attribute.HelpMessage)) {
                Add-Problem -FunctionName $FunctionName -Message ("dynamic parameter -{0} has no -HelpMessage in Set-DynamicParameter.ps1." -f $ParameterName)
            }
            continue
        }

        $ParameterHelp = $Help.parameters.parameter | Where-Object { $_.name -eq $ParameterName } | Select-Object -First 1
        if ($null -eq $ParameterHelp -or [string]::IsNullOrWhiteSpace(($ParameterHelp.description | Out-String).Trim())) {
            Add-Problem -FunctionName $FunctionName -Message ("parameter -{0} has no .PARAMETER entry." -f $ParameterName)
        }
    }

    if ($Problems.Count -eq 0 -or -not ($Problems | Where-Object { $_ -like ("{0}:*" -f $FunctionName) })) {
        "{0}: help OK ({1} example(s))" -f $FunctionName, $Examples.Count | Write-Host -ForegroundColor Green
    }
}

if ($Problems.Count -gt 0) {
    $Problems | ForEach-Object { $_ | Write-Host -ForegroundColor Red }
    "{0} comment-based help problem(s) found. Every exported command must be usable through Get-Help." -f $Problems.Count | Write-Error -ErrorAction Stop
}

"Comment-based help present for all {0} exported command(s)." -f $Manifest.FunctionsToExport.Count | Write-Host -ForegroundColor Green
