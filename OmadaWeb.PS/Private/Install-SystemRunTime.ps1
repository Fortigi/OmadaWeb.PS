function Install-SystemRunTime {
    $DllFileName = "System.Runtime.dll"
    if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
        "Failed to update '{0}'. Retry restarting this PowerShell session or manually remove the contents of folder '{1}'. Reuse current version for now. " -f $DllFileName, $WebDriverBasePath | Write-Warning
        break
    }

    "'{0}' is needs to be downloaded. Downloading from GitHub" -f $DllFileName | Write-Host
    $Uri = "https://www.nuget.org/api/v2/package/System.Runtime"

    $null = New-Item (Split-Path $Script:WebDriverPath) -ItemType Directory -Force

    $TempFile = Invoke-DownloadFile -DownloadUrl $Uri

    $TempZipPath = Expand-DownloadFile -FilePath $TempFile


    "Use net4* DLL" | Write-Verbose

    try {
        Get-ChildItem ((Get-ChildItem (Join-Path $($TempZipPath.FullName) -ChildPath "lib") -Filter "net4*" | Select-Object -Last 1)).FullName -Filter $DllFileName | Copy-Item -Destination (Split-Path $Script:WebDriverPath) -Force
    }
    catch {
        if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
            "Failed to update '{0}'. Retry restarting this PowerShell session or manually remove the contents of folder '{1}'. Reuse current version for now. Error:`r`n {2}" -f $DllFileName, $WebDriverBasePath, $_.Exception | Write-Warning
            return $false
        }
        else {
            Throw $_
        }
    }

    Remove-Item $($TempZipPath.FullName) -Force -Confirm:$false -Recurse

    #Get all dependencies

    $NuGetSource = "https://api.nuget.org/v3/index.json"

    $Json = Invoke-RestMethod -Uri $NuGetSource

    $PackageSearchJson = ($Json.resources | Where-Object '@type' -EQ 'SearchQueryService' | Select-Object -First 1).'@id'

    $SearchJson = Invoke-RestMethod -Uri $PackageSearchJson

    $SystemTextJsonSoure = ($SearchJson.data | Where-Object title -EQ 'System.Text.Json').'@id'

    $SystemTextJson = Invoke-RestMethod -Uri $SystemTextJsonSoure

    $SystemTextJson2 = $SystemTextJson.items | Select-Object -Last 1
    $id = $SystemTextJson2.items.'@id' | Select-Object -Last 1

    $SystemTextJsonVersion = Invoke-RestMethod -Uri $id
    $SystemTextJsonCatalog = $SystemTextJsonVersion.catalogEntry

    $SystemTextJsonCatalogInfo = Invoke-RestMethod -Uri $SystemTextJsonCatalog

    $Dependencies = $SystemTextJsonCatalogInfo.dependencyGroups | Where-Object { $_.targetframework -EQ '.NETFramework4.6.2' }

    $BaseUri = 'https://www.nuget.org/api/v2/package/'
    $Dependencies.dependencies.id | ForEach-Object {

        $package = $_
        $pgkuri = "{0}{1}" -f $BaseUri, $package

        $TempFile = Invoke-DownloadFile -DownloadUrl $pgkuri

        $TempZipPath = Expand-DownloadFile -FilePath $TempFile

        Get-ChildItem ((Get-ChildItem (Join-Path $($TempZipPath.FullName) -ChildPath "lib") -Filter "net4*" | Select-Object -Last 1)).FullName -Filter ("{0}.dll" -f $package) | Copy-Item -Destination (Split-Path $Script:WebDriverPath) -Force
    }

    "Installed '{0}' version {1}" -f $DllFileName, (Get-Item (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName)).VersionInfo.ProductVersion | Write-Host
    return $CheckJsonLibrary
}


