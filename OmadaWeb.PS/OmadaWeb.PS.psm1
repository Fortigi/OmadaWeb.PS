#Add parameters like: Import-Module OmadaWeb.PS -ArgumentList "C:\Temp\","C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
param(
    [parameter(Mandatory = $false)]
    [hashtable]$Parameters
)

# StrictMode has to be set here rather than by the caller: it is scoped to the session state it is
# set in, so a Set-StrictMode in the build script or in a Pester test reaches neither this file's
# load-time code nor any function defined below. Without this line the module runs unstrict no
# matter what the caller does, which is how the undefined-variable reads this guards against
# survived for so long.
#
# Opt-in rather than always-on, because the browser login flows are the module's largest code paths
# and CI cannot exercise them (they need a real interactive WebView2/Edge). Turning an unset-variable
# read there into a terminating error in front of a user, without CI ever having run that path, trades
# a silent null for a broken sign-in. The build sets this for every test run, so the bug class is
# caught before it ships instead.
if ($Env:OMADAWEBPS_STRICTMODE -eq "1") {
    Set-StrictMode -Version Latest
}

$ModuleName = "OmadaWeb.PS"
"Loading {0} Module" -f $ModuleName | Write-Verbose

$FullyQualifiedModule = @{
    ModuleName    = "Microsoft.PowerShell.Utility"
    Guid          = [guid]"1da87e53-152b-403e-98dc-74d7b4d63d59"
    ModuleVersion = [Version]"7.0.0"
}
if ($PSVersionTable.PSEdition -eq "Desktop") {
    $FullyQualifiedModule.ModuleVersion = [Version]"3.1.0.0"
}
Import-Module -FullyQualifiedName $FullyQualifiedModule -Force -ErrorAction "Stop"

$FullyQualifiedModule.ModuleName = "Microsoft.PowerShell.Management"
$FullyQualifiedModule.Guid = [guid]"eefcb906-b326-4e99-9f54-8b4bb6ef3c6d"
Import-Module -FullyQualifiedName $FullyQualifiedModule -Force -ErrorAction "Stop"

