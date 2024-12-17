function Get-GitHubRelease {
    PARAM(
        $Org = "JamesNK",
        $Repo = "Newtonsoft.Json",
        $TagFilter,
        [System.Text.RegularExpressions.Regex]$AssetFilter,
        [switch]$IncludePreRelease,
        [switch]$IncludeDraft
    )

    $ApiBaseUrl = "https://api.github.com"
    $ApiReleasePath = "/repos/{0}/{1}/releases" -f $Org, $Repo
    $Uri = $ApiBaseUrl, $ApiReleasePath -join ""
    try {
        $Releases = Invoke-RestMethod -Method Get -Uri $Uri -ErrorAction SilentlyContinue -UseBasicParsing
    }
    catch {
        $WebReleasePath = "https://github.com/{0}/{1}/releases" -f $Org, $Repo
        "Could not find any release for '{0}'. Please download it manually from '{1}'" -f $Repo, $WebReleasePath | Write-Error -ErrorAction "Stop"
    }

    if ($TagFilter) {
        if($TagFilter.contains('*')) {
            $TagFilter = " `$_.tag_name -like '{0}' " -f $TagFilter
        }
        else {
            $TagFilter = " `$_.tag_name -eq '{0}' " -f $TagFilter
        }
    }
    $PreReleaseFilter = " `$_.prerelease -eq `${0} " -f $IncludePreRelease.IsPresent
    $DraftFilter = " `$_.draft -eq `${0} " -f $IncludeDraft.IsPresent

    $FilterScriptString = (" {0} " -f ($TagFilter, $PreReleaseFilter, $DraftFilter -join " -and ")).Trim().TrimStart("-and")
    [System.Management.Automation.Scriptblock]$FilterScript = [System.Management.Automation.Scriptblock]::Create($FilterScriptString)

    $LatestRelease = $Releases | Where-Object -FilterScript $FilterScript | Sort-Object published_at | Select-Object -Last 1
    "Retrieving '{0}' version {1}" -f $Repo, ($LatestRelease.tag_name) | Write-Host

    if($AssetFilter){
        $Asset = $LatestRelease.assets | Where-Object { $_.name -match $AssetFilter }
    }
    else {
        $Asset = $LatestRelease.assets
    }

    if(($Asset|Measure-Object).Count -eq 0){
        "Could not find any asset for '{0}'" -f $AssetFilter | Write-Error -ErrorAction "Stop"
    }
    elseif(($Asset|Measure-Object).Count -gt 1){
        "Found multiple assets. Use an asset filter to narrow to the expected asset" | Write-Error -ErrorAction "Stop"
    }

    $TempFile = Invoke-DownloadFile -DownloadUrl $Asset.'browser_download_url'
    $TempPath = Expand-DownloadFile -FilePath $TempFile

    return $TempPath
}