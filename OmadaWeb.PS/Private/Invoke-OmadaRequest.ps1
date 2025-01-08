function Invoke-OmadaRequest {
    [CmdletBinding(DefaultParameterSetName = "StandardMethod")]
    PARAM()

    DynamicParam {
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

            # UseBasicParsing is deprecated since PowerShell Core 6, there it is only set when using PowerShell 5 (https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest?view=powershell-7.4#-usebasicparsing)
            if ($PSVersionTable.PSVersion.Major -lt 6) {
                $Arguments.Add("UseBasicParsing", $true)
            }

            "{0} - {1}" -f $MyInvocation.MyCommand, ($BoundParams | ConvertTo-Json) | Write-Verbose
            try {
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
                        return (Invoke-RestMethod @Parameters)
                    }
                    "Invoke-WebRequest" {
                        $Parameters = Set-RequestParameter
                        return (Invoke-WebRequest @Parameters)
                    }
                    default {
                        #Ignored
                    }
                }
            }

            catch {
                if (($BoundParams.AuthenticationType) -eq "Browser" -and $_.Exception.Response.StatusCode -eq 401) {

                    "Re-authentication needed!" | Write-Host
                    "{0} - Re-Authentication - Error message:" -f $MyInvocation.MyCommand, ($_ | ConvertTo-Json) | Write-Verbose
                    $EdgeDriverData = Invoke-DataFromWebDriver -EdgeProfile $BoundParams.EdgeProfile -InPrivate:$($BoundParams.InPrivate).IsPresent
                    $Script:OmadaWebAuthCookie = $EdgeDriverData[0]
                    $BoundParams.UserAgent = $EdgeDriverData[1]

                    try {
                        $Parameters = Set-RequestParameter
                        return (Invoke-OmadaRequest @Parameters)
                    }
                    catch {
                        Throw $_
                    }
                }
                else {
                    Throw $_
                }
            }
        }
        catch {
            Throw $_
        }
    }
}