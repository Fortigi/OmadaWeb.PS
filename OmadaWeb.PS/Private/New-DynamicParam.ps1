Function New-DynamicParam {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Position', Justification = 'It is left there to be used in a later release, it is an private function so no issue for the end user.')]
    [CmdletBinding()]
    PARAM(
        [string]$Name,
        [System.Object]$Type = [string], # Accept Object to handle deserialized types
        [string[]]$Alias = @(),
        [string[]]$ValidateSet,
        $ValidateScript,
        [switch]$Mandatory,
        [string[]]$ParameterSetName = "__AllParameterSets",
        [int]$Position,
        [switch]$ValueFromPipelineByPropertyName,
        [string]$HelpMessage,
        [ValidateScript({
                if (-not ($_.GetType().FullName -eq 'System.Management.Automation.RuntimeDefinedParameterDictionary' -or -not $_)) {
                    Throw "DPDictionary must be a RuntimeDefinedParameterDictionary or null."
                }
                $True
            })]$DPDictionary = $false,
        $Value
    )

    # Ensure the Type parameter is a valid System.Type
    if (-not ($Type -is [System.Type])) {
        if ($Type -is [string]) {
            $ResolvedType = [Type]::GetType($Type) # Try to resolve the type from its name
            if (-not $ResolvedType) {
                # Try to find the type by its full name in loaded assemblies
                $ResolvedType = [AppDomain]::CurrentDomain.GetAssemblies() |
                ForEach-Object { $_.GetType($Type, $false, $false) } |
                Where-Object { $_ -ne $null }
            }
            if ($ResolvedType) {
                $Type = $ResolvedType
            }
            else {
                # Fallback to string if no match is found
                $Type = [string]
            }
        }
        else {
            Throw "The provided Type is not a valid System.Type object."
        }
    }

    # Create ParameterAttribute object
    $AttributeCollection = New-Object 'Collections.ObjectModel.Collection[System.Attribute]'
    foreach ($SetName in $ParameterSetName) {
        $ParamAttr = New-Object System.Management.Automation.ParameterAttribute
        $ParamAttr.ParameterSetName = $SetName
        if ($Mandatory) { $ParamAttr.Mandatory = $True }
        if ($ValueFromPipelineByPropertyName) { $ParamAttr.ValueFromPipelineByPropertyName = $True }
        if ($HelpMessage) { $ParamAttr.HelpMessage = $HelpMessage }

        # Create attribute collection
        $AttributeCollection.Add($ParamAttr)
    }

    # Add ValidateSet if specified
    if ($ValidateSet) {
        $ParamOptions = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $ValidateSet
        $AttributeCollection.Add($ParamOptions)
    }
    if ($ValidateScript) {
        $ParamOptions = New-Object System.Management.Automation.ValidateScriptAttribute -ArgumentList $ValidateScript
        $AttributeCollection.Add($ParamOptions)
    }

    # Add aliases if specified
    if ($Alias.Count -gt 0) {
        $ParamAlias = New-Object System.Management.Automation.AliasAttribute -ArgumentList $Alias
        $AttributeCollection.Add($ParamAlias)
    }

    # Create the dynamic parameter
    $Parameter = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameter -ArgumentList @($Name, $Type, $AttributeCollection)
    if ($Value) { $Parameter.Value = $Value }

    # Add the parameter to the dictionary
    if ($DPDictionary) {
        $DPDictionary.Add($Name, $Parameter)
    }
    else {
        $Dictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
        $Dictionary.Add($Name, $Parameter)
        $Dictionary
    }
}