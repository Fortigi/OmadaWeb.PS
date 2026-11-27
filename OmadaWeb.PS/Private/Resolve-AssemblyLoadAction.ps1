function Resolve-AssemblyLoadAction {
    <#
    .SYNOPSIS
        Decides what to do when an assembly is about to be loaded from a file and one with the same
        name may already be in the session.

    .DESCRIPTION
        PowerShell 7 (.NET) loads every assembly into one load context, and a strong-named assembly
        can be loaded there in one version only. When another module in the same session has already
        loaded a newer Microsoft.Web.WebView2.Core than the one this module bundles, Assembly.LoadFrom
        of the bundled file fails with "A different copy of assembly ... is already loaded" - and
        signing in with WebView2 fails with it. OmadaSqlTroubleshooter does exactly that: it loads its
        own pinned WebView2 at start-up and calls this module to sign in later.

          Load      Nothing by that name is loaded: load the file.
          Reuse     The loaded version is the same or newer: use it. WebView2 keeps its .NET API
                    backward compatible, so code built against an older version runs on a newer one.
          Conflict  The loaded version is older than the file. It cannot be replaced in a running
                    session and running on it is not safe, so the caller reports it.

        Pure, so the decision is tested without loading anything.

    .PARAMETER RequestedVersion
        The version of the assembly file about to be loaded.

    .PARAMETER LoadedVersion
        The version already loaded under the same name, or $null when none is.

    .OUTPUTS
        [string] Load, Reuse or Conflict.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [version]$RequestedVersion,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [version]$LoadedVersion
    )

    if ($null -eq $LoadedVersion) {
        return "Load"
    }

    if ($LoadedVersion -ge $RequestedVersion) {
        return "Reuse"
    }

    return "Conflict"
}
