function Invoke-OmadaRequest {
    PARAM(
        [parameter(Mandatory = $true)]
        [validateSet("Rest", "Web")]
        $RequestType,

        [Microsoft.PowerShell.Commands.WebRequestMethod]
        ${Method},
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [uri]
        ${Uri},

        #[Microsoft.PowerShell.Commands.WebRequestSession]
        #${WebSession},
        #
        #[Alias('SV')]
        #[string]
        #${SessionVariable},

        [pscredential]
        [System.Management.Automation.CredentialAttribute()]
        ${Credential},

        [parameter(Mandatory = $true)]
        [validateSet("OAuth", "Integrated", "Basic", "Browser", "Windows")]
        $AuthenticationType,

        [parameter(Mandatory = $false)]
        $AzureAdTenantId,

        #[switch]
        #${UseDefaultCredentials},

        [ValidateNotNullOrEmpty()]
        [string]
        ${CertificateThumbprint},

        [ValidateNotNull()]
        [X509Certificate]
        ${Certificate},

        [string]
        ${UserAgent},

        [switch]
        ${DisableKeepAlive},

        [ValidateRange(0, 2147483647)]
        [int]
        ${TimeoutSec},

        #[System.Collections.IDictionary]
        #${Headers},

        [ValidateRange(0, 2147483647)]
        [int]
        ${MaximumRedirection},

        [uri]
        ${Proxy},

        [pscredential]
        [System.Management.Automation.CredentialAttribute()]
        ${ProxyCredential},

        [switch]
        ${ProxyUseDefaultCredentials},

        [Parameter(ValueFromPipeline = $true)]
        [System.Object]
        ${Body},

        [string]
        ${ContentType},

        [ValidateSet('chunked', 'compress', 'deflate', 'gzip', 'identity')]
        [string]
        ${TransferEncoding},

        [string]
        ${InFile},

        [string]
        ${OutFile},

        [switch]
        ${UseBasicParsing},

        [switch]
        ${PassThru},

        [string]
        #[validateScript({ if ($null -ne $_ -and ![string]::IsNullOrEmpty($_) -and !(Test-Path $_ -PathType Container)) { "Cannot find path {0} for optional parameter OmadaWebAuthCookieExportLocation!" -f $_ | Write-Error -ErrorAction Stop } })]
        ${OmadaWebAuthCookieExportLocation}
    )

    try {

        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        #TODO: See if this is still needed
        #if (!(Get-Variable -Scope Global | Where-Object { $_.Name -eq $Script:SessionId })) {
        #    New-Variable -Name $Script:SessionId -Value $null
        #}

        $ExcludedRestMethodParameters = @("AuthenticationType", "AzureAdTenantId", "Credential", "RequestType")
        $ExcludedParameters = @("OmadaWebAuthCookieExportLocation")

        $DefaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.36"
        if ("UserAgent" -notin $PSBoundParameters.Keys) {
            $PSBoundParameters.Add("UserAgent", $DefaultUserAgent)
        }

        $Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $Session.UserAgent = $DefaultUserAgent

        $Headers = @{}
        $Headers.Add("Accept", "application/json")

        $null = $Uri -match [regex]'^(?:https?:\/\/)?(?:[^@\/\n]+@)?(?:www\.)?([^:\/\n]+)'
        if ($null -ne $Matches) {
            $Script:OmadaWebBaseUrl = $Matches[0]
        }
        else {
            "Could not determine the base URL from '{0}', is the URL correct?" | Write-Error -ErrorAction "Stop"
        }

        "{0} - Authentication type: {1}" -f $MyInvocation.MyCommand, $AuthenticationType | Write-Verbose

        switch ($AuthenticationType) {
            "Windows" {
                "{0} - {1} Authentication " -f $MyInvocation.MyCommand, $_ | Write-Verbose
                $PSBoundParameters.Credential = $Credential
            }
            "Browser" {
                "{0} - {1} Authentication " -f $MyInvocation.MyCommand, $_ | Write-Verbose

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
                    $EdgeDriverData = Invoke-DataFromWebDriver
                    $Script:OmadaWebAuthCookie = $EdgeDriverData[0]

                    $PSBoundParameters.UserAgent = $EdgeDriverData[1]

                    $Session.UserAgent = $EdgeDriverData[1]
                    if ("Cookie" -notin $Headers.Keys) {
                        $Headers.Add("Cookie", ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "="))
                    }
                    else {
                        $Headers.Cookie = ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "=")
                    }

                    $Session.Cookies.Add((New-Object System.Net.Cookie("oisauthtoken", $($Script:OmadaWebAuthCookie.Value), "/", $($Script:OmadaWebAuthCookie.domain))))
                }
                if (![string]::IsNullOrEmpty($OmadaWebAuthCookieExportLocation)) {
                    "Exporting cookie to {0}" -f $OmadaWebAuthCookieExportLocation | Write-Verbose
                    $Script:OmadaWebAuthCookie | Export-CliXml (Join-Path $OmadaWebAuthCookieExportLocation -ChildPath ("{0}.cookie" -f $Script:OmadaWebAuthCookie.domain)) -Force
                }
            }
            "OAuth" {
                "{0} - {1} Authentication, Request bearer token" -f $MyInvocation.MyCommand, $_ | Write-Verbose
                if ($null -eq $Credential) {
                    "{0} - Credentials not provided! This mandatory for OAuth authentication!" -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
                }
                if ($null -eq $AzureAdTenantId) {
                    "{0} - AzureAdTenantId not provided! This mandatory for OAuth authentication!" -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
                }

                $RequestBody = @{
                    scope         = ("{0}/.default" -f $Script:OmadaWebBaseUrl)
                    client_id     = $($Credential.UserName)
                    grant_type    = 'client_credentials'
                    client_secret = $($Credential.GetNetworkCredential().Password)
                }

                $BearerToken = Invoke-RestMethod -Uri ("https://login.microsoftonline.com/{0}/oauth2/v2.0/token" -f $AzureAdTenantId) -UseBasicParsing -Method Post -Body $RequestBody -ContentType 'application/x-www-form-urlencoded'
                $BearerToken = $BearerToken
                $Headers.Add("Authorization" , "Bearer {0}" -f $BearerToken.access_token)
            }
            "Integrated" {
                "{0} - {1} Authentication " -f $MyInvocation.MyCommand, $_ | Write-Verbose
                $PsBoundParameters.Add("UseDefaultCredentials", $true)
            }
            "Basic" {
                "{0} - {1} Authentication " -f $MyInvocation.MyCommand, $_ | Write-Verbose
                $CredentialPair = "{0}:{1}" -f $Credential.UserName, $Credential.GetNetworkCredential().Password
                $EncodedCredential = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($CredentialPair))
                $Headers.Add("Authorization" , ("Basic {0}" -f $EncodedCredential))
            }
            default {
                "{0} - {1} not supported!" -f $MyInvocation.MyCommand, $_ | Write-Error -ErrorAction "Stop"
            }
        }

        if ($Method -in @('PUT', 'POST', 'PATCH')) {
            "{0} - {1} - Add Body" -f $MyInvocation.MyCommand, $Method | Write-Verbose
            if ($null -eq $Body) {
                "{0} - Provided -Body is empty this is mandatory for a {1} command" -f $MyInvocation.MyCommand , $Method | Write-Error -ErrorAction "Stop"
            }
            $Headers.Add("Content-Type", "application/json")
            if ($Body -is [hashtable]) {
                $Body = $Body | ConvertTo-Json
            }
            if ($Body -isnot [hashtable] -and $Body -isnot [string]) {
                "{0} - Content parameter should be a hashtable to string!" -f $MyInvocation.MyCommand | Write-Error -ErrorAction "Stop"
            }
            $PSBoundParameters.Body = $Body
            "{0} - {1}" -f $MyInvocation.MyCommand, ($PsBoundParameters | ConvertTo-Json) | Write-Verbose
        }
        "{0} - {1}" -f $MyInvocation.MyCommand, ($PsBoundParameters | ConvertTo-Json) | Write-Verbose

        "{0} (Line {1}): {2}" -f $MyInvocation.MyCommand, $MyInvocation.ScriptLineNumber, $$ | Write-Verbose

        try {
            if ("WebSession" -notin $PSBoundParameters.Keys) { $PSBoundParameters.Add("WebSession", $Session) }else { $PSBoundParameters.WebSession = $Session }
            if ("Headers" -notin $PSBoundParameters.Keys) { $PSBoundParameters.Add("Headers", $Headers) }else { $PSBoundParameters.Headers = $Headers }
            if ("UseBasicParsing" -notin $PSBoundParameters.Keys) { $PSBoundParameters.Add("UseBasicParsing", $true) }else { $PSBoundParameters.UseBasicParsing = $true }

            $Parameters = @{}
            $PSBoundParameters.Keys | ForEach-Object {
                if ($_ -notin $ExcludedRestMethodParameters -and $_ -notin $ExcludedParameters) {
                    $Parameters.Add($_, $PSBoundParameters[$_])
                }
            }

            "Parameters" | Write-Verbose
            $Parameters | ConvertTo-Json | Write-Verbose

            switch ($RequestType) {
                "Rest" {
                    return (Invoke-RestMethod @Parameters)
                }
                "Web" {
                    return (Invoke-WebRequest @Parameters)
                }
                default {
                    #Ignored
                }
            }
        }

        catch {
            if ($AuthenticationType -eq "Browser" -and $_.Exception.Response.StatusCode -eq 401) {

                "Re-authentication needed!" | Write-Host
                "{0} - Re-Authentication - Error message:" -f $MyInvocation.MyCommand, ($_ | ConvertTo-Json) | Write-Verbose
                $EdgeDriverData = Invoke-DataFromWebDriver
                $Script:OmadaWebAuthCookie = $EdgeDriverData[0]
                $PsBoundParameters.UserAgent = $EdgeDriverData[1]
                $Session.UserAgent = $EdgeDriverData[1]

                $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                $Session.UserAgent = $PsBoundParameters.UserAgent
                $session.Cookies.Add((New-Object System.Net.Cookie("oisauthtoken", $($Script:OmadaWebAuthCookie.Value), "/", $($Script:OmadaWebAuthCookie.domain))))
                if ("Cookie" -notin $Headers.Keys) {
                    $Headers.Add("Cookie", ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "="))
                }
                else {
                    $Headers.Cookie = ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "=")
                }

                if ("WebSession" -notin $PSBoundParameters.Keys) { $PSBoundParameters.Add("WebSession", $Session) }else { $PSBoundParameters.WebSession = $Session }
                if ("Headers" -notin $PSBoundParameters.Keys) { $PSBoundParameters.Add("Headers", $Headers) }else { $PSBoundParameters.Headers = $Headers }
                if ("UseBasicParsing" -notin $PSBoundParameters.Keys) { $PSBoundParameters.Add("UseBasicParsing", $true) }else { $PSBoundParameters.UseBasicParsing = $true }

                $Parameters = @{}
                $PSBoundParameters.Keys | ForEach-Object {
                    if ($_ -notin $ExcludedRestMethodParameters) {
                        $Parameters.Add($_, $PSBoundParameters[$_])
                    }
                }
                "Parameters" | Write-Verbose
                $Parameters | ConvertTo-Json | Write-Verbose
                try {

                    switch ($RequestType) {
                        "Rest" {
                            return (Invoke-RestMethod @Parameters)
                        }
                        "Web" {
                            return (Invoke-WebRequest @Parameters)
                        }
                        default {
                            #Ignored
                        }
                    }
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