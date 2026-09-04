function Get-InstalledModuleInfo {
    [CmdletBinding()]
    param(
        [string]$ModuleName
    )

    "{0} - Getting installed module info for: {1}" -f $MyInvocation.MyCommand, $ModuleName | Write-Verbose
    $CallStack = Get-PSCallStack
    $ModuleStack = $CallStack | Where-Object { $_.Command -eq ("{0}.psm1" -f $ModuleName) }

    $Module = Get-Module -ListAvailable -Name $ModuleName | ForEach-Object {$_ | Where-Object { (Split-Path $_.Path) -eq (Split-Path $ModuleStack.ScriptName) }} | Sort-Object Version -Descending | Select-Object -First 1
    if ($Module) {
        # A prerelease install reports its numeric version in $Module.Version and keeps the tag that
        # makes it a prerelease - "nightly74" - in the manifest's PSData. That is the only place the
        # channel of the installation can be read from, and on a stable install the key is simply
        # absent: PSData then holds nothing but Tags, ProjectUri, LicenseUri and
        # ExternalModuleDependencies. Both levels are plain hashtables, so they are probed with
        # Contains rather than by member access, which under Set-StrictMode -Version Latest would
        # turn a stable installation into an error.
        $PrereleaseTag = $null
        $PrivateData = $Module.PrivateData
        if ($PrivateData -is [System.Collections.IDictionary] -and $PrivateData.Contains("PSData")) {
            $PsData = $PrivateData["PSData"]
            if ($PsData -is [System.Collections.IDictionary] -and $PsData.Contains("Prerelease")) {
                $PrereleaseTag = $PsData["Prerelease"]
            }
        }

        if ([string]::IsNullOrWhiteSpace($PrereleaseTag)) {
            $PrereleaseTag = $null
            $FullVersion = "{0}" -f $Module.Version
        }
        else {
            $FullVersion = "{0}-{1}" -f $Module.Version, $PrereleaseTag
        }

        $ModuleInfo = @{
            Name             = $Module.Name
            Version          = $Module.Version
            RepositorySource = $Module.RepositorySourceLocation
            Prerelease       = $PrereleaseTag
            FullVersion      = $FullVersion
        }
        return $ModuleInfo
    }
    else {
        return $null
    }
}