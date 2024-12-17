function Invoke-DownloadFile {
    PARAM(
        [parameter(Mandatory = $true)]
        [string]$DownloadUrl,
        [parameter(Mandatory = $false)]
        [validateScript({ Test-Path (Split-Path $_) -PathType 'Container' })]
        $OutputFile
    )

    try {
        if ([String]::IsNullOrWhiteSpace($OutputFile)) {
            $OutputFile = [System.IO.Path]::GetTempFileName()
        }
        else {
            $OutputFile = $OutputFile
        }
        $OutputFile | Write-Verbose
        $DownloadUrl | Write-Verbose
        $WebClient = New-Object System.Net.WebClient
        $WebClient.DownloadFile($DownloadUrl, $OutputFile)

        return $OutputFile
    }
    catch {
        Throw $_.Exception.Message
    }
}