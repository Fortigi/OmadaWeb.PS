function Invoke-DownloadFile {
    [CmdletBinding(DefaultParameterSetName = "Locked")]
    PARAM(
        [parameter(Mandatory = $true, ParameterSetName = "Locked")]
        [parameter(Mandatory = $true, ParameterSetName = "Unpinned")]
        [string]$ArtifactId,
        [parameter(Mandatory = $true, ParameterSetName = "Unpinned")]
        [string]$DownloadUrl,
        [parameter(Mandatory = $false)]
        [validateScript({ Test-Path (Split-Path $_) -PathType 'Container' })]
        $OutputFile
    )

    # Every binary the module loads passes through here, so this is where integrity is enforced:
    # an artefact that is not in the lock file is never fetched, and a hash-pinned one is verified
    # before its path is handed back to be expanded, copied into Bin or loaded.
    $Artifact = Get-LockedArtifact -Id $ArtifactId

    if ($PSCmdlet.ParameterSetName -eq "Unpinned") {
        # Only artefacts the lock file declares unpinnable may bring their own URL. Everything else
        # must come from the pinned URL, otherwise the hash would be checked against the wrong bytes.
        if ($Artifact.Verification -ne "Authenticode") {
            "Artefact '{0}' is hash-pinned in '{1}' and must be downloaded from its pinned URL. Refusing to download it from '{2}'." -f $ArtifactId, $Script:DependencyLockPath, $DownloadUrl | Write-Error -ErrorAction "Stop"
        }
    }
    else {
        if ($Artifact.Verification -ne "Sha256") {
            "Artefact '{0}' is declared as '{1}' in '{2}', which carries no pinned URL. It has to be requested with an explicit -DownloadUrl." -f $ArtifactId, $Artifact.Verification, $Script:DependencyLockPath | Write-Error -ErrorAction "Stop"
        }
        $DownloadUrl = $Artifact.Url
    }

    "{0} - Downloading artefact '{1}' from URL: {2}" -f $MyInvocation.MyCommand, $ArtifactId, $DownloadUrl | Write-Verbose

    try {
        if ([String]::IsNullOrWhiteSpace($OutputFile)) {
            $OutputFile = [System.IO.Path]::GetTempFileName()
        }
        $OutputFile | Write-Verbose

        Save-RemoteFile -DownloadUrl $DownloadUrl -OutputFile $OutputFile
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }

    if ($Artifact.Verification -eq "Sha256") {
        # Throws and deletes the file on mismatch, so nothing downstream ever sees unverified bytes.
        Confirm-FileHash -Path $OutputFile -ExpectedSha256 $Artifact.Sha256 -ArtifactName ("{0} {1}" -f $ArtifactId, $Artifact.Version).Trim() -SourceUrl $DownloadUrl
    }
    else {
        # Authenticode artefacts are archives here; the signed payload inside is verified by the
        # caller once it has been extracted.
        "{0} - Artefact '{1}' is signature-verified after extraction" -f $MyInvocation.MyCommand, $ArtifactId | Write-Verbose
    }

    return $OutputFile
}
