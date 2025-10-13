function Add-ReflectionAssembly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
            Position = 0,
            HelpMessage = "Path or name of the assembly to load")]
        [String]$Object,
        [Parameter(Mandatory = $false,
            Position = 1,
            HelpMessage = "Load type: LoadFrom (default) or LoadFile")]
        [ValidateSet("LoadFrom", "LoadFile", "LoadWithPartialName")]
        [String]$Type = "LoadFrom"
    )

    try {
        "{0} - Loading assembly: {1} (Type: {2})" -f $MyInvocation.MyCommand, $Object, $Type | Write-Verbose
        switch ($Type) {
            "LoadFrom" {
                [void][Reflection.Assembly]::LoadFrom($Object)
            }
            "LoadWithPartialName" {
                [void][Reflection.Assembly]::LoadWithPartialName($Object)
            }
            default {
                [void][Reflection.Assembly]::LoadFile($Object)
            }
        }
    }
    catch {
        if ($_.Exception.Message -like '*Assembly with same name is already loaded*') {}
        else { throw $_.Exception.Message }
    }
}