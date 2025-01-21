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
    New-DynamicParam -Name "CookiePath" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Attempts to load a stored Omada authentication cookie from this path. This file will be updated re-authentication is needed. If the file does not exist, it will be created after successful authentication. When this option is used, an encrypted cookie is not cached. IMPORTANT: Be aware that an unencrypted version of the session cookie is stored on the file system. This parameter only applies in combination with parameter -AuthenticationMethod Browser. Make sure it is stored at a secure location so it cannot be accessed by unauthorized users."
    New-DynamicParam -Name "SkipCookieCache" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Do not cache the encrypted Omada authentication cookie. It wil also not be cached when -CookiePath is used. This parameter only applies in combination with parameter -AuthenticationMethod Browser."
    New-DynamicParam -Name "ForceAuthentication" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Force authentication to Omada even when the cookie is still valid."
    New-DynamicParam -Name "EdgeProfile" -Type "string" -ValidateSet $Script:EdgeProfiles.Name -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Use the specified Edge profile for the authentication request."
    New-DynamicParam -Name "InPrivate" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Use InPrivate mode for the authentication request."

    return $Dictionary
}