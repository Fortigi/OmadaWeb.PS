function Get-AssemblyFileName {
    <#
    .SYNOPSIS
        Reads the identity (name and version) of an assembly file without loading it.

    .DESCRIPTION
        A seam over AssemblyName.GetAssemblyName, so Add-ReflectionAssembly can be tested with any
        version without real assembly files.

    .PARAMETER Path
        The assembly file.

    .OUTPUTS
        [System.Reflection.AssemblyName]
    #>
    [CmdletBinding()]
    [OutputType([System.Reflection.AssemblyName])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return [System.Reflection.AssemblyName]::GetAssemblyName($Path)
}
