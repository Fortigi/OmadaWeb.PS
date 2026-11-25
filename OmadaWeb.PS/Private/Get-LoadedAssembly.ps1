function Get-LoadedAssembly {
    <#
    .SYNOPSIS
        The assembly with the given simple name that is already loaded in this session, if any.

    .DESCRIPTION
        A seam over AppDomain.GetAssemblies(), so Add-ReflectionAssembly's decision can be tested
        without loading real assemblies into the test session.

    .PARAMETER Name
        The assembly's simple name, e.g. Microsoft.Web.WebView2.Core.

    .OUTPUTS
        [System.Reflection.Assembly] or nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq $Name } | Select-Object -First 1
}
