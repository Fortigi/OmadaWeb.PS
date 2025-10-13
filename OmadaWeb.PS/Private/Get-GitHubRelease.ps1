function Get-GitHubRelease {
    [CmdletBinding()]
    PARAM(
        [Parameter(Mandatory = $true)]
        [string]$Org,
        [Parameter(Mandatory = $true)]
        [string]$Repo,
        [Parameter(Mandatory = $false)]
        [string]$TagFilter,
        [Parameter(Mandatory = $false)]
        [System.Text.RegularExpressions.Regex]$AssetFilter,
        [Parameter(Mandatory = $false)]
        [switch]$IncludePreRelease,
        [Parameter(Mandatory = $false)]
        [switch]$IncludeDraft
    )

    "{0} - Retrieving latest release for: {1}/{2}" -f $MyInvocation.MyCommand, $Org, $Repo | Write-Verbose

    $ApiBaseUrl = "https://api.github.com"
    $ApiReleasePath = "/repos/{0}/{1}/releases" -f $Org, $Repo
    $Uri = $ApiBaseUrl, $ApiReleasePath -join ""
    try {
        $Arguments = @{
            Method      = "Get"
            Uri         = $Uri
            ErrorAction = "SilentlyContinue"
        }
        # UseBasicParsing is deprecated since PowerShell Core 6, there it is only set when using PowerShell 5 (https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest?view=powershell-7.4#-usebasicparsing)
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            $Arguments.Add("UseBasicParsing", $true)
        }
        $Releases = Invoke-RestMethod @Arguments
    }
    catch {
        $WebReleasePath = "https://github.com/{0}/{1}/releases" -f $Org, $Repo
        "Could not find any release for '{0}'. Please download it manually from '{1}'" -f $Repo, $WebReleasePath | Write-Error -ErrorAction "Stop"
    }

    if ($TagFilter) {
        if ($TagFilter.contains('*')) {
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

    if ($AssetFilter) {
        $Asset = $LatestRelease.assets | Where-Object { $_.name -match $AssetFilter }
    }
    else {
        $Asset = $LatestRelease.assets
    }

    if (($Asset | Measure-Object).Count -eq 0) {
        "Could not find any asset for '{0}'" -f $AssetFilter | Write-Error -ErrorAction "Stop"
    }
    elseif (($Asset | Measure-Object).Count -gt 1) {
        "Found multiple assets. Use an asset filter to narrow to the expected asset" | Write-Error -ErrorAction "Stop"
    }

    $TempFile = Invoke-DownloadFile -DownloadUrl $Asset.'browser_download_url'
    $TempPath = Expand-DownloadFile -FilePath $TempFile

    return $TempPath
}