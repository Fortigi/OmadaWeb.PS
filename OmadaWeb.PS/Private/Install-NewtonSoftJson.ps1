function Install-NewtonSoftJson {
    $null = New-Item (Split-Path $Script:NewtonsoftJsonPath) -ItemType Directory -Force
    "Downloading latest Newtonsoft.Json.Dll missing, downloading latest version from GitHub" | Write-Host
    $DownloadUrl = "https://api.github.com"
    $URI = $DownloadUrl, "/repos/JamesNK/Newtonsoft.Json/releases" -join ""
    try {
        $Result = Invoke-RestMethod -Method Get -Uri $URI -ErrorAction SilentlyContinue -UseBasicParsing
    }
    catch {
        "Could not download the Newtonsoft.Json.dll. Please manually download the latest Json130*.zip from 'https://github.com//JamesNK/Newtonsoft.Json/releases/' extract the net48 or netstandard20 Newtonsoft.Json.dll and place it in directory '{0}'." -f (Split-Path $Script:WebDriverPath) | Write-Error -ErrorAction "Stop"
    }
    $LatestRelease = $Result | Where-Object { $_.tag_name -ne "nightly" -and $_.prerelease -eq $false -and $_.draft -eq $false -and $_.name.startswith("13") } | Sort-Object published_at | Select-Object -Last 1
    $Asset = $LatestRelease.assets | Where-Object { $_.name -match "(Json130)*.zip" }
    $TempFile = [System.IO.Path]::GetTempFileName()
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile($Asset.'browser_download_url', $TempFile)

    $TempFile = Get-Item $TempFile | Rename-Item -NewName ("{0}.zip" -f $TempFile) -PassThru
    $TempZipFullName = (Join-Path (Get-Item $TempFile).PsParentPath -ChildPath $($TempFile.BaseName.Substring(0, $TempFile.BaseName.IndexOf("."))))
    $TempZipPath = New-Item $TempZipFullName -ItemType Directory -Force
    Get-Item $TempFile | Expand-Archive -DestinationPath $($TempZipPath.FullName)
    Get-ChildItem ((Get-ChildItem (Join-Path $($TempZipPath.FullName) -ChildPath "bin") -Filter "netstandard2.0" | Select-Object -Last 1)).FullName -Filter "Newtonsoft.Json.dll" | Copy-Item -Destination (Split-Path $Script:WebDriverPath) -Force

    Remove-Item $TempZipPath -Force -Confirm:$false -Recurse
    Remove-Item $TempFile -Force -Confirm:$false -Recurse
    return $false
}