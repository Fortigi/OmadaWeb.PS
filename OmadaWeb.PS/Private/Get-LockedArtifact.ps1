function Get-LockedArtifact {
    [CmdletBinding(DefaultParameterSetName = "Id")]
    PARAM(
        [parameter(Mandatory = $true, ParameterSetName = "Id")]
        [string]$Id,
        [parameter(Mandatory = $true, ParameterSetName = "Group")]
        [string]$Group
    )

    $Lock = Get-DependencyLock

    if ($PSCmdlet.ParameterSetName -eq "Group") {
        # Returned in file order, which is the order the closure has to be installed in.
        $Artifacts = @($Lock.Artifacts | Where-Object { $_.Group -eq $Group })
        if ($Artifacts.Count -eq 0) {
            "No artefacts are listed under group '{0}' in '{1}'. Refusing to download anything that is not pinned there." -f $Group, $Script:DependencyLockPath | Write-Error -ErrorAction "Stop"
        }
        return $Artifacts
    }

    $Artifact = @($Lock.Artifacts | Where-Object { $_.Id -eq $Id })
    if ($Artifact.Count -eq 0) {
        # Fail closed: an artefact nobody pinned is an artefact nobody can verify.
        "There is no lock entry for artefact '{0}' in '{1}', so it cannot be verified. Refusing to download it." -f $Id, $Script:DependencyLockPath | Write-Error -ErrorAction "Stop"
    }
    if ($Artifact.Count -gt 1) {
        "Artefact '{0}' is listed {1} times in '{2}'. The lock file must hold exactly one entry per artefact." -f $Id, $Artifact.Count, $Script:DependencyLockPath | Write-Error -ErrorAction "Stop"
    }

    return $Artifact[0]
}
