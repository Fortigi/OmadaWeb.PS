function Start-EdgeDriver {
    PARAM(
        [string]$EdgeProfile,
        [switch]$InPrivate
    )
    $JsonLibraryType = Invoke-WebEdgeDriverFramework
    try {
        Add-Type -Path $($Script:WebDriverPath)
    }
    catch {
        [void] [System.Reflection.Assembly]::LoadFrom($Script:WebDriverPath)
    }
    try {
        switch ($JsonLibraryType) {
            "Newtonsoft.Json" {
                Add-Type -Path $($Script:NewtonsoftJsonPath)
            }
            "System.Text.Json" {
                if ($PSVersionTable.PSVersion.Major -le 5) {

                    #$DllFiles = Get-ChildItem ".\Bin" -Filter "*.dll" | Where-Object { $_.Name -notin @('System.Text.Json.dll', 'Webdriver.dll') }
                    #do {
                    #    try {
                    #        $DllFiles | ForEach-Object {
                    #            [System.Reflection.Assembly]::LoadFrom($_.FullName)
                    #            Add-Type -Path $_.FullName
                    #            $Failed = $false
                    #        }
                    #    }
                    #    catch {
                    #        $_.Exception.Message
                    #        $Failed = $true
                    #    }
                    #}until($Failed -eq $false)

                    #[void] [System.Reflection.Assembly]::LoadFrom($Script:SystemRuntimePath)
                    #[void] [System.Reflection.Assembly]::LoadFrom($Script:SystemTextJsonPath)

                    Add-Type -Path $($Script:SystemRuntimePath)
                    Add-Type -Path $($Script:SystemTextJsonPath)
                }
            }
        }
    }
    catch {
        [void] [System.Reflection.Assembly]::LoadWithPartialName("OpenQA.Selenium.Edge")
    }
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

    $WindowWidth = 564
    $WindowHeight = 973

    $ScreenSize = [System.Windows.Forms.Screen]::PrimaryScreen
    $CenterScreenWidth = [System.Math]::Ceiling((($ScreenSize.WorkingArea.Width - $WindowWidth) / 2))
    $CenterScreenHeight = [System.Math]::Ceiling((($ScreenSize.WorkingArea.Height - $WindowHeight) / 2))

    $EdgeOptions = New-Object  OpenQA.Selenium.Edge.EdgeOptions
    $EdgeOptions.AddArgument("--disable-logging");
    $EdgeOptions.AddArgument("--no-first-run");
    $EdgeOptions.AddArgument("--window-size=$WindowWidth,$WindowHeight" )
    $EdgeOptions.AddArgument("--window-position=$CenterScreenWidth,$CenterScreenHeight" )
    $EdgeOptions.AddArgument("--content-shell-hide-toolbar")
    $EdgeOptions.AddArgument("--top-controls-hide-threshold")
    $EdgeOptions.AddArgument("--app-auto-launched")
    $EdgeOptions.AddArgument("--disable-blink-features=AutomationControlled")
    $EdgeOptions.AddArgument("--disable-infobars")
    $EdgeOptions.AddArgument("--log-level=3")
    $EdgeOptions.AddArgument("--lang=en")
    $EdgeOptions.AddExcludedArgument("enable-automation")
    $EdgeOptions.AddAdditionalOption("useAutomationExtension", $false)

    if ($InPrivate) {
        if (![string]::IsNullOrWhiteSpace($EdgeProfile)) {
            "InPrivate mode is enabled. The -EdgeProfile parameter will be ignored." | Write-Warning
        }
        $EdgeOptions.AddArgument("--inprivate")
    }
    elseif (![string]::IsNullOrWhiteSpace($EdgeProfile) -and $EdgeProfile -ne "Default") {
        # This results in an error most of the time. Need to find a way to handle this.
        "Loading Edge profile: '{0}'" -f $EdgeProfile | Write-Verbose
        $ProfileFolderName = ($Script:EdgeProfiles | Where-Object { $_.Name -eq $EdgeProfile }).Folder
        $ProfileArgument = '--profile-directory="{0}"' -f $ProfileFolderName
        "Profile argument: '{0}'" -f $ProfileArgument | Write-Verbose
        $EdgeOptions.AddArgument($ProfileArgument)
        $UserProfileDir = New-Item (Join-Path $env:LOCALAPPDATA -ChildPath "OmadaWeb.PS\Profiles\$ProfileFolderName") -ItemType Directory -Force
        "Using profile user-data-dir: '{0}'" -f $UserProfileDir.FullName | Write-Verbose
        $UserDataDirArgument = 'user-data-dir="{0}"' -f $UserProfileDir.FullName
        "User data argument: '{0}'" -f $UserDataDirArgument | Write-Verbose
        $EdgeOptions.AddArgument($UserDataDirArgument)
    }

    $EdgeDriverService = [OpenQA.Selenium.Edge.EdgeDriverService]::CreateDefaultService($($Script:EdgeDriverPath))
    $EdgeDriverService.HideCommandPromptWindow = $true
    $EdgeDriverService.SuppressInitialDiagnosticInformation = $true;
    try {
        $EdgeDriver = New-Object OpenQA.Selenium.Edge.EdgeDriver($EdgeDriverService, $EdgeOptions)
    }
    catch {
        if (![string]::IsNullOrWhiteSpace($EdgeProfile) -and $EdgeProfile -ne "Default" -and $_.Exception.Message -match "DevToolsActivePort") {
               "It seems that Edge profile '{0}' is currently running.  It is not possible use this profile when it is active. To use this profile, please close that browser session. You can also choose to omit -EdgeProfile parameter." -f $EdgeProfile | Write-Error -ErrorAction "Stop" -ErrorId "EdgeProfileActive"
        }
        else {
            Throw $_
        }
        Close-EdgeDriver
        break
    }
    return $EdgeDriver
}