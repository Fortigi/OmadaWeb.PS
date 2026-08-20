function Confirm-FileHash {
    [CmdletBinding()]
    PARAM(
        [parameter(Mandatory = $true)]
        [string]$Path,
        [parameter(Mandatory = $true)]
        [string]$ExpectedSha256,
        [parameter(Mandatory = $true)]
        [string]$ArtifactName,
        [parameter(Mandatory = $false)]
        [string]$SourceUrl
    )

    "{0} - Verifying SHA-256 of '{1}'" -f $MyInvocation.MyCommand, $Path | Write-Verbose

    if (-not (Test-Path $Path -PathType Leaf)) {
        "Cannot verify artefact '{0}': the downloaded file '{1}' does not exist." -f $ArtifactName, $Path | Write-Error -ErrorAction "Stop"
    }

    if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        "Artefact '{0}' has no expected SHA-256 in '{1}', so the download cannot be verified. Refusing to use it." -f $ArtifactName, $Script:DependencyLockPath | Write-Error -ErrorAction "Stop"
    }

    # Hashed through .NET rather than Get-FileHash, for the same reason Get-DependencyLock parses the
    # lock file itself: Get-FileHash lives in Microsoft.PowerShell.Utility, and the integrity check
    # must not become unavailable because a module directory on the machine shadows that one.
    # Build/New-Sbom.ps1 computes its hashes the same way.
    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $Stream = [System.IO.File]::OpenRead($Path)
        try {
            $ActualSha256 = ([System.BitConverter]::ToString($Sha256.ComputeHash($Stream)) -replace "-", "").ToLowerInvariant()
        }
        finally {
            $Stream.Dispose()
        }
    }
    finally {
        $Sha256.Dispose()
    }

    if ($ActualSha256 -ne $ExpectedSha256) {
        # Delete first: leaving unverified bytes on disk invites a later code path picking them up.
        Remove-Item -Path $Path -Force -Confirm:$false -ErrorAction SilentlyContinue

        "Integrity check FAILED for '{0}' downloaded from '{1}'.`r`n  Expected SHA-256: {2}`r`n  Actual SHA-256:   {3}`r`nThe file was deleted and has not been loaded. Either the download was corrupted, or the published artefact no longer matches the version pinned in '{4}'. Do not work around this by editing the lock file - report it at https://github.com/Fortigi/OmadaWeb.PS/security/advisories/new if you believe the upstream artefact was tampered with." -f $ArtifactName, $SourceUrl, $ExpectedSha256.ToLowerInvariant(), $ActualSha256.ToLowerInvariant(), $Script:DependencyLockPath | Write-Error -ErrorAction "Stop"
    }

    "{0} - '{1}' matches the pinned SHA-256" -f $MyInvocation.MyCommand, $ArtifactName | Write-Verbose
}
