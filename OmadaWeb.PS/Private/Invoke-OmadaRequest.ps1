function Invoke-OmadaRequest {
    [CmdletBinding(DefaultParameterSetName = "StandardMethod")]
    param()

    dynamicparam {
        return Set-DynamicParameter -FunctionName $Script:FunctionName
    }
    process {
        try {

            "{0} called for {1} by {2}" -f $MyInvocation.MyCommand, $Script:FunctionName, (Get-PSCallStack)[1].Command | Write-Verbose

            $BoundParams = $PsCmdLet.MyInvocation.BoundParameters

            if ("UserAgent" -notin $BoundParams.Keys) {
                $BoundParams.Add("UserAgent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0")
            }

            if ("Headers" -notin $BoundParams.Keys) {
                $BoundParams.Add("Headers", @{})
            }

            $Uri = [System.Uri]::new($BoundParams.Uri)
            if ($null -ne $Uri) {
                $Script:OmadaWebBaseUrl = "{0}://{1}" -f $Uri.Scheme, $Uri.Host
                if (!$Uri.IsDefaultPort) {
                    $Script:OmadaWebBaseUrl = "{0}://{1}:{2}" -f $Uri.Scheme, $Uri.Host, $Uri.Port
                }
                "{0} - BaseUrl: {1}" -f $MyInvocation.MyCommand, $Script:OmadaWebBaseUrl | Write-Verbose
            }
            else {
                "Could not determine the base URL from '{0}', is the URL correct?" -f $BoundParams.Uri | Write-Error -ErrorAction "Stop"
            }

            if ("UserAgent" -notin $BoundParams.Keys) {
                $BoundParams.Add("UserAgent", $DefaultUserAgent)
            }

            $Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
            $Session.UserAgent = $BoundParams.UserAgent

            if ("AuthenticationType" -notin $BoundParams.Keys) {
                $BoundParams.Add("AuthenticationType", "Browser")
            }

            if ($null -eq $Script:OmadaWebAuthCookie) {
                if ($BoundParams.Keys -contains "CookiePath") {
                    $CookiePath = (Join-Path $($BoundParams.CookiePath) -ChildPath ("{0}.cookie" -f $Uri.Authority))
                    "{0} - Loading custom cookie: {1}" -f $MyInvocation.MyCommand, $CookiePath | Write-Verbose
                    if (!(Test-Path $CookiePath -PathType Leaf)) {
                        "No cookie found at '{0}' not found, try to create a new one." -f $CookiePath | Write-Warning
                    }
                    else {
                        try {
                            $Script:OmadaWebAuthCookie = (Import-Clixml $CookiePath).OmadaWebAuthCookie
                            "{0} - Cookie:`r{1}" -f $MyInvocation.MyCommand, ($Script:OmadaWebAuthCookie | ConvertTo-Json) | Write-Verbose
                        }
                        catch {
                            "Failure loading cookie, try to create a new one." | Write-Verbose
                        }
                    }
                }
                elseif ($BoundParams.Keys -notcontains "SkipCookieCache") {
                    $Script:CookieCacheFilePath = Join-Path $Env:Temp -ChildPath (([System.Guid]([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($($Uri.Authority))))).Guid -replace "-", "")
                    if ($BoundParams.Keys -notcontains "ForceAuthentication" -and (Test-Path $Script:CookieCacheFilePath -PathType Leaf)) {
                        "{0} - Loading cached encrypted cookie: {1}" -f $MyInvocation.MyCommand, $Script:CookieCacheFilePath | Write-Verbose

                        try {
                            $Script:OmadaWebAuthCookie = ([System.Management.Automation.PSSerializer]::Deserialize([System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                                        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR((Import-Clixml $Script:CookieCacheFilePath))
                                    ))).OmadaWebAuthCookie
                            "{0} - Cookie:`r{1}" -f $MyInvocation.MyCommand, ($Script:OmadaWebAuthCookie | ConvertTo-Json) | Write-Verbose
                        }
                        catch {
                            "Failure loading cookie, try to create a new one." | Write-Verbose
                        }
                    }
                }
            }

            "{0} - Authentication type: {1}" -f $MyInvocation.MyCommand, $($BoundParams.AuthenticationType) | Write-Verbose

            switch ($BoundParams.AuthenticationType) {
                "Windows" {
                    "{0} - {1} Authentication" -f $MyInvocation.MyCommand, $_ | Write-Verbose
                    Invoke-WindowsAuthentication
                }
                "Browser" {
                    "{0} - {1} Authentication" -f $MyInvocation.MyCommand, $_ | Write-Verbose
                    Invoke-BrowserAuthentication
                }
                "OAuth" {
                    "{0} - {1} Authentication" -f $MyInvocation.MyCommand, $_ | Write-Verbose
                    Invoke-EntraIdOAuth
                }
                "Integrated" {
                    "{0} - {1} Authentication " -f $MyInvocation.MyCommand, $_ | Write-Verbose
                    Invoke-IntegratedAuthentication
                }
                "Basic" {
                    "{0} - {1} Authentication" -f $MyInvocation.MyCommand, $_ | Write-Verbose
                    Invoke-BasicAuthentication
                }
                default {
                    "{0} - {1} not supported!" -f $MyInvocation.MyCommand, $_ | Write-Error -ErrorAction "Stop"
                }
            }

            if ($BoundParams.Method -in @('PUT', 'POST', 'PATCH')) {
                "{0} - {1} - Add Body" -f $MyInvocation.MyCommand, $BoundParams.Method | Write-Verbose
                Set-Body
            }

            $BoundParams.Add("WebSession", $Session)

            # UseBasicParsing is deprecated since PowerShell Core 6, there it is only set when using PowerShell 5 (https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest?view=powershell-7.4#-usebasicparsing)
            if ($PSVersionTable.PSVersion.Major -lt 6) {
                $BoundParams.Add("UseBasicParsing", $true)
            }

            "{0} - {1}" -f $MyInvocation.MyCommand, ($BoundParams | ConvertTo-Json) | Write-Verbose
            try {
                $CustomErrorTrigger = "Login failed - {0}" -f (New-Guid).Guid.ToString()
                switch ($Script:FunctionName) {
                    "Invoke-RestMethod" {

                        if ("Accept" -notin $BoundParams.Headers.Keys) {
                            $BoundParams.Headers.Add("Accept", "application/json")
                        }

                        if ("ContentType" -in $BoundParams.Keys) {
                            $BoundParams.Headers.Add("Content-Type", $BoundParams.ContentType)
                            $BoundParams.Remove("ContentType") | Out-Null
                        }
                        elseif ("Content-Type" -notin $BoundParams.Headers.Keys) {
                            $BoundParams.Headers.Add("Content-Type", "application/json")
                        }
                        $Parameters = Set-RequestParameter

                        $Return = (Invoke-RestMethod @Parameters)

                        #To support -SkipHttpErrorCheck
                        if ($BoundParams.Keys -contains "SkipHttpErrorCheck" -and ($BoundParams.AuthenticationType) -eq "Browser" -and $Return -is [System.Xml.XmlDocument]) {
                            $NamespaceManager = New-Object System.Xml.XmlNamespaceManager($Return.NameTable)
                            $NamespaceManager.AddNamespace("xhtml", "http://www.w3.org/1999/xhtml")
                            if ($Return.SelectSingleNode('//xhtml:html/xhtml:head/xhtml:title', $NamespaceManager).'#text' -like "401 *") {
                                throw $CustomErrorTrigger
                            }
                        }
                        $Script:LoginCount++
                        return $Return
                    }
                    "Invoke-WebRequest" {
                        $Parameters = Set-RequestParameter
                        $Return = (Invoke-WebRequest @Parameters)

                        #To support -SkipHttpErrorCheck
                        if ($BoundParams.Keys -contains "SkipHttpErrorCheck" -and ($BoundParams.AuthenticationType) -eq "Browser" -and $Return -is [Microsoft.PowerShell.Commands.WebResponseObject] -and $Return.StatusCode -eq 401) {
                            throw $CustomErrorTrigger
                        }
                        $Script:LoginCount++
                        return $Return
                    }
                    default {
                        #Ignored
                    }
                }
            }

            catch {

                if (($BoundParams.AuthenticationType) -eq "Browser" -and ($_.Exception.Response.StatusCode -eq 401 -or $_.Exception.Message -eq $CustomErrorTrigger)) {

                    if ($Script:LoginCount -le 1) {
                        "Authentication needed!" | Write-Host
                    }
                    else {
                        "Re-authentication failed!" | Write-Host
                    }
                    "{0} - Re-Authentication - Error message: {1}" -f $MyInvocation.MyCommand, $_.Exception.Message | Write-Verbose
                    $UseWebView2 = $false
                    if ($BoundParams.ContainsKey('UseWebView2') -and $BoundParams.UseWebView2) {
                        $UseWebView2 = $true
                    }
                    elseif ($Script:PreferWebView2 -eq $true) {
                        $UseWebView2 = $true
                    }
                    if ($UseWebView2) {
                        "{0} - Using WebView2 for authentication" -f $MyInvocation.MyCommand | Write-Verbose
                        Invoke-DataFromWebView2 -EdgeProfile $BoundParams.EdgeProfile -InPrivate:$($BoundParams.InPrivate).IsPresent
                        $BrowserData = @($Script:OmadaWebAuthCookie, $Script:UserAgent)
                    }
                    else {
                        $BrowserData = Invoke-DataFromWebDriver -EdgeProfile $BoundParams.EdgeProfile -InPrivate:$($BoundParams.InPrivate).IsPresent
                    }
                    $Script:OmadaWebAuthCookie = $BrowserData[0]
                    $BoundParams.UserAgent = $BrowserData[1]

                    try {
                        $Parameters = Set-RequestParameter -InvokeOmadaRequest
                        return (Invoke-OmadaRequest @Parameters)
                    }
                    catch {
                        throw
                    }
                }
                else {
                    throw
                }
            }
        }
        catch {
            throw
        }
    }
}