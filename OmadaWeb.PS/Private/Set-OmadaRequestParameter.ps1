function Set-OmadaRequestParameter {
    [CmdletBinding()]
    PARAM(
        $FunctionObject,
        $Dictionary
    )


    #https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_commonparameters?view=powershell-7.4
    $CommonParameters = @("Debug",
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
        "WarningVariable"
    )

    $ParameterObjects = @()
    foreach ($ParameterSet in $FunctionObject.ParameterSets) {
        foreach ($Parameter in $ParameterSet.Parameters) {
            if ($Parameter.Name -notin $CommonParameters) {
                $ParameterObjects += @{
                    Name                            = $Parameter.Name
                    Type                            = $Parameter.ParameterType
                    Alias                           = $Parameter.Aliases
                    ValidateSet                     = $Parameter.ValidateSet
                    Mandatory                       = $Parameter.IsMandatory
                    ParameterSetName                = $ParameterSet.Name
                    Position                        = $Parameter.Position
                    ValueFromPipelineByPropertyName = $Parameter.ValueFromPipelineByPropertyName
                    HelpMessage                     = $Parameter.HelpMessage
                    DPDictionary                    = $Dictionary
                }
            }
        }
    }

    $ParameterObjectSets = $ParameterObjects | Group-Object -Property ParameterSetName
    [string[]]$ParameterObjectSetNames = $ParameterObjectSets.Name | Select-Object -Unique
    $UniqueParameters = @()
    foreach ($ParameterObjectSets in $ParameterObjectSets) {
        foreach ($ParameterObject in $ParameterObjectSets.Group) {
            if ($UniqueParameters.Name -notcontains $ParameterObject.Name) {
                $ParameterObject.ParameterSetName = ($ParameterObjects | Where-Object {$_.Name -eq $ParameterObject.Name} | Select-Object -ExpandProperty ParameterSetName -Unique) -Join ","
                $UniqueParameters += $ParameterObject
            }
        }
    }

    foreach ($UniqueParameter in $UniqueParameters) {
        New-DynamicParam @UniqueParameter
    }

    New-DynamicParam -Name "AuthenticationType" -Type "string" -ValidateSet ("OAuth", "Integrated", "Basic", "Browser", "Windows") -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -Value "Browser"
    New-DynamicParam -Name "OmadaWebAuthCookie" -Type "string" -ValidateSet $Script:EdgeProfiles.Name -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary
    New-DynamicParam -Name "OmadaWebAuthCookieExportLocation" -Type "string" -ValidateSet $Script:EdgeProfiles.Name -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary
    New-DynamicParam -Name "ForceAuthentication" -Type "string" -ValidateSet $Script:EdgeProfiles.Name -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary
    New-DynamicParam -Name "EdgeProfile" -Type "switch" -ValidateSet $Script:EdgeProfiles.Name -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary
    New-DynamicParam -Name "InPrivate" -Type "switch" -ValidateSet $Script:EdgeProfiles.Name -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary

    return $Dictionary
}