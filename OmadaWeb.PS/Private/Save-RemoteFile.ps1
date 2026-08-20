function Save-RemoteFile {
    [CmdletBinding()]
    PARAM(
        [parameter(Mandatory = $true)]
        [string]$DownloadUrl,
        [parameter(Mandatory = $true)]
        [string]$OutputFile
    )

    # The raw fetch, kept in its own function so Invoke-DownloadFile stays about verification and so
    # the network call can be replaced in tests.
    $WebClient = New-Object System.Net.WebClient
    try {
        $WebClient.DownloadFile($DownloadUrl, $OutputFile)
    }
    finally {
        $WebClient.Dispose()
    }
}
