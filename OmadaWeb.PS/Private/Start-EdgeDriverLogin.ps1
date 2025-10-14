function Start-EdgeDriverLogin {
    [CmdletBinding()]
    param()

    "{0} - Starting Edge WebDriver login" -f $MyInvocation.MyCommand | Write-Verbose

    if ($null -eq $EdgeDriver) {
        "Browser authentication failed to start!" | Write-Error -ErrorAction "Stop"
    }

    #$EdgeDriver.Manage().Window.position = [System.Drawing.Point]::new($CenterScreenWidth,$CenterScreenHeight)
    #$WindowSize = [System.Drawing.Size]::new($WindowWidth, $WindowHeight)
    #$EdgeDriver.Manage().Window.size = $WindowSize

    try {
        "{0} - Navigate to: {1}" -f $MyInvocation.MyCommand, $Script:OmadaWebBaseUrl | Write-Verbose
        $EdgeDriver.Navigate().GoToUrl($Script:OmadaWebBaseUrl) | Out-Null
        "{0} - Switch Edge WebView window" -f $MyInvocation.MyCommand | Write-Verbose
        $EdgeDriver.SwitchTo().Window($EdgeDriver.CurrentWindowHandle) | Out-Null
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}