function Confirm-AuthenticodeTrust {
    [CmdletBinding()]
    PARAM(
        [parameter(Mandatory = $true)]
        [string]$Path,
        [parameter(Mandatory = $true)]
        [string]$ExpectedSubject,
        [parameter(Mandatory = $true)]
        [string]$ArtifactName
    )

    "{0} - Verifying Authenticode signature of '{1}'" -f $MyInvocation.MyCommand, $Path | Write-Verbose

    if (-not (Test-Path $Path -PathType Leaf)) {
        "Cannot verify artefact '{0}': the downloaded file '{1}' does not exist." -f $ArtifactName, $Path | Write-Error -ErrorAction "Stop"
    }

    # Being unable to check is not the same as checking and passing, so this fails closed as well -
    # but with an error that says why. Get-AuthenticodeSignature comes from
    # Microsoft.PowerShell.Security, which cannot load when another PowerShell installation has
    # leaked its module directory onto this one's PSModulePath.
    try {
        $Signature = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
    }
    catch {
        Remove-Item -Path $Path -Force -Confirm:$false -ErrorAction SilentlyContinue

        "Cannot verify the Authenticode signature of '{0}' because 'Get-AuthenticodeSignature' is unavailable: {1}`r`nThe file was deleted and has not been executed, because this artefact cannot be pinned by hash and its signature is the only proof of origin. This usually means the Microsoft.PowerShell.Security module cannot be loaded - check `$env:PSModulePath for entries belonging to a different PowerShell installation. Until that is resolved, use -AuthenticationType WebView2, which does not need msedgedriver.exe." -f $ArtifactName, $_.Exception.Message | Write-Error -ErrorAction "Stop"
    }

    if ($Signature.Status -ne "Valid") {
        Remove-Item -Path $Path -Force -Confirm:$false -ErrorAction SilentlyContinue

        "Authenticode check FAILED for '{0}' ('{1}').`r`n  Signature status: {2}`r`n  Status message:   {3}`r`nThe file was deleted and has not been executed. This artefact cannot be pinned by hash because its version has to match the Microsoft Edge build installed on this machine, so a valid signature is the only proof of origin. Report it at https://github.com/Fortigi/OmadaWeb.PS/security/advisories/new if you believe the download was tampered with." -f $ArtifactName, $Path, $Signature.Status, $Signature.StatusMessage | Write-Error -ErrorAction "Stop"
    }

    $Subject = $Signature.SignerCertificate.Subject
    if ($Subject -notlike $ExpectedSubject) {
        Remove-Item -Path $Path -Force -Confirm:$false -ErrorAction SilentlyContinue

        "Authenticode check FAILED for '{0}' ('{1}'). The signature is valid but was issued to an unexpected publisher.`r`n  Expected subject like: {2}`r`n  Actual subject:        {3}`r`nThe file was deleted and has not been executed. Report it at https://github.com/Fortigi/OmadaWeb.PS/security/advisories/new if you believe the download was tampered with." -f $ArtifactName, $Path, $ExpectedSubject, $Subject | Write-Error -ErrorAction "Stop"
    }

    "{0} - '{1}' carries a valid signature from '{2}'" -f $MyInvocation.MyCommand, $ArtifactName, $Subject | Write-Verbose
}