$PowerShellType = "Core"
if ($PSVersionTable.PSVersion.Major -le 5) {
    "When browser authentication type with Selenium is used, it is restricted to version (v4.11.0) due to compatibility issues in Windows PowerShell Desktop 5. Consider using PowerShell 7 LTS instead, you can get it here: https://aka.ms/powershell-release?tag=stable" | Write-Warning
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
$RuntimeFolder = "win-x64"
if ($Env:PROCESSOR_ARCHITECTURE -eq "x86") {
    $RuntimeFolder = "win-x86"
}
$DefaultParams = @{
    WebBinBasePath        = $Script:BinPath
    InstalledEdgeBasePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application"
    NewtonsoftJsonPath    = $Script:BinPath
    SystemTextJsonPath    = $Script:BinPath
    SystemRuntimePath     = $Script:BinPath
    WebView2Path          = $Script:BinPath
    OmadaWebAuthCookie    = $null
    UpdateDependencies    = $false
    LastSessionType       = "Normal"
    WebView2Used          = $false
    CheckForUpdates       = $true
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

"Trying to find the Edge Browser installation path" | Write-Verbose
if (!(Test-Path $InstalledEdgeBasePath -PathType Container)) {
    $InstalledEdgeBasePath = "$($env:ProgramFiles)\Microsoft\Edge\Application"
    "Trying path: {0}" -f $InstalledEdgeBasePath | Write-Verbose
    if (!(Test-Path $InstalledEdgeBasePath -PathType Container)) {
        $UnInstallRegLocation = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
        )

        $EdgeRegs = @()
        foreach ($RegLocation in $UnInstallRegLocation) {
            if (Test-Path $RegLocation -PathType Container) {
                "Searching registry location: {0}" -f $RegLocation | Write-Verbose
                $EdgeRegs += Get-ChildItem $RegLocation -ErrorAction SilentlyContinue | ForEach-Object { Get-ItemProperty $_.PSPath } | Where-Object { $_.DisplayName -like "Microsoft Edge*" -and $_.DisplayName -notlike "*WebView2 Runtime*" -and $_.InstallLocation -and (Test-Path $_.InstallLocation -PathType Container) }
            }
            else {
                "Registry location not found: {0}" -f $RegLocation | Write-Verbose
            }
        }
        foreach ($EdgeReg in $EdgeRegs | Sort-Object InstallDate -Descending) {

            if ($EdgeReg.DisplayName -eq "Microsoft Edge") {
                $InstalledEdgeBasePath = $EdgeReg.InstallLocation
                "Found Edge installation in registry: {0}" -f $InstalledEdgeBasePath | Write-Verbose
                break
            }
            elseif ($EdgeReg.DisplayName -like "Microsoft Edge*") {
                $InstalledEdgeBasePath = $EdgeReg.InstallLocation
                "Found Edge installation in registry: {0}" -f $InstalledEdgeBasePath | Write-Verbose
                break
            }
        }

        if (!(Test-Path $InstalledEdgeBasePath -PathType Container)) {
            "Could not find Microsoft Edge on the system!" -f $InstalledEdgeBasePath | Write-Verbose
        }
    }
}

try {
    $null = New-Item $WebBinBasePath -ItemType Directory -Force
}
catch {}

# Initialize script-level variables
# Redaction constants for ConvertTo-RedactedLogString. They live here, initialized once per import,
# because the walker recurses once per property of every object logged and builds its string on every
# request whether or not -Verbose is on - rebuilding a 16-element array per recursive call is exactly
# the kind of cost that does not belong on that path. The patterns are matched as case-insensitive
# substrings, so composites such as X-CSRF-Token, RefreshToken and SessionCookie are covered too.
$Script:RedactedLogToken = "***REDACTED***"
$Script:SensitiveLogNamePatterns = @(
    "authorization", "cookie", "credential", "password", "pwd", "secret", "token",
    "apikey", "api_key", "clientsecret", "sessionkey", "bearer", "csrf", "assertion",
    "privatekey", "connectionstring"
)
# Used only inside an object that pairs a Name member with a Value member - a cookie or a header,
# where the value is the secret. Precomputed for the same reason as the list above.
$Script:SensitiveLogNamePatternsWithValue = $Script:SensitiveLogNamePatterns + "value"
# Wrapped in a function purely to scope the analyzer suppression to this one assignment. The
# attribute always covers the whole scope it sits on - PSAvoidGlobalVars has no per-variable
# suppression ID - so on the param() block above it would have covered this entire file and hidden
# any global added to module initialization later. The variable has to exist before the first
# request: Set-StrictMode is active, and Set-OmadaCurrentBaseUrl reads it before writing it.
function Initialize-OmadaCurrentBaseUrl {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidGlobalVars", "", Justification = "OmadaWebPSCurrentBaseUrl is deliberately global: it is part of the module's public surface, readable by callers to see which environment the last request went to. Maintained by Set-OmadaCurrentBaseUrl and cleared by Clear-OmadaWebCache.")]
    param()

    $Global:OmadaWebPSCurrentBaseUrl = $null
}

Initialize-OmadaCurrentBaseUrl
[bool]$Script:EnvironmentSuspended = $false
# The suspended status is cached in $Script:EnvironmentSuspended for the current base URL only
# ($Global:OmadaWebPSCurrentBaseUrl tracks that single last-used URL - there is no per-URL map, so
# alternating between two environments re-probes on each switch). This flag forces the next request
# to re-probe even when the base URL is unchanged; it is set after a 502 response (how a suspended
# Omada environment surfaces once a session is active). An Import-Module -Force re-runs this file,
# which resets all of this state and re-probes as well.
[bool]$Script:RecheckEnvironmentSuspended = $false
# Single module-scoped HttpClient reused by Test-EnvironmentSuspended so the suspension probe
# doesn't allocate a new handler/socket per call (which contributes to .NET port exhaustion).
$Script:EnvironmentSuspendedHttpClient = $null
# Dispose that shared HttpClient when the module unloads - Remove-Module, or the implicit remove
# during Import-Module -Force - so repeated import/remove cycles don't keep sockets and handlers
# alive longer than necessary.
$ExecutionContext.SessionState.Module.OnRemove = {
    if ($null -ne $Script:EnvironmentSuspendedHttpClient) {
        $Script:EnvironmentSuspendedHttpClient.Dispose()
        $Script:EnvironmentSuspendedHttpClient = $null
    }
}
# Reusable authentication session state (cookie, base URL, credential, WebView2 profile/environment,
# etc.) lives per-session in $Script:OmadaSessions instead of single unkeyed variables - see
# Get-OmadaSessionKey.ps1 / Get-OmadaSessionContext.ps1.
$Script:OmadaSessions = @{}
# Bridges the blocking WinForm/WebView2 dialog's .NET event-handler closures (which cannot see the
# Invoke-OmadaRequest call stack) to the session context driving the current interactive login.
$Script:CurrentWebView2Session = $null
# Deprecation warnings are shown once per session rather than once per request - see
# Write-OmadaDeprecationWarning.ps1. Module scope means Import-Module -Force resets the set.
$Script:DeprecationWarningsShown = @{}
# Test-only override for "now" in the deprecation date comparison, so the date-gated branches can be
# exercised on both sides of every boundary today. $null means "use the real clock".
$Script:DeprecationUtcNow = $null
$Script:DebugWebView2 = $false
$Script:CurrentScenario = $null
$Script:FunctionName = $null
$Script:InstalledEdgeFilePath = $null
$Script:LastCheckedHost = $null
$Script:LastLoggedSecond = -1
[double]$Script:LastFiredSecond = -1
$Script:LoginFailed = $false
$Script:LoginState = $null
$Script:LoginSubState = $null
$Script:LoginTask = $null
# The snapshot of the sign-in page the current decision is being made from, and the submit
# button still to be clicked once a field has been filled in.
$Script:PageState = $null
$Script:PendingSubmitId = $null
# Seconds the sign-in automation may sit on the same page without making progress before it stops
# filling in credentials and lets the user sign in manually - see Switch-ToManualLogin.ps1. Generous
# on purpose: a slow round trip to Entra must not be mistaken for a changed sign-in page.
$Script:LoginAutomationFallbackTimeout = 60
# Every element the Microsoft sign-in automation recognizes a screen by, in one place so that the
# JavaScript that reads the page (Get-EntraSignInProbeScript) and the rule set that judges what it
# read (Resolve-EntraSignInScreen) cannot drift apart on a selector.
#
# These ids are what makes the automation language agnostic: the Entra sign-in app is served fully
# localized, but its element ids are the same in every language, so a screen is identified by an id
# and never by the words on it. They are, however, internal to Microsoft's sign-in app and not a
# contracted API - which is why Resolve-EntraSignInScreen keeps structural fallbacks behind them and
# ends in Switch-ToManualLogin rather than in a guess when none of them match.
$Script:EntraSignInElementId = [ordered]@{
    UserName           = "i0116"
    Password           = "i0118"
    Submit             = "idSIButton9"
    Back               = "idBtn_Back"
    KeepMeSignedIn     = "KmsiCheckboxField"
    PasswordlessNumber = "idRemoteNGC_DisplaySign"
    NumberMatch        = "idRichContext_DisplaySign"
    OneTimeCode        = "idTxtBx_SAOTCC_OTC"
    OneTimeCodeSubmit  = "idSubmit_SAOTCC_Continue"
    ProofsContainer    = "idDiv_SAOTCS_Proofs"
    MethodPicker       = "i0281"
    SwitchToCredPicker = "idA_PWD_SwitchToCredPicker"
    SignInAnotherWay   = "signInAnotherWay"
    ForgotPassword     = "idA_PWD_ForgotPassword"
    PasswordError      = "passwordError"
    CantAccessAccount  = "cantAccessAccount"
    MfaResendTotp      = "idA_SAASTO_Resend"
    MfaResendDs        = "idA_SAASDS_Resend"
}
# The JavaScript built from the table above, kept because it is built from nothing else: the same
# table produces the same script, and the sign-in reads the page over and over while a user works
# through it. Reset here rather than only inside the function so that Import-Module -Force rebuilds
# it - otherwise an edited selector table would keep serving the script made from the old one.
$Script:EntraSignInProbeScript = $null
# Set once per sign-in when -PreferredMfaMethod named a verification method the account does not
# offer, so the 150 ms timer reports that once instead of on every tick.
$Script:PreferredMfaMethodWarningIssued = $false
# Wall clock of the last "still waiting for approval" line, so a multi-minute wait for someone to
# reach for their phone reports progress without filling the verbose stream at 150 ms intervals.
$Script:MfaWaitLastReported = $null
# Seconds between two of those lines.
$Script:MfaWaitReportInterval = 10
$Script:ManualLoginFallbackActive = $false
$Script:UnmatchedPageSignature = $null
$Script:UnmatchedPageSince = $null
# Set by Stop-OmadaLogin when a sign-in has been refused in a way that retrying cannot change - an
# identity-provider error rendered on Omada's own logon page, for instance. Both login drivers check
# this instead of opening another browser window, and report it instead of "Could not authenticate".
# It is cleared once per sign-in rather than once per window: surviving the window closing is exactly
# what lets the driver see why the window closed.
$Script:LoginAbortReason = $null
# State of the logon-page scrape in Get-WebView2LogonPageError. Per browser window, so it is cleared
# by Reset-LoginAutomationState along with the rest of the per-window automation state.
$Script:LogonPageErrorTask = $null
$Script:LogonPageErrorLastCheck = $null
$Script:LogonPageErrorReported = $null
# Milliseconds between two reads of the logon page. The WebView2 timer ticks every 150 ms, and a page
# that is still loading gains nothing from being read seven times a second.
$Script:LogonPageErrorInterval = 1000
$Script:MaxLoginRetries = 3
$Script:MfaRequestDisplayed = $false
$Script:MicrosoftOnlineLogin = $false
$Script:NameObjects = $null
$Script:OmadaWatchdogStart = $null
$Script:OmadaWatchdogRunning = $false
$Script:OmadaWatchdogTimeout = 600
# Only used to seed the first session context created in this Runspace when the module is imported
# with -ArgumentList @{ Parameters = @{ OmadaWebAuthCookie = ... } } - see Get-OmadaSessionContext.ps1.
$Script:OmadaWebAuthCookie = $null
$Script:PreviousScenario = $null
$Script:ProgressCounter = 0
$Script:StopError = $false
$Script:Timer = $null
$Script:Task = $null
$Script:UserAgent = "OmadaWeb.PS/{0}"
$Script:UserAgentParameterUsed = $false
$Script:WebView2UpdateChecked = $false
$Script:WebView2WpfPath = $null
$Script:WebView2LatestVersion = $null
# Pinned versions and expected SHA-256 hashes of every binary the module downloads, cached by
# Get-DependencyLock on first use. Nothing is downloaded that is not listed there.
$Script:DependencyLock = $null

if ($PsBoundParameters.ContainsKey("CheckForUpdates") -and $PsBoundParameters["CheckForUpdates"] -eq $false) {
    "Skipping update check based on provided parameter" | Write-Verbose
    $Script:WebView2UpdateChecked = $true
}

"{0} - Set paths" -f $MyInvocation.MyCommand | Write-Verbose
#Dependency lock location. Ships next to this file, both in the source tree and in the built module,
#so $PSScriptRoot resolves it in either layout.
$Script:DependencyLockPath = [System.IO.Path]::Combine($PSScriptRoot, "DependencyLock.psd1")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:DependencyLockPath | Write-Verbose

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
$WebView2ArchitectureFolder = "win-x86"
if ($Env:PROCESSOR_ARCHITECTURE -eq "AMD64") {
    $WebView2ArchitectureFolder = "win-x64"
}
$WebView2BasePath = [System.IO.Path]::Combine($WebBinBasePath, $WebView2ArchitectureFolder)

#WebView2 assemblies bundled with the module, laid out by Build\Get-BundledDependency.ps1 as
#lib\<edition>\<architecture>. They are fetched and hash-verified at build time, which is what makes
#the default authentication type work on a machine with no egress to nuget.org, and it means the
#assemblies load from the module's own - usually read-only - install directory instead of from a
#user-writable one.
#
#Everything below is a straight path swap: when the three files are all there the script-scope paths
#point into the package, otherwise they point at %LOCALAPPDATA%\OmadaWeb.PS\Bin and Install-WebView2
#downloads into it exactly as it always has. Nothing is ever copied out of the bundle into Bin, and
#the bundled folder is never written to. -UpdateDependencies deliberately skips the bundle, so it
#still forces a fresh download.
$Script:WebView2Bundled = $false
$BundledWebView2BasePath = [System.IO.Path]::Combine($PSScriptRoot, "lib", $PowerShellType, $WebView2ArchitectureFolder)
if (-not $UpdateDependencies) {
    $BundledWebView2File = @("Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.WinForms.dll", "WebView2Loader.dll")
    $BundledWebView2Complete = $true
    foreach ($FileName in $BundledWebView2File) {
        if (!(Test-Path ([System.IO.Path]::Combine($BundledWebView2BasePath, $FileName)) -PathType Leaf)) {
            $BundledWebView2Complete = $false
        }
    }
    if ($BundledWebView2Complete) {
        $WebView2BasePath = $BundledWebView2BasePath
        $Script:WebView2Bundled = $true
        "{0} - Using the WebView2 assemblies bundled with the module: '{1}'" -f $MyInvocation.MyCommand, $WebView2BasePath | Write-Verbose
    }
    else {
        "{0} - No complete WebView2 bundle at '{1}'; falling back to downloading into '{2}'" -f $MyInvocation.MyCommand, $BundledWebView2BasePath, $WebView2BasePath | Write-Verbose
    }
}

#Only the download path writes here, so the folder is created only when that path is the one in use.
#Creating it while running from the bundle would leave an empty folder behind for a download that is
#never going to happen.
if (!$Script:WebView2Bundled) {
    New-Item -ItemType Directory -Path $WebView2BasePath -Force | Out-Null
}

#WebView2 Core Location
$Script:WebView2CorePath = [System.IO.Path]::Combine($WebView2BasePath, "Microsoft.Web.WebView2.Core.dll")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebView2CorePath | Write-Verbose

#WebView2 WinForms Location
$Script:WebView2WinFormsPath = [System.IO.Path]::Combine($WebView2BasePath, "Microsoft.Web.WebView2.WinForms.dll")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebView2WinFormsPath | Write-Verbose

#WebView2 Loader Location
$Script:WebView2LoaderPath = [System.IO.Path]::Combine($WebView2BasePath, "WebView2Loader.dll")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebView2LoaderPath | Write-Verbose

#WebView2 User Profile Base Location - actual profile folders are created per session (see Get-OmadaSessionContext)
$Script:WebView2UserProfileBasePath = [System.IO.Path]::Combine($ModuleAppDataPath, "Edge User Data")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebView2UserProfileBasePath | Write-Verbose

#Selenium/Edge user-data-dir Base Location - actual profile folders are created per session (see Start-EdgeDriver)
$Script:SeleniumProfileBasePath = [System.IO.Path]::Combine($ModuleAppDataPath, "Profiles")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:SeleniumProfileBasePath | Write-Verbose

#Module root under %LOCALAPPDATA%, holding every artefact the module stores (see Clear-OmadaWebCache)
$Script:ModuleAppDataPath = $ModuleAppDataPath

#Encrypted cookie cache location. Created on demand by Get-OmadaCookieCacheFilePath so importing the
#module never leaves an empty folder behind.
$Script:CookieCachePath = [System.IO.Path]::Combine($ModuleAppDataPath, "Cookies")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:CookieCachePath | Write-Verbose

#Cookie caches used to live directly in %TEMP%. Ones left there by an earlier module version are
#migrated to $Script:CookieCachePath on first use, and Clear-OmadaWebCache cleans up the rest.
$Script:LegacyCookieCachePath = $Env:Temp

#Edge Location
$Script:InstalledEdgeFilePath = [System.IO.Path]::Combine($InstalledEdgeBasePath, "msedge.exe")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:InstalledEdgeFilePath | Write-Verbose
if ($PSBoundParameters["InstalledEdgeBasePath"] -and -not (Test-Path $Script:InstalledEdgeFilePath -PathType Leaf)) {
    "Cannot find path '{0}'. Please make sure that it exists!" -f $Script:InstalledEdgeFilePath | Write-Error -ErrorAction "Stop"
}

#MsEdgeView2 Location (in case it cannot be found automatically)
$MsEdgeWebView2ExecPath = Get-ChildItem -Path $InstalledEdgeBasePath -Filter "msedgewebview2.exe" -Recurse -ErrorAction SilentlyContinue | Sort-Object "DirectoryName" | Select-Object -First 1

$MsEdgeFixedRunTimePath = $null
if ($null -eq $MsEdgeWebView2ExecPath) {
    $MsEdgeFixedRunTimePath = Get-ChildItem (Join-Path $ModuleAppDataPath -ChildPath ("Bin\WebView2RunTime\{0}" -f $RuntimeFolder)) -Filter "msedgewebview2.exe" -Recurse -ErrorAction SilentlyContinue | Sort-Object "DirectoryName" | Select-Object -First 1
}
if ($null -ne $MsEdgeWebView2ExecPath -and (Test-Path $MsEdgeWebView2ExecPath.FullName -PathType Leaf)) {
    $Script:InstalledEdgeWebView2Path = $MsEdgeWebView2ExecPath.FullName
    "{0} - Using built-in MsEdgeWebView2 from: '{1}'" -f $MyInvocation.MyCommand, $Script:InstalledEdgeWebView2Path | Write-Verbose
}
elseif ($null -ne $MsEdgeFixedRunTimePath -and (Test-Path $MsEdgeFixedRunTimePath.FullName -PathType Leaf)) {
    $Script:InstalledEdgeWebView2Path = $MsEdgeFixedRunTimePath.FullName
    "{0} - Using fixed MsEdgeWebView2 runtime: '{1}'" -f $MyInvocation.MyCommand, $Script:InstalledEdgeWebView2Path | Write-Verbose
}
else {
    "MsEdgeWebView2.exe was not found in the expected folder: '{0}'. It is needed when using WebView2. The module will try to locate it automatically.`nIn case you get an error you can download the fixed version from 'https://developer.microsoft.com/en-us/Microsoft-edge/webview2/' (x86/x64) and follow these steps.`n1. Download the cab file`n2. Open a CMD commandline and run the following command (replace the variables <var> accordingly):`n   set TARGETDIR=%LOCALAPPDATA\OmadaWeb.PS\Bin\WebView2RunTime\<win-x86 or win-x64>;`n   mkdir %TARGETDIR%;`n   expand `"<downloaded cab file path>`" -F:* `"%TARGETDIR%`";" -f $InstalledEdgeBasePath | Write-Warning
    $Script:InstalledEdgeWebView2Path = $null
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

# Import-Module -ArgumentList can carry an OmadaWebAuthCookie, so this goes through the redaction
# walker like every other object that reaches the verbose stream. It has to be logged from here
# rather than from where the parameters are processed further up: the walker is one of the functions
# the loop above dot-sources, so it does not exist yet at that point.
"PsBoundParameters = {0}" -f (ConvertTo-RedactedLogString -InputObject $PsBoundParameters) | Write-Verbose

"Validate version" | Write-Verbose
try {
    $InstalledModule = Get-InstalledModuleInfo -ModuleName $ModuleName
    # Get-InstalledModuleInfo returns $null whenever the module was imported from a path instead of
    # installed - every build and every test run. Reading a member off that $null is an error under
    # StrictMode, and the empty catch below swallowed it, so $Script:UserAgent kept its unformatted
    # "OmadaWeb.PS/{0}" template and every request built from it was rejected as a malformed header.
    if ($null -eq $InstalledModule -or -not $InstalledModule['RepositorySource'] -or $InstalledModule['RepositorySource'] -notlike "*powershellgallery.com*") {
        "Module '{0}' was not sourced from the PowerShell Gallery. Skipping version check." -f $ModuleName | Write-Verbose
        $Script:UserAgent = $Script:UserAgent -f "Development"
    }
    else {
        $Script:UserAgent = $Script:UserAgent -f $($InstalledModule['Version'])
        $GalleryVersion = Get-GalleryModuleVersion -ModuleName $ModuleName

        if (-not $GalleryVersion) {
        }
        else {
            if ([System.Version]$InstalledModule['Version'] -lt [System.Version]$GalleryVersion) {
                "The installed version {0} of '{1}' is outdated. Latest version: {2}. Execute Update-Module {1} to update to the latest version!" -f ($($InstalledModule['Version'])), $ModuleName, $GalleryVersion | Write-Warning
            }
            elseif ([System.Version]$InstalledModule['Version'] -eq [System.Version]$GalleryVersion) {
                "The installed version {0} of '{1}' is up-to-date." -f ($($InstalledModule['Version'])) , $ModuleName | Write-Verbose
            }
            else {
                "The installed version {0} of '{1}' is newer than the gallery version {2}." -f ($($InstalledModule['Version'])), $ModuleName, $GalleryVersion | Write-Warning
            }
        }
    }

}
catch {}

$Script:EdgeProfiles = Get-EdgeProfile

"Module {0} loaded successfully" -f $ModuleName | Write-Verbose