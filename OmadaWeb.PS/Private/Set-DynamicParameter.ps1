function Set-DynamicParameter {
    [CmdletBinding()]
    PARAM(
        $FunctionName
    )
    $Dictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
    $FunctionObject = Get-Command -Name $FunctionName

    #https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_commonparameters?view=powershell-7.4
    $ExcludedParameters = @("Debug",
        "ErrorAction",
        "ErrorVariable",
        "InformationAction",
        "InformationVariable",
        "OutVariable",
        "OutBuffer",
        "PipelineVariable",
        "ProgressAction",
        "Verbose",
        "WarningAction",
        "WarningVariable",
        "Session",
        "WebSession",
        "Authentication",
        "SessionVariable",
        "UseDefaultCredentials",
        "UseBasicParsing"
    )

    $ParameterObjects = @()
    foreach ($ParameterSet in $FunctionObject.ParameterSets) {
        foreach ($Parameter in $ParameterSet.Parameters) {
            if ($Parameter.Name -notin $ExcludedParameters) {
                if ($Parameter.Name -notin $ParameterObjects.Name) {
                    $ParameterSetName = @($($ParameterSet.Name))
                    $ParameterObjects += @{
                        Name                            = $Parameter.Name
                        Type                            = $Parameter.ParameterType
                        Alias                           = $Parameter.Aliases
                        ValidateSet                     = $Parameter.ValidateSet
                        Mandatory                       = $Parameter.IsMandatory
                        ParameterSetName                = $ParameterSetName
                        Position                        = $Parameter.Position
                        ValueFromPipelineByPropertyName = $Parameter.ValueFromPipelineByPropertyName
                        HelpMessage                     = $Parameter.HelpMessage
                        DPDictionary                    = $Dictionary
                    }
                }
                else {
                    ($ParameterObjects | Where-Object {$_.Name -eq $Parameter.Name}).ParameterSetName += $($ParameterSet.Name)
                }
            }
        }
    }

    [string[]]$ParameterObjectSetNames = $null
    if (($ParameterObjects.ParameterSetName | Select-Object -Unique | Measure-Object).Count -eq 1 -and [string]::IsNullOrWhiteSpace($ParameterObjects.ParameterSetName)) {
        $ParameterObjectSetNames += "__AllParameterSets"
        $ParameterObjects | ForEach-Object { $_.ParameterSetName = "__AllParameterSets" }
    }
    else {
        $ParameterObjectSetNames += $ParameterObjects.ParameterSetName | Select-Object -Unique
    }

    foreach ($ParameterObject in $ParameterObjects) {
        New-DynamicParam @ParameterObject
    }

    New-DynamicParam -Name "AuthenticationType" -Type "string" -ValidateSet ("OAuth", "Integrated", "Basic", "Browser", "Windows") -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -Value "Browser" -HelpMessage "The type of authentication to use for the request. Default is `Browser`. The acceptable values for this parameter are:
- Basic
- Browser
- Integrated
- OAuth
- Windows"
    New-DynamicParam -Name "EntraIdTenantId" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "The tenant id or name for -AuthenticationType OAuth." -Alias "AzureAdTenantId"
    New-DynamicParam -Name "OmadaWebAuthCookieFile" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Use a previously exported Omada authentication cookie using -OmadaWebAuthCookieExportLocation. This must be to the cookie file." -ValidateScript { Test-Path -Path $_ }
    New-DynamicParam -Name "OmadaWebAuthCookieExportLocation" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Export the Omada authentication cookie to as a CliXml file."
    New-DynamicParam -Name "ForceAuthentication" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Force authentication to Omada even when the cookie is still valid."
    New-DynamicParam -Name "EdgeProfile" -Type "string" -ValidateSet $Script:EdgeProfiles.Name -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Use the specified Edge profile for the authentication request."
    New-DynamicParam -Name "InPrivate" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Use InPrivate mode for the authentication request."

    return $Dictionary
}