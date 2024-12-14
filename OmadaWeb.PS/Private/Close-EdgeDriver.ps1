function Close-EdgeDriver {
    "{0}" -f $MyInvocation.MyCommand | Write-Verbose
    if ($null -ne $EdgeDriver) {
        if ($EdgeDriver.HasActiveDevToolsSession) {
            $null = $EdgeDriver.Close()
        }
        $null = $EdgeDriver.Dispose()
    }
}