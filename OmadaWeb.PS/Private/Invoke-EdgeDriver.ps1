function Invoke-EdgeDriver {
    Invoke-WebEdgeDriverFramework
    try {
        Add-Type -Path $($Script:WebDriverPath)
    }
    catch {
        [void] [System.Reflection.Assembly]::LoadFrom($Script:WebDriverPath)
        Add-Type -Path $($Script:NewtonsoftJsonPath)
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
    #$EdgeOptions.AddArgument("--inprivate")
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

    #TODO: Fails to load with profile currently
    #$EdgeOptions.AddArgument("--profile-directory='Default'")
    #$UserProfile = (Join-Path $env:LOCALAPPDATA -ChildPath "Microsoft\Edge\User Data").Replace('\','\\')
    #$EdgeOptions.AddArgument("user-data-dir=$UserProfile")

    $EdgeDriverService = [OpenQA.Selenium.Edge.EdgeDriverService]::CreateDefaultService($($Script:EdgeDriverPath))
    $EdgeDriverService.HideCommandPromptWindow = $true
    $EdgeDriverService.SuppressInitialDiagnosticInformation = $true;
    $EdgeDriver = New-Object OpenQA.Selenium.Edge.EdgeDriver($($Script:EdgeDriverPath), $EdgeOptions)

    return $EdgeDriver

}
