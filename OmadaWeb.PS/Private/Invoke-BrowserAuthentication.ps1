function Invoke-BrowserAuthentication {
    [CmdletBinding()]
    PARAM()

    "{0} - Set Browser authentication" -f $MyInvocation.MyCommand | Write-Verbose

    if ($BoundParams.ForceAuthentication) {
        $Script:OmadaWebAuthCookie = $null
    }
    $Script:Credential = $null
    if ($BoundParams.keys -contains "Credential") {
        $Script:Credential = $BoundParams.Credential
    }
    switch ($Script:LastSessionType) {
        { $_ -eq "Normal" -and $($BoundParams.InPrivate).IsPresent -eq $true } {
            "{0} - Reset OmadaWebAuthCookie because session has changed to InPrivate" -f $MyInvocation.MyCommand | Write-Verbose
            $Script:OmadaWebAuthCookie = $null
            $Script:LastSessionType = "InPrivate"
        }
        { $_ -eq "InPrivate" -and $($BoundParams.InPrivate).IsPresent -eq $false } {
            "{0} - Reset OmadaWebAuthCookie because session has changed from InPrivate to not InPrivate" -f $MyInvocation.MyCommand | Write-Verbose
            $Script:OmadaWebAuthCookie = $null
            $Script:LastSessionType = "Normal"
        }
        default {}
    }

    if ($null -ne $($Script:OmadaWebAuthCookie) -and ($Script:OmadaWebBaseUrl -like "*$($Script:OmadaWebAuthCookie.domain)*" )) {
        "{0} - Using existing cookie for this domain: {1}" -f $MyInvocation.MyCommand, $Script:OmadaWebBaseUrl | Write-Verbose
        if ("Cookie" -notin $BoundParams.Headers.Keys) {
            $BoundParams.Headers.Add("Cookie", ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "="))
        }
        else {
            $BoundParams.Headers.Cookie = ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "=")
        }
        $Session.Cookies.Add((New-Object System.Net.Cookie("oisauthtoken", $($Script:OmadaWebAuthCookie.Value), "/", $($Script:OmadaWebAuthCookie.domain))))
    }
    else {
        "{0} - OmadaWebAuthCookie not exists or is for different domain. Need to authenticate!" -f $MyInvocation.MyCommand | Write-Verbose
        $EdgeDriverData = Invoke-DataFromWebDriver -EdgeProfile $BoundParams.EdgeProfile -InPrivate:$($BoundParams.InPrivate).IsPresent
        $Script:OmadaWebAuthCookie = $EdgeDriverData[0]

        $BoundParams.UserAgent = $EdgeDriverData[1]

        $Session.UserAgent = $EdgeDriverData[1]

        if ("Cookie" -notin $BoundParams.Headers.Keys) {
            $BoundParams.Headers.Add("Cookie", ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "="))
        }
        else {
            $BoundParams.Headers.Cookie = ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "=")
        }

        $Session.Cookies.Add((New-Object System.Net.Cookie("oisauthtoken", $($Script:OmadaWebAuthCookie.Value), "/", $($Script:OmadaWebAuthCookie.domain))))
    }

    if (![string]::IsNullOrEmpty($($BoundParams.CookiePath))) {
        $CookiePath = (Join-Path $($BoundParams.CookiePath) -ChildPath ("{0}.cookie" -f $Script:OmadaWebAuthCookie.domain))
        $CookieObject = [PSCustomObject]@{
            OmadaWebAuthCookie = $Script:OmadaWebAuthCookie
        }

        try {
            $CookieObject | Export-Clixml $CookiePath -Force
            "Find the exported cookie file: {0}" -f $CookiePath | Write-Host
        }
        catch [System.UnauthorizedAccessException] {
            "Unable to export the cookie file due insufficient permissions in folder {0}" -f $($BoundParams.CookiePath) | Write-Warning
        }
        catch {
            Throw
        }
    }
    elseif ($BoundParams.Keys -notcontains "SkipCookieCache") {
        "{0} - Caching encrypted cookie" -f $MyInvocation.MyCommand | Write-Verbose
        $CookieObject = [PSCustomObject]@{
            OmadaWebAuthCookie = $Script:OmadaWebAuthCookie
        }
        $CookieCliXmlContent = [System.Management.Automation.PSSerializer]::Serialize($CookieObject, [int]::MaxValue)
        $SecureCookieCliXml = ConvertTo-SecureString -String $CookieCliXmlContent -AsPlainText -Force
        try {
            $SecureCookieCliXml | Export-Clixml -Path $Script:CookieCacheFilePath -Force
            "{0} - Updated encrypted cookie to: {1}" -f $MyInvocation.MyCommand, $Script:CookieCacheFilePath | Write-Verbose
        }
        catch [System.UnauthorizedAccessException] {
            "Unable to cache cookie due insufficient permissions to the temp folder" | Write-Warning
        }
        catch {
            Throw
        }
    }
}
