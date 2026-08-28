#Requires -Version 7.0
#Requires -PSEdition Core

<#
.SYNOPSIS
    Regenerates the COMMANDS, SYNTAX, EXAMPLES and PARAMETERS sections of README.md from the live
    OmadaWeb.PS module.
.DESCRIPTION
    The README is generated from the module so that help is written once and cannot drift. It is read
    from two sources, because the module's commands document themselves in two different ways:

      - Comment-based help in OmadaWeb.PS/Public/*.ps1 supplies the synopsis, description and examples
        of every exported command, and the parameter descriptions of commands that declare their
        parameters normally. This is the same help Get-Help shows.
      - -HelpMessage strings on the New-DynamicParam calls in
        OmadaWeb.PS/Private/Set-DynamicParameter.ps1 supply the parameter descriptions of the
        Invoke-Omada* wrappers, whose parameters are all added at runtime via DynamicParam and so
        cannot carry comment-based .PARAMETER entries. Get-Help reads the same strings.

    The script imports the module and reflects over the resulting Get-Command output (which resolves
    the dynamic parameters and mirrors the real parameter sets of Invoke-RestMethod/Invoke-WebRequest),
    then rewrites the generated regions of README.md - delimited by "<!-- BEGIN GENERATED ... -->" /
    "<!-- END GENERATED ... -->" comments - so hand-written prose elsewhere in the file is never
    touched.

    Run this after changing comment-based help in OmadaWeb.PS/Public/*.ps1 or dynamic parameters in
    OmadaWeb.PS/Private/Set-DynamicParameter.ps1.

    Note: the real parameter sets (StandardMethod/StandardMethodNoProxy/CustomMethod/CustomMethodNoProxy)
    only exist on PowerShell 7's Invoke-RestMethod/Invoke-WebRequest - Windows PowerShell 5.1's versions
    only expose __AllParameterSets. This script requires PowerShell 7 so the generated SYNTAX reflects
    the real set structure.
#>
[CmdletBinding()]
param(
    [string]$ModuleManifestPath = (Join-Path $PSScriptRoot "..\OmadaWeb.PS\OmadaWeb.PS.psd1"),
    [string]$ReadmePath = (Join-Path $PSScriptRoot "..\README.md"),
    [string]$PublicCommandsPath = (Join-Path $PSScriptRoot "PublicCommands.psd1")
)

$ErrorActionPreference = "Stop"

# Maps each exported function to the native cmdlet it wraps (mirroring the $Script:FunctionName
# assignment inside that function's DynamicParam block), or to an empty string when it is a command
# in its own right. Shared with Build/Test-CommentBasedHelp.ps1.
$NativeCommandMap = (Import-PowerShellDataFile -Path $PublicCommandsPath).WrappedCommands

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
    "Paged",
    "MaximumRetryCount",
    "RetryIntervalSec"
)

# Parameters the module declares itself in Set-DynamicParameter.ps1 even though the wrapped native
# cmdlet happens to declare one of the same name. Without this list they would be classified as
# inherited and disappear from the generated documentation, because the "Omada-specific" test is
# "not a parameter of the native cmdlet". That test is right for everything else, but wrong here:
# PowerShell 7's Invoke-RestMethod/Invoke-WebRequest have MaximumRetryCount and RetryIntervalSec
# while Windows PowerShell 5.1's do not, so documenting them as inherited would both hide them and
# describe them incorrectly - the module supplies them on both engines, with its own semantics.
$ModuleOwnedParameterNames = @(
    "MaximumRetryCount",
    "RetryIntervalSec"
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
    $Names = $Command.Parameters.Keys | Where-Object { $_ -notin $NativeCommand.Parameters.Keys -or $_ -in $ModuleOwnedParameterNames }
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
    param($Command, [string]$FunctionName, [string]$NativeName, [string[]]$OmadaParameterNames)

    $Blocks = [System.Collections.Generic.List[string]]::new()
    foreach ($ParameterSet in $Command.ParameterSets) {
        $Tokens = [System.Collections.Generic.List[string]]::new()
        $Tokens.Add($FunctionName)

        if ([string]::IsNullOrWhiteSpace($NativeName)) {
            # A command in its own right: every parameter it declares is listed, since there is no
            # native cmdlet whose documentation the reader can be sent to for the rest.
            foreach ($Param in $ParameterSet.Parameters) {
                if ($Param.Name -in $CommonParameterNames) {
                    continue
                }
                $Tokens.Add((Format-ParameterToken -ParameterMetadata $Param -Mandatory:$Param.IsMandatory))
            }
            $Tokens.Add("[<CommonParameters>]")
        }
        else {
            $MandatoryNativeParams = $ParameterSet.Parameters | Where-Object {
                $_.IsMandatory -and $_.Name -notin $OmadaParameterNames
            }
            $OrderedMandatory = @($MandatoryNativeParams | Where-Object Name -eq "Uri") +
            @($MandatoryNativeParams | Where-Object { $_.Name -ne "Uri" } | Sort-Object Name)

            foreach ($Param in $OrderedMandatory) {
                $Tokens.Add((Format-ParameterToken -ParameterMetadata $Param -Mandatory))
            }
            foreach ($Name in $OmadaParameterNames) {
                $Tokens.Add((Format-ParameterToken -ParameterMetadata $Command.Parameters[$Name]))
            }
            $Tokens.Add("[<{0} Parameters>]" -f $NativeName)
        }

        $Fence = '```'
        $Header = "### {0} ({1})" -f $FunctionName, $ParameterSet.Name
        $Code = $Tokens -join " "
        $BlockLines = @($Header, "", ($Fence + "powershell"), $Code, $Fence, "")
        $Blocks.Add(($BlockLines -join "`n"))
    }
    return ($Blocks -join "`n")
}

function Format-Paragraph {
    param([string]$Text)

    # Comment-based help is hard-wrapped for the console, but markdown treats a single newline as a
    # space, so the wrapping has to be undone or the README renders with ragged lines. List items are
    # the exception: each one has to keep its own line to stay a list.
    $LogicalLines = [System.Collections.Generic.List[string]]::new()
    foreach ($Line in ($Text -split "\r?\n")) {
        $Trimmed = $Line.Trim()
        if ([string]::IsNullOrWhiteSpace($Trimmed)) {
            continue
        }
        if ($LogicalLines.Count -eq 0 -or $Trimmed -match "^([-*+]|\d+\.)\s") {
            $LogicalLines.Add($Trimmed)
        }
        else {
            $LogicalLines[$LogicalLines.Count - 1] = "{0} {1}" -f $LogicalLines[$LogicalLines.Count - 1], $Trimmed
        }
    }
    return ($LogicalLines -join "`n")
}

function New-CommandsSection {
    param($HelpByFunctionName)

    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add("| Command | Description |")
    $Lines.Add("|---|---|")
    foreach ($FunctionName in $HelpByFunctionName.Keys) {
        $Synopsis = ($HelpByFunctionName[$FunctionName].Synopsis | Out-String).Trim() -replace "\s*\r?\n\s*", " "
        $Lines.Add(("| [``{0}``](#{1}) | {2} |" -f $FunctionName, $FunctionName.ToLowerInvariant(), $Synopsis))
    }
    return ($Lines -join "`n")
}

function New-ExamplesSection {
    param($HelpByFunctionName)

    $Fence = '```'
    $Blocks = [System.Collections.Generic.List[string]]::new()

    foreach ($FunctionName in $HelpByFunctionName.Keys) {
        $Help = $HelpByFunctionName[$FunctionName]
        $Blocks.Add(("### {0}`n" -f $FunctionName))

        $Description = ($Help.Description | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($Description)) {
            $Paragraphs = $Description -split "\r?\n\s*\r?\n" | ForEach-Object { Format-Paragraph -Text $_ }
            $Blocks.Add((($Paragraphs -join "`n`n") + "`n"))
        }

        $ExampleNumber = 0
        foreach ($Example in @($Help.Examples.Example)) {
            $ExampleNumber++
            $Code = ($Example.code | Out-String).Trim()
            $Remarks = @($Example.remarks | ForEach-Object { $_.Text } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $RemarkText = Format-Paragraph -Text ($Remarks -join "`n")

            $Blocks.Add(("#### Example {0}`n" -f $ExampleNumber))
            $Blocks.Add((@(($Fence + "powershell"), $Code, $Fence) -join "`n") + "`n")
            if (-not [string]::IsNullOrWhiteSpace($RemarkText)) {
                $Blocks.Add($RemarkText + "`n")
            }
        }
    }

    return (($Blocks -join "`n").TrimEnd())
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
    param($ParameterInfoByName, [switch]$Dynamic, [string]$HeadingPrefix = "####")

    $Blocks = foreach ($Name in ($ParameterInfoByName.Keys | Sort-Object -Property @(
                @{ Expression = { $Index = $PreferredParameterOrder.IndexOf($_); if ($Index -lt 0) { [int]::MaxValue } else { $Index } } },
                @{ Expression = { $_ } }
            ))) {
        $Info = $ParameterInfoByName[$Name]
        $ParameterMetadata = $Info.ParameterMetadata
        $Attribute = Get-ParameterAttribute -ParameterMetadata $ParameterMetadata
        $IsSwitch = $ParameterMetadata.ParameterType -eq [System.Management.Automation.SwitchParameter]
        $TypeToken = if ($IsSwitch) { "<switch>" } else { "<{0}>" -f (Get-FriendlyTypeName -Type $ParameterMetadata.ParameterType) }

        $Description = Format-Description -HelpMessage $Info.HelpText -ParameterName $Name
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
            "        Dynamic: $($Dynamic.IsPresent.ToString().ToLowerInvariant())",
            "        Accept wildcard characters: $($SupportsWildcards.ToString().ToLowerInvariant())"
        )
        $ParamBlockLines = @(
            "$HeadingPrefix -$Name $TypeToken",
            $Description,
            "",
            ($Fence + "yaml")
        ) + $YamlLines + @($Fence)
        $ParamBlockLines -join "`n"
    }
    return ($Blocks -join "`n`n")
}

Import-Module $ModuleManifestPath -Force

$CommonParameterNames = @([System.Management.Automation.Cmdlet]::CommonParameters)
$OptionalCommonParameterNames = @([System.Management.Automation.Cmdlet]::OptionalCommonParameters)

$Manifest = Import-PowerShellDataFile $ModuleManifestPath
$SyntaxSections = [System.Collections.Generic.List[string]]::new()
$StandaloneParameterSections = [System.Collections.Generic.List[string]]::new()
$HelpByFunctionName = [ordered]@{}
$ParameterInfoByName = [ordered]@{}
$WrapperFunctionNames = [System.Collections.Generic.List[string]]::new()

foreach ($FunctionName in $Manifest.FunctionsToExport) {
    if (-not $NativeCommandMap.ContainsKey($FunctionName)) {
        throw "'$FunctionName' is exported but not listed in $PublicCommandsPath. Add it, mapping it to the cmdlet it wraps or to an empty string."
    }
    $NativeName = $NativeCommandMap[$FunctionName]

    $Command = Get-Command -Name $FunctionName
    $HelpByFunctionName[$FunctionName] = Get-Help -Name $FunctionName -Full

    if ([string]::IsNullOrWhiteSpace($NativeName)) {
        # A command in its own right: its parameters are declared normally, so their descriptions
        # come from the .PARAMETER entries in its comment-based help.
        $SyntaxSections.Add((New-SyntaxSection -Command $Command -FunctionName $FunctionName -NativeName "" -OmadaParameterNames @()))

        $OwnParameterInfo = [ordered]@{}
        foreach ($Name in $Command.Parameters.Keys) {
            # -WhatIf and -Confirm are listed in the syntax, because whether a command supports them
            # is worth knowing, but they are documented by PowerShell itself rather than here.
            if ($Name -in $CommonParameterNames -or $Name -in $OptionalCommonParameterNames) {
                continue
            }
            $ParameterHelp = $HelpByFunctionName[$FunctionName].parameters.parameter | Where-Object { $_.name -eq $Name } | Select-Object -First 1
            $OwnParameterInfo[$Name] = [ordered]@{
                ParameterMetadata    = $Command.Parameters[$Name]
                HelpText             = (($ParameterHelp.description | ForEach-Object { $_.Text }) -join "`n").Trim()
                Functions            = [System.Collections.Generic.List[string]]::new()
                AllParameterSetNames = $Command.ParameterSets.Name
                TotalFunctionCount   = 1
            }
            $OwnParameterInfo[$Name].Functions.Add($FunctionName)
        }

        $StandaloneParameterSections.Add(("### {0} parameters`n`n{1}" -f $FunctionName, (New-ParametersSection -ParameterInfoByName $OwnParameterInfo)))
        continue
    }

    $WrapperFunctionNames.Add($FunctionName)
    $NativeCommand = Get-Command -Name $NativeName
    $OmadaParameterNames = Get-OmadaSpecificParameterNames -Command $Command -NativeCommand $NativeCommand

    $SyntaxSections.Add((New-SyntaxSection -Command $Command -FunctionName $FunctionName -NativeName $NativeName -OmadaParameterNames $OmadaParameterNames))

    foreach ($Name in $OmadaParameterNames) {
        if (-not $ParameterInfoByName.Contains($Name)) {
            $Attribute = Get-ParameterAttribute -ParameterMetadata $Command.Parameters[$Name]
            $ParameterInfoByName[$Name] = [ordered]@{
                ParameterMetadata    = $Command.Parameters[$Name]
                HelpText             = $Attribute.HelpMessage
                Functions            = [System.Collections.Generic.List[string]]::new()
                AllParameterSetNames = $Command.ParameterSets.Name
            }
        }
        $ParameterInfoByName[$Name].Functions.Add($FunctionName)
    }
}

foreach ($Info in $ParameterInfoByName.Values) {
    $Info.TotalFunctionCount = $WrapperFunctionNames.Count
}

$SyntaxMarkdown = ($SyntaxSections -join "`n")
$CommandsMarkdown = New-CommandsSection -HelpByFunctionName $HelpByFunctionName
$ExamplesMarkdown = New-ExamplesSection -HelpByFunctionName $HelpByFunctionName

$ParametersMarkdown = "### {0} parameters`n`nThese are added on top of the parameters of the wrapped cmdlet and are the same for both commands, unless stated otherwise.`n`n{1}" -f ($WrapperFunctionNames -join " and "), (New-ParametersSection -ParameterInfoByName $ParameterInfoByName -Dynamic)
if ($StandaloneParameterSections.Count -gt 0) {
    $ParametersMarkdown += "`n`n" + ($StandaloneParameterSections -join "`n`n")
}

$ReadmeContent = Get-Content -Path $ReadmePath -Raw -Encoding UTF8

function Set-MarkerRegion {
    param([string]$Content, [string]$Marker, [string]$Replacement)

    $Pattern = "(?s)(<!-- BEGIN GENERATED $Marker -->\r?\n).*?(\r?\n<!-- END GENERATED $Marker -->)"
    if ($Content -notmatch $Pattern) {
        throw "Could not find '<!-- BEGIN GENERATED $Marker -->' / '<!-- END GENERATED $Marker -->' markers in $ReadmePath."
    }
    return [regex]::Replace($Content, $Pattern, { param($Match) $Match.Groups[1].Value + $Replacement + $Match.Groups[2].Value })
}

$ReadmeContent = Set-MarkerRegion -Content $ReadmeContent -Marker "COMMANDS" -Replacement $CommandsMarkdown
$ReadmeContent = Set-MarkerRegion -Content $ReadmeContent -Marker "SYNTAX" -Replacement $SyntaxMarkdown
$ReadmeContent = Set-MarkerRegion -Content $ReadmeContent -Marker "EXAMPLES" -Replacement $ExamplesMarkdown
$ReadmeContent = Set-MarkerRegion -Content $ReadmeContent -Marker "PARAMETERS" -Replacement $ParametersMarkdown

Set-Content -Path $ReadmePath -Value $ReadmeContent -Encoding UTF8 -NoNewline

"README.md regenerated: {0}" -f $ReadmePath | Write-Host -ForegroundColor Green
