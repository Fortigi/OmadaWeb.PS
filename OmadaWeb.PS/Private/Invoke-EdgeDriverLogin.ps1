function Invoke-EdgeDriverLogin {

    if($null -eq $EdgeDriver) {
        "Browser authentication failed to start!" | Write-Error -ErrorAction "Stop"
    }

    #$EdgeDriver.Manage().Window.position = [System.Drawing.Point]::new($CenterScreenWidth,$CenterScreenHeight)
    #$WindowSize = [System.Drawing.Size]::new($WindowWidth, $WindowHeight)
    #$EdgeDriver.Manage().Window.size = $WindowSize

    $EdgeDriver.Navigate().GoToUrl($Script:OmadaWebBaseUrl) | Out-Null
    $EdgeDriver.SwitchTo().Window($EdgeDriver.CurrentWindowHandle) | Out-Null

}
