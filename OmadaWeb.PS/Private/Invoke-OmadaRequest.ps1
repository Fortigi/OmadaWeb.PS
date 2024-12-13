function Invoke-OmadaRequest {
    [CmdletBinding(DefaultParameterSetName = "StandardMethod")]
    PARAM()

    DynamicParam {
        $FunctionName = $Script:FunctionName
        $FunctionObject = Get-Command -Name $FunctionName
        return Set-OmadaRequestParameter -Function $FunctionObject
    }
    process {
        try {

            "{0}" -f $MyInvocation.MyCommand | Write-Verbose

            #TODO: See if this is still needed
            #if (!(Get-Variable -Scope Global | Where-Object { $_.Name -eq $Script:SessionId })) {
            #    New-Variable -Name $Script:SessionId -Value $null
            #}
            $ExcludedRestMethodParameters = @("AuthenticationType", "AzureAdTenantId", "Credential", "RequestType", "EdgeProfile")
            $ExcludedParameters = @("OmadaWebAuthCookieExportLocation", "InPrivate", "ForceAuthentication", "EdgeProfile")

            $DefaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0"
            $BoundParams = $PsCmdLet.MyInvocation.BoundParameters

            if ("UserAgent" -notin $BoundParams.Keys) {
                $BoundParams.Add("UserAgent", $DefaultUserAgent)
            }

            $Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
            $Session.UserAgent = $DefaultUserAgent

            $Headers = @{}
            $Headers.Add("Accept", "application/json")
            $null = $BoundParams.Uri -match [regex]'^(?:https?:\/\/)?(?:[^@\/\n]+@)?(?:www\.)?([^:\/\n]+)'
            if ($null -ne $Matches) {
                $Script:OmadaWebBaseUrl = $Matches[0]
            }
            else {
                "Could not determine the base URL from '{0}', is the URL correct?" | Write-Error -ErrorAction "Stop"
            }

            if ("AuthenticationType" -notin $BoundParams.Keys) {
                $BoundParams.Add("AuthenticationType", "Browser")
            }

            if ($BoundParams.Keys -contains "OmadaWebAuthCookieFile") {
                $Script:OmadaWebAuthCookie = (Import-Clixml $BoundParams.OmadaWebAuthCookieFile).OmadaWebAuthCookie
            }
            if ("OmadaWebAuthCookieFile" -in $BoundParams.Keys) {
                $BoundParams.Remove("OmadaWebAuthCookieFile") | Out-Null
            }

            "{0} - Authentication type: {1}" -f $MyInvocation.MyCommand, $($BoundParams.AuthenticationType) | Write-Verbose

            switch ($BoundParams.AuthenticationType) {
                "Windows" {
                    "{0} - {1} Authentication " -f $MyInvocation.MyCommand, $_ | Write-Verbose
                    if($BoundParams.keys -notcontains "Credential"){
                        $BoundParams.Add("Credential", (Get-Credential -Message "Please enter your Windows credentials"))
                    }
                }
                "Browser" {
                    "{0} - {1} Authentication " -f $MyInvocation.MyCommand, $_ | Write-Verbose
                    if ($BoundParams.ForceAuthentication) {
                        $Script:OmadaWebAuthCookie = $null
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
                        "{0} - {1} - OmadaWebAuthCookie exists for this domain" -f $MyInvocation.MyCommand, $_ | Write-Verbose
                        if ("Cookie" -notin $Headers.Keys) {
                            $Headers.Add("Cookie", ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "="))
                        }
                        else {
                            $Headers.Cookie = ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "=")
                        }
                        $Session.Cookies.Add((New-Object System.Net.Cookie("oisauthtoken", $($Script:OmadaWebAuthCookie.Value), "/", $($Script:OmadaWebAuthCookie.domain))))
                    }
                    else {
                        "{0} - {1} - OmadaWebAuthCookie not exists or for different domain" -f $MyInvocation.MyCommand, $_ | Write-Verbose
                        $EdgeDriverData = Invoke-DataFromWebDriver -EdgeProfile $BoundParams.EdgeProfile -InPrivate:$($BoundParams.InPrivate).IsPresent
                        $Script:OmadaWebAuthCookie = $EdgeDriverData[0]

                        $BoundParams.UserAgent = $EdgeDriverData[1]

                        $Session.UserAgent = $EdgeDriverData[1]
                        if ("Cookie" -notin $Headers.Keys) {
                            $Headers.Add("Cookie", ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "="))
                        }
                        else {
                            $Headers.Cookie = ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "=")
                        }

                        $Session.Cookies.Add((New-Object System.Net.Cookie("oisauthtoken", $($Script:OmadaWebAuthCookie.Value), "/", $($Script:OmadaWebAuthCookie.domain))))
                    }
                    if (![string]::IsNullOrEmpty($($BoundParams.OmadaWebAuthCookieExportLocation))) {
                        "Exporting cookie to {0}" -f $($BoundParams.OmadaWebAuthCookieExportLocation) | Write-Verbose
                        $CookieObject = [PSCustomObject]@{
                            OmadaWebAuthCookie = $Script:OmadaWebAuthCookie
                        }
                        $CookieObject | Export-Clixml (Join-Path $($BoundParams.OmadaWebAuthCookieExportLocation) -ChildPath ("{0}.cookie" -f $Script:OmadaWebAuthCookie.domain)) -Force
                    }
                }
                "OAuth" {
                    "{0} - {1} Authentication, Request bearer token" -f $MyInvocation.MyCommand, $_ | Write-Verbose
                    if ($null -eq $BoundParams.Credential) {
                        "{0} - Credentials not provided! This mandatory for OAuth authentication!" -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
                    }
                    if ($null -eq $BoundParams.AzureAdTenantId) {
                        "{0} - AzureAdTenantId not provided! This mandatory for OAuth authentication!" -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
                    }

                    $RequestBody = @{
                        scope         = ("{0}/.default" -f $Script:OmadaWebBaseUrl)
                        client_id     = $($BoundParams.Credential.UserName)
                        grant_type    = 'client_credentials'
                        client_secret = $($BoundParams.Credential.GetNetworkCredential().Password)
                    }

                    $BearerToken = Invoke-RestMethod -Uri ("https://login.microsoftonline.com/{0}/oauth2/v2.0/token" -f $BoundParams.AzureAdTenantId) -UseBasicParsing -Method Post -Body $RequestBody -ContentType 'application/x-www-form-urlencoded'
                    $BearerToken = $BearerToken
                    $Headers.Add("Authorization" , "Bearer {0}" -f $BearerToken.access_token)
                }
                "Integrated" {
                    "{0} - {1} Authentication " -f $MyInvocation.MyCommand, $_ | Write-Verbose
                    $BoundParams.Add("UseDefaultCredentials", $true)
                }
                "Basic" {
                    "{0} - {1} Authentication " -f $MyInvocation.MyCommand, $_ | Write-Verbose
                    if($BoundParams.keys -notcontains "Credential"){
                        $BoundParams.Add("Credential", (Get-Credential -Message "Please enter your authentication credentials"))
                    }
                    $BoundParams.CredentialPair = "{0}:{1}" -f $BoundParams.Credential.UserName, $BoundParams.Credential.GetNetworkCredential().Password
                    $EncodedCredential = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($BoundParams.CredentialPair))
                    $Headers.Add("Authorization" , ("Basic {0}" -f $EncodedCredential))
                }
                default {
                    "{0} - {1} not supported!" -f $MyInvocation.MyCommand, $_ | Write-Error -ErrorAction "Stop"
                }
            }

            if ($BoundParams.Method -in @('PUT', 'POST', 'PATCH')) {
                "{0} - {1} - Add Body" -f $MyInvocation.MyCommand, $BoundParams.Method | Write-Verbose
                if ($null -eq $BoundParams.Body) {
                    "{0} - Provided -Body is empty this is mandatory for a {1} command" -f $MyInvocation.MyCommand , $BoundParams.Method | Write-Error -ErrorAction "Stop"
                }
                $Headers.Add("Content-Type", "application/json")
                if ($BoundParams.Body -is [hashtable]) {
                    $BoundParams.Body = $BoundParams.Body | ConvertTo-Json
                }
                if ($BoundParams.Body -isnot [hashtable] -and $BoundParams.Body -isnot [string]) {
                    "{0} - Content parameter should be a hashtable to string!" -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
                }
                $BoundParams.Body = $BoundParams.Body
                "{0} - {1}" -f $MyInvocation.MyCommand, ($BoundParams | ConvertTo-Json) | Write-Verbose
            }
            "{0} - {1}" -f $MyInvocation.MyCommand, ($BoundParams | ConvertTo-Json) | Write-Verbose

            "{0} (Line {1}): {2}" -f $MyInvocation.MyCommand, $MyInvocation.ScriptLineNumber, $$ | Write-Verbose

            try {
                if ("WebSession" -notin $BoundParams.Keys) { $BoundParams.Add("WebSession", $Session) }else { $BoundParams.WebSession = $Session }
                if ("Headers" -notin $BoundParams.Keys) { $BoundParams.Add("Headers", $Headers) }else { $BoundParams.Headers = $Headers }
                if ("UseBasicParsing" -notin $BoundParams.Keys) { $BoundParams.Add("UseBasicParsing", $true) }else { $BoundParams.UseBasicParsing = $true }

                $Parameters = @{}
                $BoundParams.Keys | ForEach-Object {
                    if ($_ -notin $ExcludedRestMethodParameters -and $_ -notin $ExcludedParameters) {
                        $Parameters.Add($_, $BoundParams[$_])
                    }
                }

                "Parameters" | Write-Verbose
                $Parameters | ConvertTo-Json | Write-Verbose

                return (Invoke-RestMethod @Parameters)
            }

            catch {
                if (($BoundParams.AuthenticationType) -eq "Browser" -and $_.Exception.Response.StatusCode -eq 401) {

                    "Re-authentication needed!" | Write-Host
                    "{0} - Re-Authentication - Error message:" -f $MyInvocation.MyCommand, ($_ | ConvertTo-Json) | Write-Verbose
                    $EdgeDriverData = Invoke-DataFromWebDriver -EdgeProfile $BoundParams.EdgeProfile -InPrivate:$($BoundParams.InPrivate).IsPresent
                    $Script:OmadaWebAuthCookie = $EdgeDriverData[0]
                    $BoundParams.UserAgent = $EdgeDriverData[1]
                    $Session.UserAgent = $EdgeDriverData[1]

                    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                    $Session.UserAgent = $BoundParams.UserAgent
                    $session.Cookies.Add((New-Object System.Net.Cookie("oisauthtoken", $($Script:OmadaWebAuthCookie.Value), "/", $($Script:OmadaWebAuthCookie.domain))))
                    if ("Cookie" -notin $Headers.Keys) {
                        $Headers.Add("Cookie", ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "="))
                    }
                    else {
                        $Headers.Cookie = ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "=")
                    }

                    if ("WebSession" -notin $BoundParams.Keys) { $BoundParams.Add("WebSession", $Session) }else { $BoundParams.WebSession = $Session }
                    if ("Headers" -notin $BoundParams.Keys) { $BoundParams.Add("Headers", $Headers) }else { $BoundParams.Headers = $Headers }
                    if ("UseBasicParsing" -notin $BoundParams.Keys) { $BoundParams.Add("UseBasicParsing", $true) }else { $BoundParams.UseBasicParsing = $true }

                    $Parameters = @{}
                    $BoundParams.Keys | ForEach-Object {
                        if ($_ -notin $ExcludedRestMethodParameters) {
                            $Parameters.Add($_, $BoundParams[$_])
                        }
                    }
                    "Parameters" | Write-Verbose
                    $Parameters | ConvertTo-Json | Write-Verbose
                    try {
                        return (Invoke-RestMethod @Parameters)
                    }
                    catch {
                        Throw $_
                    }
                }
                else {
                    throw $_
                }
            }
        }
        catch {
            Throw $_
        }
    }
}