#Add parameters like: Import-Module OmadaWeb.PS -ArgumentList "C:\Temp\","C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
param(
    [parameter(Mandatory = $false)]
    [hashtable]$Parameters
)

$ModuleName = "OmadaWeb.PS"
"Loading {0} Module" -f $ModuleName | Write-Verbose

$PowerShellType = "Core"
if ($PSVersionTable.PSVersion.Major -le 5) {
    "When browser authentication type with Selenium is used, it is restricted to version (v4.23) due to compatibility issues in Windows PowerShell Desktop 5. Consider using PowerShell 7 LTS instead, you can get it here: https://aka.ms/powershell-release?tag=stable" | Write-Warning
    $PowerShellType = "Desktop"
}
else {
    if (!$IsWindows) {
        "This module is not supported on non-Windows platforms. Please use Windows PowerShell or PowerShell Core on Windows." | Write-Error -ErrorAction "Stop"
    }
}

$LocalAppDataPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
$ModuleAppDataPath = (New-Item (Join-Path $LocalAppDataPath -ChildPath $ModuleName) -ItemType Directory -Force).FullName
$Script:BinPath = (New-Item (Join-Path $ModuleAppDataPath -ChildPath "Bin\$PowerShellType") -ItemType Directory -Force).FullName
$DefaultParams = @{
    WebBinBasePath        = $Script:BinPath
    InstalledEdgeBasePath = "C:\Program Files (x86)\Microsoft\Edge\Application"
    NewtonsoftJsonPath    = $Script:BinPath
    SystemTextJsonPath    = $Script:BinPath
    SystemRuntimePath     = $Script:BinPath
    WebView2Path          = $Script:BinPath
    OmadaWebAuthCookie    = $null
    UpdateDependencies    = $false
    LastSessionType       = "Normal"
    WebView2Used          = $false
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
    $null = New-Item $WebBinBasePath -ItemType Directory -Force
}
catch {}

"PsBoundParameters = {0}" -f ($PsBoundParameters | ConvertTo-Json) | Write-Verbose

# Initialize script-level variables

$Script:AccountSelectionAttempted = $false
$Script:BrowserDataCleared = $false
$Script:CookieCacheFilePath = $null
$Script:DebugWebView2 = $false
$Script:Credential = $null
$Script:CurrentScenario = $null
$Script:EdgeDriverPath = $null
$Script:EdgeProfiles = $null
$Script:ForceAuthentication = $false
$Script:FunctionName = $null
$Script:IdAttributes = $null
$Script:InstalledEdgeFilePath = $null
$Script:LastCheckedHost = $null
$Script:LastLoggedSecond = -1
[double]$Script:LastFiredSecond = -1
$Script:LastSessionType = $null
$Script:LoginCount = 0
$Script:LoginFailed = $false
$Script:LoginRetryCount = 0
$Script:LoginState = $null
$Script:LoginSubState = $null
$Script:LoginTask = $null
$Script:MaxLoginRetries = 3
$Script:MfaRequestDisplayed = $false
$Script:MicrosoftOnlineLogin = $false
$Script:NameObjects = $null
$Script:NewtonsoftJsonPath = $null
$Script:OmadaWatchdogStart = $null
$Script:OmadaWatchdogRunning = $false
$Script:OmadaWatchdogTimeout = 600
$Script:OmadaWebAuthCookie = $null
$Script:OmadaWebBaseUrl = $null
$Script:PreviousAttributes = $null
$Script:PreviousScenario = $null
$Script:ProgressCounter = 0
$Script:SystemRuntimePath = $null
$Script:SystemTextJsonPath = $null
$Script:Timer = $null
$Script:Task = $null
$Script:UserAgent = "OmadaWeb.PS/{0}"
$Script:UserAgentParameterUsed = $false
$Script:WebDriverPath = $null
$Script:WebView2CorePath = $null
$Script:WebView2LoaderPath = $null
$Script:WebView2Used = $false
$Script:WebView2UserProfilePath = $null
$Script:WebView2WinFormsPath = $null
$Script:WebView2WpfPath = $null
$Script:WebViewEnv = $null


