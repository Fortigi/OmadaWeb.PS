function Invoke-EdgeDriverLogin {


    #$EdgeDriver.Manage().Window.position = [System.Drawing.Point]::new($CenterScreenWidth,$CenterScreenHeight)
    #$WindowSize = [System.Drawing.Size]::new($WindowWidth, $WindowHeight)
    #$EdgeDriver.Manage().Window.size = $WindowSize

    $EdgeDriver.Navigate().GoToUrl($Script:OmadaWebBaseUrl) | Out-Null
    $EdgeDriver.SwitchTo().Window($EdgeDriver.CurrentWindowHandle) | Out-Null


}
