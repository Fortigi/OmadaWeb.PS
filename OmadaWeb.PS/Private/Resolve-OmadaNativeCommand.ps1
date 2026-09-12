function Resolve-OmadaNativeCommand {
    <#
    .SYNOPSIS
    Resolve the built-in cmdlet a request is executed through.

    .DESCRIPTION
    Every request ends up calling Invoke-RestMethod or Invoke-WebRequest, and the module resolves
    them through -FullyQualifiedModule so a function of the same name defined by the caller cannot
    take the call. That lookup has two ways of not producing a command, and only one of them used to
    be handled.

    The handled one is a throw, which is what Get-Command does when nothing matches the name at all.
    The other is a silent miss: Get-Command returns nothing, without raising anything, so the old
    catch-based recovery never saw it. The caller then read .Source off $null and, under the
    StrictMode this module runs with, the request died as "The property 'Source' cannot be found on
    this object" - a message with nothing in it to point at command resolution.

    The silent miss happens in a bare runspace - the one a background worker created with
    [powershell]::Create() gets, which is exactly what Import-OmadaSession exists to serve. There,
    the native cmdlets come from the runspace's initial session state rather than from an imported
    module: Get-Module Microsoft.PowerShell.Utility returns nothing, so a -FullyQualifiedModule
    lookup has no module to match against and yields nothing, with or without the Guid. On Windows
    PowerShell there is a second, independent reason: its Invoke-RestMethod reports version 3.0.0.0,
    below the 3.1.0.0 the specification asks for, so that filter cannot match in such a runspace
    however the module is loaded.

    So resolution is tried three ways, narrowest first:

      1. The fully qualified lookup, unchanged, which is what succeeds in an ordinary session.
      2. The same lookup after importing the module explicitly, which recovers the case where it
         simply had not been loaded yet.
      3. A lookup scoped to the module by name, restricted to cmdlets.

    Step 3 is what makes a bare runspace work. It keeps the property the qualified lookup exists for
    - that a function the caller happens to have defined called Invoke-RestMethod cannot take the
    call - because the result still has to be a cmdlet belonging to Microsoft.PowerShell.Utility.
    What it gives up is the version floor, which in that runspace was never satisfiable anyway.

    Only if all three produce nothing does the request stop, with an error that names what could not
    be resolved.

    .PARAMETER Name
    The command to resolve, such as "Invoke-RestMethod".

    .PARAMETER FullyQualifiedModule
    The module specification to resolve it through, as built in OmadaWeb.PS.psm1.

    .OUTPUTS
    [System.Management.Automation.CommandInfo]. Never $null - the function throws instead.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.CommandInfo])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$FullyQualifiedModule
    )

    # Wrapped in @() so a silent miss and a throw arrive as the same thing - an empty result - rather
    # than as $null in one case and an exception in the other.
    $Command = $null
    try {
        $Command = @(Get-Command $Name -FullyQualifiedModule $FullyQualifiedModule -ErrorAction Stop) | Select-Object -First 1
    }
    catch {
        "{0} - '{1}' did not resolve through {2}: {3}" -f $MyInvocation.MyCommand, $Name, $FullyQualifiedModule.ModuleName, $PSItem.Exception.Message | Write-Verbose
    }

    if ($null -ne $Command) {
        return $Command
    }

    "{0} - Importing '{1}' so '{2}' can be resolved" -f $MyInvocation.MyCommand, $FullyQualifiedModule.ModuleName, $Name | Write-Verbose
    try {
        # -FullyQualifiedName rather than name plus a version floor, which is what this line used to
        # do: the specification carries the Guid as well, so the module that gets imported is the
        # same one the lookup above and below filter on. Importing by name alone could bring in a
        # different module that happens to share it, and then step 3 would resolve against that.
        # OmadaWeb.PS.psm1 imports the same specification the same way at load.
        Import-Module -FullyQualifiedName $FullyQualifiedModule -Force -ErrorAction Stop
        $Command = @(Get-Command $Name -FullyQualifiedModule $FullyQualifiedModule -ErrorAction SilentlyContinue) | Select-Object -First 1
    }
    catch {
        # Not fatal on its own: step 3 below can still resolve the command in a runspace where the
        # cmdlets come from the initial session state and there is no module to import.
        "{0} - Could not import '{1}': {2}" -f $MyInvocation.MyCommand, $FullyQualifiedModule.ModuleName, $PSItem.Exception.Message | Write-Verbose
    }

    if ($null -ne $Command) {
        return $Command
    }

    # -CommandType Cmdlet is what keeps this as safe as the qualified lookup: a function the caller
    # defined cannot satisfy it, and the .Source check below keeps the answer inside the module the
    # caller asked for.
    "{0} - Falling back to a module-scoped lookup for '{1}'" -f $MyInvocation.MyCommand, $Name | Write-Verbose
    $Command = @(Get-Command -Name $Name -Module $FullyQualifiedModule.ModuleName -CommandType Cmdlet -ErrorAction SilentlyContinue) |
        Where-Object { $_.Source -eq $FullyQualifiedModule.ModuleName } |
        Select-Object -First 1

    if ($null -eq $Command) {
        "Could not resolve '{0}' from module '{1}'. This PowerShell session cannot make web requests." -f $Name, $FullyQualifiedModule.ModuleName | Write-Error -ErrorAction "Stop"
    }

    return $Command
}
