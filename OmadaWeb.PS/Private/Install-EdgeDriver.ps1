function Install-EdgeDriver {

    $null = New-Item (Split-Path $Script:EdgeDriverPath) -ItemType Directory -Force

    $TempFile = [System.IO.Path]::GetTempFileName()
    "Invoke-WebEdgeDriverFramework: {0}" -f $$ | Write-Verbose

    $ComputerInfo = Get-WmiObject -Class Win32_ComputerSystem
    switch($ComputerInfo.SystemType) {
        "x64-based PC" { $Arch = "win64" }
        "x86-based PC" { $Arch = "win32" }
        default { $Arch = "win64" }
    }

    #Download correct version
    $EdgeWebdriverDownloadBaseUrl = "https://msedgedriver.azureedge.net/"
    $EdgeWebdriverFileName = "edgedriver_{0}.zip" -f $Arch
    #Example: https://msedgedriver.azureedge.net/128.0.2739.33/edgedriver_win64.zip
    $EdgeWebdriverDownloadUrl = "{0}{1}/{2}" -f $EdgeWebdriverDownloadBaseUrl,$($InstalledEdgeVersion.VersionInfo.ProductVersion),$EdgeWebdriverFileName
    "Download URL: {0}" -f $EdgeWebdriverDownloadUrl | Write-Verbose

    $TempFile = [System.IO.Path]::GetTempFileName()
    try{
        Invoke-RestMethod $EdgeWebdriverDownloadUrl -UseBasicParsing -OutFile $TempFile
    }
    catch{
        Throw ("Failed to download '{0}'" -f $EdgeWebdriverDownloadUrl)
    }
    $TempFile = Get-Item $TempFile | Rename-Item -NewName ("{0}.zip" -f $TempFile) -PassThru

    Get-Item $TempFile | Expand-Archive -DestinationPath (Split-Path $Script:EdgeDriverPath) -Force
    Remove-Item $TempFile
    return $false
}
