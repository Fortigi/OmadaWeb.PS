function Start-EdgeDriverLogin {
    [CmdletBinding()]
    PARAM()

    if ($null -eq $EdgeDriver) {
        "Browser authentication failed to start!" | Write-Error -ErrorAction "Stop"
    }

    #$EdgeDriver.Manage().Window.position = [System.Drawing.Point]::new($CenterScreenWidth,$CenterScreenHeight)
    #$WindowSize = [System.Drawing.Size]::new($WindowWidth, $WindowHeight)
    #$EdgeDriver.Manage().Window.size = $WindowSize

    try {
        $EdgeDriver.Navigate().GoToUrl($Script:OmadaWebBaseUrl) | Out-Null
        $EdgeDriver.SwitchTo().Window($EdgeDriver.CurrentWindowHandle) | Out-Null
    }
    catch {
        if ($_.Exception.Message -like "*failed to check if window was closed: disconnected: not connected to DevTools*") {
            "Edge window seems to be closed before authentication was completed. Re-open Edge driver!" | Write-Host -ForegroundColor Yellow
        }
        else {
            $_
        }
    }
}