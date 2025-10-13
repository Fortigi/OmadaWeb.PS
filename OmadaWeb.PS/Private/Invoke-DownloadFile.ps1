function Invoke-DownloadFile {
    [CmdletBinding()]
    PARAM(
        [parameter(Mandatory = $true)]
        [string]$DownloadUrl,
        [parameter(Mandatory = $false)]
        [validateScript({ Test-Path (Split-Path $_) -PathType 'Container' })]
        $OutputFile
    )

    "{0} - Downloading file from URL: {1}" -f $MyInvocation.MyCommand, $DownloadUrl | Write-Verbose

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
        Throw
    }
}