#Add parameters like: Import-Module OmadaWeb.PS -ArgumentList "C:\Temp\","C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
PARAM(
    [parameter(Mandatory = $false)]
    [hashtable]$Parameters
)

$ModuleName = "OmadaWeb.PS"
"Loading {0} Module" -f $ModuleName | Write-Verbose

$PowerShellType = "Core"
if ($PSVersionTable.PSVersion.Major -le 5) {
    "Selenium is restricted to version (v4.23) due compatibility issues in Windows PowerShell Desktop 5. Consider using PowerShell 7 LTS instead, you can get it here: https://aka.ms/powershell-release?tag=stable" | Write-Warning
    $PowerShellType = "Desktop"
}

$BinPath = (New-Item (Join-Path ([System.Environment]::GetEnvironmentVariable("LOCALAPPDATA")) -ChildPath "$ModuleName\Bin\$PowerShellType") -ItemType Directory -Force).FullName
$DefaultParams = @{
    WebDriverBasePath     = $BinPath
    InstalledEdgeBasePath = "C:\Program Files (x86)\Microsoft\Edge\Application"
    NewtonsoftJsonPath    = $BinPath
    SystemTextJsonPath    = $BinPath
    SystemRuntimePath     = $BinPath
    OmadaWebAuthCookie    = $null
    UpdateDependencies    = $false
    LastSessionType       = "Normal"
}

$DefaultParams.GetEnumerator() | ForEach-Object {
    New-Variable -Name $_.Key -Value $_.Value -Force
}
if ($Parameters -eq $null) {
    $Parameters = @{}
}
$Parameters.GetEnumerator() | ForEach-Object {
    "Processing parameter {0}" -f $_.Key | Write-Verbose
    if ($_.Key -notin $DefaultParams.Keys) {
        "Invalid parameter provided '{0}'" -f $_.Key | Write-Error -ErrorAction "Stop"
    }
    New-Variable -Name $_.Key -Value $_.Value -Force
}

try {
    $null = New-Item $WebDriverBasePath -ItemType Directory -Force
}
catch {}

"PsBoundParameters = {0}" -f ($PsBoundParameters | ConvertTo-Json) | Write-Verbose

#EdgeDriver Location
$Script:EdgeDriverPath = [System.IO.Path]::Combine($WebDriverBasePath, "msedgedriver.exe")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:EdgeDriverPath | Write-Verbose

#Newtonsoft.Json Location
$Script:NewtonsoftJsonPath = [System.IO.Path]::Combine($($NewtonsoftJsonPath), "Newtonsoft.Json.dll")
"{0} - {1}" -f $MyInvocation.MyCommand, $($Script:NewtonsoftJsonPath) | Write-Verbose

#System.Text.Json Location
$Script:SystemTextJsonPath = [System.IO.Path]::Combine($($SystemTextJsonPath), "System.Text.Json.dll")
"{0} - {1}" -f $MyInvocation.MyCommand, $($Script:SystemTextJsonPath) | Write-Verbose

#System.Runtime Location
$Script:SystemRuntimePath = [System.IO.Path]::Combine($($SystemRuntimePath), "System.Runtime.dll")
"{0} - {1}" -f $MyInvocation.MyCommand, $($Script:SystemRuntimePath) | Write-Verbose

#WebDriver Location
$Script:WebDriverPath = [System.IO.Path]::Combine($WebDriverBasePath, "WebDriver.dll")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebDriverPath | Write-Verbose

#Edge Location
$Script:InstalledEdgeFilePath = [System.IO.Path]::Combine($InstalledEdgeBasePath, "msedge.exe")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:InstalledEdgeFilePath | Write-Verbose
if ($PSBoundParameters["InstalledEdgeBasePath"] -and -not (Test-Path $Script:InstalledEdgeFilePath -PathType Leaf)) {
    "Cannot find path '{0}'. Please make sure that it exists!" -f $Script:InstalledEdgeFilePath | Write-Error -ErrorAction "Stop"
}

#OmadaWebAuthCookie
if ($null -ne $PsBoundParameters["OmadaWebAuthCookie"]) {
    "Using provided OmadaWebAuthCookie when loading module" | Write-Verbose
    New-Variable OmadaWebAuthCookie -Value $PsBoundParameters["OmadaWebAuthCookie"] -Force -Scope Global | Out-Null
}
elseif ([string]::IsNullOrEmpty($Script:OmadaWebAuthCookie)) {
    "Initialize OmadaWebAuthCookie" | Write-Verbose
    New-Variable OmadaWebAuthCookie -Value $null -Force -Scope Global | Out-Null
}

if ($UpdateDependencies) {
    "Update Dependencies" | Write-Verbose
    try {
        Get-ChildItem $WebDriverBasePath | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    catch {
        "Failed to initiate dependency updates. Retry restarting this PowerShell session or manually remove the contents of folder '{0}'. Error:`r`n {1}" -f $WebDriverBasePath, $_.Exception | Write-Warning
    }
}

#region exclude
$Public = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -Recurse)
$Private = @(Get-ChildItem -Path $PSScriptRoot\Private\*.ps1)
Foreach ($Import in @($Public + $Private)) {
    try {
        . $Import.FullName
    }
    catch {
        "Failed to import function {0}: {1}" -f $($Import.FullName), $_ | Write-Error -ErrorAction "Stop"
    }
}

# Export all the functions
Export-ModuleMember -Function $Public.Basename -Alias *
#endregion

"Validate version" | Write-Verbose
try {
    $InstalledModule = Get-InstalledModuleInfo -ModuleName $ModuleName

    if (-not $InstalledModule.RepositorySource -or $InstalledModule.RepositorySource -notlike "*powershellgallery.com*") {
        "Module '{0}' was not sourced from the PowerShell Gallery. Skipping version check." -f $ModuleName | Write-Verbose
    }
    else {
        $GalleryVersion = Get-GalleryModuleVersion -ModuleName $ModuleName

        if (-not $GalleryVersion) {
        }
        else {
            if ([System.Version]$InstalledModule.Version -lt [System.Version]$GalleryVersion) {
                "The installed version {0} of '{1}' is outdated. Latest version: {2}. Execute Update-Module {1} to update to the latest version!" -f ($($InstalledModule.Version)), $ModuleName, $GalleryVersion | Write-Warning
            }
            elseif ([System.Version]$InstalledModule.Version -eq [System.Version]$GalleryVersion) {
                "The installed version {0} of '{1}' is up-to-date." -f ($($InstalledModule.Version)) , $ModuleName | Write-Verbose
            }
            else {
                "The installed version {0} of '{1}' is newer than the gallery version {2}." -f ($($InstalledModule.Version)), $ModuleName, $GalleryVersion | Write-Warning
            }
        }
    }

}
catch {}

$Script:EdgeProfiles = Get-EdgeProfile
$Script:LoginRetryCount = 0
$Script:LoginCount = 0