function Get-DependencyLock {
    [CmdletBinding()]
    PARAM()

    # Cached for the lifetime of the module: the lock is read on every download and never changes
    # while a session runs.
    if ($null -ne $Script:DependencyLock) {
        return $Script:DependencyLock
    }

    "{0} - Loading dependency lock from '{1}'" -f $MyInvocation.MyCommand, $Script:DependencyLockPath | Write-Verbose

    if ([string]::IsNullOrWhiteSpace($Script:DependencyLockPath) -or -not (Test-Path $Script:DependencyLockPath -PathType Leaf)) {
        "The dependency lock file '{0}' is missing. It ships with the module and holds the pinned version and expected SHA-256 of every binary the module downloads, so nothing can be verified without it. Reinstall the module with 'Update-Module -Name OmadaWeb.PS' or 'Install-Module -Name OmadaWeb.PS -Force'." -f $Script:DependencyLockPath | Write-Error -ErrorAction "Stop"
    }

    # Read through the language parser rather than Import-PowerShellDataFile. SafeGetValue gives the
    # same guarantee - it evaluates constant expressions only, so a data file can never execute code -
    # but it depends on nothing outside the engine. Import-PowerShellDataFile comes from
    # Microsoft.PowerShell.Utility, and on a machine where a newer PowerShell has leaked its module
    # directory onto Windows PowerShell 5.1's PSModulePath that cmdlet resolves to an assembly 5.1
    # cannot load. Every download would then fail closed for a reason that has nothing to do with the
    # integrity of the download.
    try {
        $ParseErrors = $null
        $Tokens = $null
        $LockAst = [System.Management.Automation.Language.Parser]::ParseFile($Script:DependencyLockPath, [ref]$Tokens, [ref]$ParseErrors)
        if (($ParseErrors | Measure-Object).Count -gt 0) {
            throw ($ParseErrors | ForEach-Object { $_.Message }) -join "; "
        }

        $HashtableAst = $LockAst.Find({ param($Node) $Node -is [System.Management.Automation.Language.HashtableAst] }, $false)
        if ($null -eq $HashtableAst) {
            throw "the file does not contain a hashtable"
        }

        $Lock = $HashtableAst.SafeGetValue()
    }
    catch {
        "The dependency lock file '{0}' could not be read and no download can be verified without it. Reinstall the module with 'Update-Module -Name OmadaWeb.PS'. Error:`r`n {1}" -f $Script:DependencyLockPath, $_.Exception.Message | Write-Error -ErrorAction "Stop"
    }

    if (-not $Lock.ContainsKey("SchemaVersion") -or $Lock.SchemaVersion -ne 1) {
        "The dependency lock file '{0}' has schema version '{1}', but this version of OmadaWeb.PS only understands schema version 1. Reinstall the module with 'Update-Module -Name OmadaWeb.PS'." -f $Script:DependencyLockPath, $Lock.SchemaVersion | Write-Error -ErrorAction "Stop"
    }

    if (-not $Lock.ContainsKey("Artifacts") -or ($Lock.Artifacts | Measure-Object).Count -eq 0) {
        "The dependency lock file '{0}' lists no artefacts, so every download would be refused. Reinstall the module with 'Update-Module -Name OmadaWeb.PS'." -f $Script:DependencyLockPath | Write-Error -ErrorAction "Stop"
    }

    "{0} - Dependency lock loaded, {1} artefact(s) pinned" -f $MyInvocation.MyCommand, ($Lock.Artifacts | Measure-Object).Count | Write-Verbose

    $Script:DependencyLock = $Lock
    return $Script:DependencyLock
}
