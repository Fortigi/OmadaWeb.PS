function ConvertTo-HashtableDeep {
    <#
    .SYNOPSIS
        Converts a deserialized object graph into nested hashtables.

    .DESCRIPTION
        The build round-trips the manifest's PrivateData through ConvertTo-Json / ConvertFrom-Json
        to work around the New-ModuleManifest bug that breaks the PrivateData key
        (https://github.com/PowerShell/PowerShell/issues/5922). ConvertFrom-Json returns
        PSCustomObject graphs, and New-ModuleManifest needs hashtables, so this converts them back.

        The object test is [System.Management.Automation.PSCustomObject], not the [PSCustomObject]
        accelerator. That distinction is the actual fix. [PSCustomObject] resolves to PSObject, the
        wrapper the pipeline puts around every value, so a wrapped string matched it:

            $Tags[0] -is [PSCustomObject]                       # False, outside a pipeline
            $Tags | ForEach-Object { $_ -is [PSCustomObject] }   # True, inside one

        Each string in an array therefore took the object branch, was enumerated into
        @{ Length = <n> }, and the manifest serializer rendered that as the literal
        "System.Collections.Hashtable". That is how the published module ended up tagged
        "System.Collections.Hashtable" instead of "Omada" and "Windows".

        The unwrapping below is a second guard: it keeps the enumerable test and the returned
        scalar working on the underlying value. Note that reassigning $InputObject itself rather
        than using a separate variable does not work - property enumeration then loses the
        deserialized PSData object and yields a null PSData.

    .PARAMETER InputObject
        The value to convert. Typically the output of ConvertFrom-Json.

    .EXAMPLE
        $PrivateData = ConvertTo-HashtableDeep ($Manifest.PrivateData | ConvertTo-Json -Depth 10 | ConvertFrom-Json)

        Rebuilds the manifest's PrivateData as nested hashtables, with tag arrays intact.
    #>
    param(
        $InputObject
    )

    # Unwrap so the branch tests and the returned scalar see the underlying value rather than the
    # PSObject wrapper the pipeline adds.
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
