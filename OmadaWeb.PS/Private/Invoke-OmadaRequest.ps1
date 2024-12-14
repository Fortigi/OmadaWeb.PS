function Invoke-OmadaRequest {
    [CmdletBinding(DefaultParameterSetName = "StandardMethod")]
    PARAM()

    DynamicParam {
        return Set-OmadaRequestParameter -FunctionName $Script:FunctionName
    }
    process {
        try {

            "{0} called for {1} by {2}" -f $MyInvocation.MyCommand, $Script:FunctionName, (Get-PSCallStack)[1].Command | Write-Verbose

            $BoundParams = $PsCmdLet.MyInvocation.BoundParameters

            $ExcludedRestMethodParameters = @("AuthenticationType", "AzureAdTenantId", "Credential", "RequestType", "EdgeProfile")
            $ExcludedParameters = @("OmadaWebAuthCookieExportLocation", "InPrivate", "ForceAuthentication", "EdgeProfile")

            $DefaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0"

            $null = $BoundParams.Uri -match [regex]'^(?:https?:\/\/)?(?:[^@\/\n]+@)?(?:www\.)?([^:\/\n]+)'
            if ($null -ne $Matches) {
                $Script:OmadaWebBaseUrl = $Matches[0]
            }
            else {
                "Could not determine the base URL from '{0}', is the URL correct?" -f $BoundParams.Uri | Write-Error -ErrorAction "Stop"
            }

            if ("UserAgent" -notin $BoundParams.Keys) {
                $BoundParams.Add("UserAgent", $DefaultUserAgent)
            }

            $Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
            $Session.UserAgent = $DefaultUserAgent

            if ("Headers" -notin $BoundParams.Keys) {
                $BoundParams.Add("Headers", @{})
                $BoundParams.Headers.Add("Accept", "application/json")
            }
            elseif ("Accept" -notin $BoundParams.Headers.Keys) {
                $BoundParams.Headers.Add("Accept", "application/json")
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
            $BoundParams.Add("UseBasicParsing", $true)

            "{0} - {1}" -f $MyInvocation.MyCommand, ($BoundParams | ConvertTo-Json) | Write-Verbose
            try {
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

                    $Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                    $Session.UserAgent = $BoundParams.UserAgent
                    $Session.Cookies.Add((New-Object System.Net.Cookie("oisauthtoken", $($Script:OmadaWebAuthCookie.Value), "/", $($Script:OmadaWebAuthCookie.domain))))
                    if ("Cookie" -notin $BoundParams.Headers.Keys) {
                        $BoundParams.Headers.Add("Cookie", ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "="))
                    }
                    else {
                        $BoundParams.Headers.Cookie = ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "=")
                    }

                    if ("WebSession" -notin $BoundParams.Keys) { $BoundParams.Add("WebSession", $Session) }else { $BoundParams.WebSession = $Session }
                    if ("Headers" -notin $BoundParams.Keys) { $BoundParams.Add("Headers", $BoundParams.Headers) }else { $BoundParams.Headers = $BoundParams.Headers }
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