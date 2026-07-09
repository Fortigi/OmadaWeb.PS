#Requires -Version 7.0
#Requires -PSEdition Core

<#
.SYNOPSIS
    Regenerates the SYNTAX and PARAMETERS sections of README.md from the live OmadaWeb.PS module.
.DESCRIPTION
    Invoke-OmadaRestMethod and Invoke-OmadaWebRequest have no comment-based help - every parameter is
    added at runtime via DynamicParam/Set-DynamicParameter.ps1, and the parameter descriptions live as
    -HelpMessage strings on the New-DynamicParam calls in that file. This script imports the module,
    reflects over the resulting Get-Command output (which resolves the dynamic parameters and mirrors
    the real parameter sets of Invoke-RestMethod/Invoke-WebRequest), and rewrites the generated regions
    of README.md - delimited by "<!-- BEGIN GENERATED ... -->" / "<!-- END GENERATED ... -->" comments -
    so hand-written prose elsewhere in the file is never touched.

    Run this after changing dynamic parameters in OmadaWeb.PS/Private/Set-DynamicParameter.ps1.

    Note: the real parameter sets (StandardMethod/StandardMethodNoProxy/CustomMethod/CustomMethodNoProxy)
    only exist on PowerShell 7's Invoke-RestMethod/Invoke-WebRequest - Windows PowerShell 5.1's versions
    only expose __AllParameterSets. This script requires PowerShell 7 so the generated SYNTAX reflects
    the real set structure.
#>
[CmdletBinding()]
param(
    [string]$ModuleManifestPath = (Join-Path $PSScriptRoot "..\OmadaWeb.PS\OmadaWeb.PS.psd1"),
    [string]$ReadmePath = (Join-Path $PSScriptRoot "..\README.md")
)

$ErrorActionPreference = "Stop"

# Maps each Omada wrapper function to the native cmdlet it wraps (mirrors the $Script:FunctionName
# assignment inside each Public function's DynamicParam block). Add an entry here if a new wrapper
# function is introduced.
$NativeCommandMap = [ordered]@{
    "Invoke-OmadaRestMethod" = "Invoke-RestMethod"
    "Invoke-OmadaWebRequest" = "Invoke-WebRequest"
}

# Preferred display order for Omada-specific parameters, taken from the declaration order in
# Set-DynamicParameter.ps1. Any Omada-specific parameter not listed here (e.g. a newly added one)
# is appended alphabetically at the end instead of being silently dropped.
$PreferredParameterOrder = @(
    "AuthenticationType",
    "EntraIdTenantId",
    "EntraApplicationIdUri",
    "OAuthScope",
    "OAuthUri",
    "CookiePath",
    "SkipCookieCache",
    "ForceAuthentication",
    "EdgeProfile",
    "InPrivate",
    "UseWebView2",
    "DebugWebView2",
    "Paged"
)

# ValidateSet values that are populated from the local machine (not a fixed set of documentation
# values) and should therefore not be expanded into a {A | B | ...} list in the generated SYNTAX.
$RuntimeDependentValidateSetParameters = @("EdgeProfile")

# Per-parameter markdown-only enrichment, for rich formatting (distinctly-labeled hyperlinks, bold
# emphasis) that can't be expressed by the generic 'quoted term' -> `code span` / IMPORTANT: -> blockquote
# rules in Format-Description without leaking markup into Get-Help (which prints -HelpMessage verbatim).
# -HelpMessage stays plain, console-safe English; each entry below does a literal, case-sensitive
# find/replace against that parameter's rendered README description only. Keep entries narrowly scoped
# (specific phrases, not single common words) so they cannot accidentally match unrelated text.
$ParameterMarkdownOverrides = @{
    AuthenticationType = @(
        @{ Find = "Microsoft WebView2 NuGet package"; Replace = "[Microsoft WebView2](https://developer.microsoft.com/en-us/Microsoft-edge/webview2) [NuGet](https://www.nuget.org/packages/microsoft.web.webview2) package" }
        @{ Find = "Requires Credential."; Replace = "Requires **Credential**." }
        @{ Find = "Supplying AuthenticationType overrides"; Replace = "Supplying **AuthenticationType** overrides" }
    )
}

$FriendlyTypeNames = @{
    "System.String"                                  = "string"
    "System.Uri"                                      = "uri"
    "System.Int32"                                    = "int"
    "System.Int64"                                    = "long"
    "System.Boolean"                                  = "bool"
    "System.Management.Automation.SwitchParameter"    = "switch"
    "System.Management.Automation.PSCredential"       = "pscredential"
}

function Get-FriendlyTypeName {
    param([Type]$Type)
    if ($FriendlyTypeNames.ContainsKey($Type.FullName)) {
        return $FriendlyTypeNames[$Type.FullName]
    }
    return $Type.Name.ToLowerInvariant()
}

function Get-ParameterAttribute {
    param($ParameterMetadata)
    return ($ParameterMetadata.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Select-Object -First 1)
}

