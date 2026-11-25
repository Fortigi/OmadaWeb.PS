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
                if (Test-AssemblyAlreadyLoaded -Path $Object) {
                    return
                }
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
        else { $PSCmdlet.ThrowTerminatingError($PSItem) }
    }
}

function Test-AssemblyAlreadyLoaded {
    <#
    .SYNOPSIS
        Whether an assembly file need not be loaded because the session already holds a usable
        version of it; throws when the session holds an older one.

    .DESCRIPTION
        See Resolve-AssemblyLoadAction for why. Only files are considered: a name that is not an
        existing file is left to Assembly.LoadFrom, unchanged.

        In this file, not one of its own, because it exists only for Add-ReflectionAssembly.

    .PARAMETER Path
        The assembly file about to be loaded.

    .OUTPUTS
        [bool] $true to skip loading (a usable version is loaded), $false to load the file.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $Requested = Get-AssemblyFileName -Path $Path
    $Loaded = Get-LoadedAssembly -Name $Requested.Name
    $LoadedVersion = if ($null -ne $Loaded) { $Loaded.GetName().Version } else { $null }

    switch (Resolve-AssemblyLoadAction -RequestedVersion $Requested.Version -LoadedVersion $LoadedVersion) {
        "Reuse" {
            "{0} - '{1}' {2} is already loaded from '{3}'; using it instead of {4} from '{5}'" -f $MyInvocation.MyCommand, $Requested.Name, $LoadedVersion, $Loaded.Location, $Requested.Version, $Path | Write-Verbose
            return $true
        }
        "Conflict" {
            throw ("'{0}' {1} is already loaded in this PowerShell session from '{2}', which is older than the {3} this module needs. .NET cannot load a second version of an assembly into a running session. Start a new PowerShell session, or update the module that loaded the older version." -f $Requested.Name, $LoadedVersion, $Loaded.Location, $Requested.Version)
        }
    }

    return $false
}
