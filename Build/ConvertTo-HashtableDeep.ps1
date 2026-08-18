function ConvertTo-HashtableDeep {
    <#
    .SYNOPSIS
        Converts a deserialized object graph into nested hashtables.

    .DESCRIPTION
        The build round-trips the manifest's PrivateData through ConvertTo-Json / ConvertFrom-Json
        to work around the New-ModuleManifest bug that breaks the PrivateData key
        (https://github.com/PowerShell/PowerShell/issues/5922). ConvertFrom-Json returns
        PSCustomObject graphs, and New-ModuleManifest needs hashtables, so this converts them back.

        Comparisons are made against the unwrapped object. Inside a pipeline every value is
        PSObject-wrapped, and a wrapped string satisfies "-is [PSCustomObject]":

            $Tags[0] -is [PSCustomObject]                       # False, outside a pipeline
            $Tags | ForEach-Object { $_ -is [PSCustomObject] }   # True, inside one

        Without that unwrapping, each string in an array took the PSCustomObject branch and came
        back as @{ Length = <n> }, which the manifest serializer then rendered as the literal
        "System.Collections.Hashtable". That is how the published module ended up tagged
        "System.Collections.Hashtable" instead of "Omada" and "Windows".

        Note that unwrapping $InputObject itself instead of comparing against a separate variable
        does not work: it collapses the deserialized PSData object and yields a null PSData.

    .PARAMETER InputObject
        The value to convert. Typically the output of ConvertFrom-Json.

    .EXAMPLE
        $PrivateData = ConvertTo-HashtableDeep ($Manifest.PrivateData | ConvertTo-Json -Depth 10 | ConvertFrom-Json)

        Rebuilds the manifest's PrivateData as nested hashtables, with tag arrays intact.
    #>
    param(
        $InputObject
    )

    # Compare against the unwrapped object; see the note above on PSObject wrapping in pipelines.
    $BaseObject = $InputObject
    if ($null -ne $InputObject -and $InputObject -is [System.Management.Automation.PSObject]) {
        $BaseObject = $InputObject.PSObject.BaseObject
    }

    if ($BaseObject -is [System.Collections.IEnumerable] -and $BaseObject -isnot [string]) {
        return @($BaseObject | ForEach-Object { ConvertTo-HashtableDeep $_ })
    }
    elseif ($BaseObject -is [System.Management.Automation.PSCustomObject]) {
        $Hash = @{}
        foreach ($Property in $InputObject.PSObject.Properties) {
            $Hash[$Property.Name] = ConvertTo-HashtableDeep $Property.Value
        }

        return $Hash
    }

    return $BaseObject
}