function Get-OmadaSpecificParameterNames {
    param($Command, $NativeCommand)
    $Names = $Command.Parameters.Keys | Where-Object { $_ -notin $NativeCommand.Parameters.Keys }
    return $Names | Sort-Object -Property @(
        @{ Expression = { $Index = $PreferredParameterOrder.IndexOf($_); if ($Index -lt 0) { [int]::MaxValue } else { $Index } } },
        @{ Expression = { $_ } }
    )
}

function Format-ParameterToken {
    param($ParameterMetadata, [switch]$Mandatory)

    $Name = $ParameterMetadata.Name
    $IsSwitch = $ParameterMetadata.ParameterType -eq [System.Management.Automation.SwitchParameter]
    $ValidateSetAttr = $ParameterMetadata.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | Select-Object -First 1

    if ($ValidateSetAttr -and $Name -notin $RuntimeDependentValidateSetParameters) {
        $TypeToken = "{{{0}}}" -f ($ValidateSetAttr.ValidValues -join " | ")
    }
    elseif ($IsSwitch) {
        $TypeToken = "<switch>"
    }
    else {
        $TypeToken = "<{0}>" -f (Get-FriendlyTypeName -Type $ParameterMetadata.ParameterType)
    }

    if ($Mandatory -and $IsSwitch) {
        return "-{0}" -f $Name
    }
    elseif ($Mandatory) {
        return "-{0} {1}" -f $Name, $TypeToken
    }
    else {
        return "[-{0} {1}]" -f $Name, $TypeToken
    }
}

function New-SyntaxSection {
    param($Command, $NativeCommand, [string]$FunctionName, [string]$NativeName, [string[]]$OmadaParameterNames)

    $Blocks = [System.Collections.Generic.List[string]]::new()
    foreach ($ParameterSet in $Command.ParameterSets) {
        $MandatoryNativeParams = $ParameterSet.Parameters | Where-Object {
            $_.IsMandatory -and $_.Name -notin $OmadaParameterNames
        }
        $OrderedMandatory = @($MandatoryNativeParams | Where-Object Name -eq "Uri") +
        @($MandatoryNativeParams | Where-Object { $_.Name -ne "Uri" } | Sort-Object Name)

        $Tokens = [System.Collections.Generic.List[string]]::new()
        $Tokens.Add($FunctionName)
        foreach ($Param in $OrderedMandatory) {
            $Tokens.Add((Format-ParameterToken -ParameterMetadata $Param -Mandatory))
        }
        foreach ($Name in $OmadaParameterNames) {
            $Tokens.Add((Format-ParameterToken -ParameterMetadata $Command.Parameters[$Name]))
        }
        $Tokens.Add("[<{0} Parameters>]" -f $NativeName)

        $Fence = '```'
        $Header = "### {0} ({1})" -f $FunctionName, $ParameterSet.Name
        $Code = $Tokens -join " "
        $BlockLines = @($Header, "", ($Fence + "powershell"), $Code, $Fence, "")
        $Blocks.Add(($BlockLines -join "`n"))
    }
    return ($Blocks -join "`n")
}

function Format-Description {
    param([string]$HelpMessage, [string]$ParameterName)

    # HelpMessage is written as plain, console-safe text (it is shown verbatim by Get-Help), using a
    # lightweight convention the markdown README rendering understands:
    #  - 'quoted terms' become `code spans`
    #  - a line starting with "IMPORTANT: " becomes a GitHub [!IMPORTANT] blockquote
    $Lines = $HelpMessage -split "`r?`n"
    $Formatted = foreach ($Line in $Lines) {
        $ConvertedLine = [regex]::Replace($Line, "'([^'\r\n]+)'", '`$1`')
        if ($ConvertedLine -match '^IMPORTANT:\s*(.*)$') {
            "> [!IMPORTANT]`n> {0}" -f $Matches[1]
        }
        else {
            $ConvertedLine
        }
    }
    $Description = $Formatted -join "`n"

    foreach ($Override in $ParameterMarkdownOverrides[$ParameterName]) {
        $Description = $Description.Replace($Override.Find, $Override.Replace)
    }
    return $Description
}