"{0} - Set paths" -f $MyInvocation.MyCommand | Write-Verbose
#EdgeDriver Location
$Script:EdgeDriverPath = [System.IO.Path]::Combine($WebBinBasePath, "msedgedriver.exe")
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
$Script:WebDriverPath = [System.IO.Path]::Combine($WebBinBasePath, "WebDriver.dll")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebDriverPath | Write-Verbose

#WebView2 Base Path
if ($Env:PROCESSOR_ARCHITECTURE -eq "AMD64") {
    $WebView2BasePath = [System.IO.Path]::Combine($WebBinBasePath, "win-x64")
}
else {
    $WebView2BasePath = [System.IO.Path]::Combine($WebBinBasePath, "win-x86")
}
New-Item -ItemType Directory -Path $WebView2BasePath -Force | Out-Null

#WebView2 Core Location
$Script:WebView2CorePath = [System.IO.Path]::Combine($WebView2BasePath, "Microsoft.Web.WebView2.Core.dll")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebView2CorePath | Write-Verbose

#WebView2 WinForms Location
$Script:WebView2WinFormsPath = [System.IO.Path]::Combine($WebView2BasePath, "Microsoft.Web.WebView2.WinForms.dll")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebView2WinFormsPath | Write-Verbose

#WebView2 Loader Location
$Script:WebView2LoaderPath = [System.IO.Path]::Combine($WebView2BasePath, "WebView2Loader.dll")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebView2LoaderPath | Write-Verbose

#WebView2 User Profile Location
$Script:WebView2UserProfilePath = [System.IO.Path]::Combine($ModuleAppDataPath, "Edge User Data\OmadaWebView2Profile")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebView2UserProfilePath | Write-Verbose

#Edge Location
$Script:InstalledEdgeFilePath = [System.IO.Path]::Combine($InstalledEdgeBasePath, "msedge.exe")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:InstalledEdgeFilePath | Write-Verbose
if ($PSBoundParameters["InstalledEdgeBasePath"] -and -not (Test-Path $Script:InstalledEdgeFilePath -PathType Leaf)) {
    "Cannot find path '{0}'. Please make sure that it exists!" -f $Script:InstalledEdgeFilePath | Write-Error -ErrorAction "Stop"
}

#OmadaWebAuthCookie
if ($null -ne $PsBoundParameters["OmadaWebAuthCookie"]) {
    "Using provided OmadaWebAuthCookie when loading module" | Write-Verbose
    New-Variable OmadaWebAuthCookie -Value $PsBoundParameters["OmadaWebAuthCookie"] -Force -Scope Script | Out-Null
}
elseif ([string]::IsNullOrEmpty($Script:OmadaWebAuthCookie)) {
    "Initialize OmadaWebAuthCookie" | Write-Verbose
    New-Variable OmadaWebAuthCookie -Value $null -Force -Scope Script | Out-Null
}

if ($UpdateDependencies) {
    "Update Dependencies" | Write-Verbose
    try {
        Get-ChildItem $WebBinBasePath | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    catch {
        "Failed to initiate dependency updates. Retry restarting this PowerShell session or manually remove the contents of folder '{0}'. Error:`r`n {1}" -f $WebBinBasePath, $_.Exception | Write-Warning
    }
}

#region exclude
$Public = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -Recurse | Where-Object { $_.Name -notlike "_*.ps1" })
$Private = @(Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -Recurse | Where-Object { $_.Name -notlike "_*.ps1" })
foreach ($Import in @($Public + $Private)) {
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
        $Script:UserAgent = $Script:UserAgent -f "Development"
    }
    else {
        $Script:UserAgent = $Script:UserAgent -f $($InstalledModule.Version)
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

"Module {0} loaded successfully" -f $ModuleName | Write-Verbose