function New-ParametersSection {
    param($ParameterInfoByName)

    $Blocks = foreach ($Name in ($ParameterInfoByName.Keys | Sort-Object -Property @(
                @{ Expression = { $Index = $PreferredParameterOrder.IndexOf($_); if ($Index -lt 0) { [int]::MaxValue } else { $Index } } },
                @{ Expression = { $_ } }
            ))) {
        $Info = $ParameterInfoByName[$Name]
        $ParameterMetadata = $Info.ParameterMetadata
        $Attribute = Get-ParameterAttribute -ParameterMetadata $ParameterMetadata
        $IsSwitch = $ParameterMetadata.ParameterType -eq [System.Management.Automation.SwitchParameter]
        $TypeToken = if ($IsSwitch) { "<switch>" } else { "<{0}>" -f (Get-FriendlyTypeName -Type $ParameterMetadata.ParameterType) }

        $Description = Format-Description -HelpMessage $Attribute.HelpMessage -ParameterName $Name
        if ($Info.Functions.Count -lt $Info.TotalFunctionCount) {
            $Description += "`n`nThis parameter only applies to {0}." -f ($Info.Functions -join ", ")
        }

        $AllSetNames = @($Info.AllParameterSetNames | Sort-Object) -join "|"
        $OwnSetNames = @($ParameterMetadata.ParameterSets.Keys)
        $OwnSetNamesSorted = @($OwnSetNames | Sort-Object) -join "|"
        if ($OwnSetNames -contains "__AllParameterSets" -or $AllSetNames -eq $OwnSetNamesSorted) {
            $ParameterSetName = "(All)"
        }
        else {
            $ParameterSetName = ($OwnSetNames -join ", ")
        }

        $Aliases = if ($ParameterMetadata.Aliases.Count -gt 0) { $ParameterMetadata.Aliases -join ", " } else { "None" }
        $Required = if ($Attribute.Mandatory) { "true" } else { "false" }
        $AcceptPipeline = if ($Attribute.ValueFromPipeline) { "true (ByValue)" } elseif ($Attribute.ValueFromPipelineByPropertyName) { "true (ByPropertyName)" } else { "false" }
        $SupportsWildcards = ($ParameterMetadata.Attributes | Where-Object { $_ -is [System.Management.Automation.SupportsWildcardsAttribute] } | Measure-Object).Count -gt 0

        $Fence = '```'
        $YamlLines = @(
            "        Type: $($ParameterMetadata.ParameterType.FullName)",
            "        Required: $Required",
            "        Position: Named",
            "        Accept pipeline input: $AcceptPipeline",
            "        Parameter set name: $ParameterSetName",
            "        Aliases: $Aliases",
            "        Dynamic: true",
            "        Accept wildcard characters: $($SupportsWildcards.ToString().ToLowerInvariant())"
        )
        $ParamBlockLines = @(
            "### -$Name $TypeToken",
            $Description,
            "",
            ($Fence + "yaml")
        ) + $YamlLines + @($Fence)
        $ParamBlockLines -join "`n"
    }
    return ($Blocks -join "`n`n")
}

Import-Module $ModuleManifestPath -Force

$Manifest = Import-PowerShellDataFile $ModuleManifestPath
$SyntaxSections = [System.Collections.Generic.List[string]]::new()
$ParameterInfoByName = [ordered]@{}

foreach ($FunctionName in $Manifest.FunctionsToExport) {
    $NativeName = $NativeCommandMap[$FunctionName]
    if (-not $NativeName) {
        throw "No native command mapping registered for '$FunctionName' in `$NativeCommandMap. Update Build/Update-ReadmeHelp.ps1."
    }

    $Command = Get-Command -Name $FunctionName
    $NativeCommand = Get-Command -Name $NativeName
    $OmadaParameterNames = Get-OmadaSpecificParameterNames -Command $Command -NativeCommand $NativeCommand

    $SyntaxSections.Add((New-SyntaxSection -Command $Command -NativeCommand $NativeCommand -FunctionName $FunctionName -NativeName $NativeName -OmadaParameterNames $OmadaParameterNames))

    foreach ($Name in $OmadaParameterNames) {
        if (-not $ParameterInfoByName.Contains($Name)) {
            $ParameterInfoByName[$Name] = [ordered]@{
                ParameterMetadata  = $Command.Parameters[$Name]
                Functions          = [System.Collections.Generic.List[string]]::new()
                AllParameterSetNames = $Command.ParameterSets.Name
            }
        }
        $ParameterInfoByName[$Name].Functions.Add($FunctionName)
    }
}

foreach ($Info in $ParameterInfoByName.Values) {
    $Info.TotalFunctionCount = $Manifest.FunctionsToExport.Count
}

$SyntaxMarkdown = ($SyntaxSections -join "`n")
$ParametersMarkdown = New-ParametersSection -ParameterInfoByName $ParameterInfoByName

$ReadmeContent = Get-Content -Path $ReadmePath -Raw -Encoding UTF8

function Set-MarkerRegion {
    param([string]$Content, [string]$Marker, [string]$Replacement)

    $Pattern = "(?s)(<!-- BEGIN GENERATED $Marker -->\r?\n).*?(\r?\n<!-- END GENERATED $Marker -->)"
    if ($Content -notmatch $Pattern) {
        throw "Could not find '<!-- BEGIN GENERATED $Marker -->' / '<!-- END GENERATED $Marker -->' markers in $ReadmePath."
    }
    return [regex]::Replace($Content, $Pattern, { param($Match) $Match.Groups[1].Value + $Replacement + $Match.Groups[2].Value })
}

$ReadmeContent = Set-MarkerRegion -Content $ReadmeContent -Marker "SYNTAX" -Replacement $SyntaxMarkdown
$ReadmeContent = Set-MarkerRegion -Content $ReadmeContent -Marker "PARAMETERS" -Replacement $ParametersMarkdown

Set-Content -Path $ReadmePath -Value $ReadmeContent -Encoding UTF8 -NoNewline

"README.md regenerated: {0}" -f $ReadmePath | Write-Host -ForegroundColor Green
