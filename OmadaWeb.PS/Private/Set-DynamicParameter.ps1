function Set-DynamicParameter {
    [CmdletBinding()]
    param(
        $FunctionName
    )
    $Dictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
    $FunctionObject = Get-Command -Name $FunctionName

    #https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_commonparameters?view=powershell-7.4
    $ExcludedParameters = @("Debug",
        "ErrorAction",
        "ErrorVariable",
        "InformationAction",
        "InformationVariable",
        "OutVariable",
        "OutBuffer",
        "PipelineVariable",
        "ProgressAction",
        "Verbose",
        "WarningAction",
        "WarningVariable",
        "Session",
        "WebSession",
        "Authentication",
        "SessionVariable",
        "UseDefaultCredentials",
        "UseBasicParsing",
        # PowerShell 7's Invoke-RestMethod/Invoke-WebRequest declare these two themselves, Windows
        # PowerShell 5.1's do not. Inheriting them would mean the module offers a different retry
        # surface - and different retry semantics - depending on which engine it runs on, and on 7
        # it would also retry twice: once in the native cmdlet and once in the module's own policy.
        # They are dropped here and re-declared below so both engines get one identical parameter
        # with one implementation behind it, which honours Retry-After and applies jitter.
        "MaximumRetryCount",
        "RetryIntervalSec"
    )

    $ParameterObjects = @()
    foreach ($ParameterSet in $FunctionObject.ParameterSets) {
        foreach ($Parameter in $ParameterSet.Parameters) {
            if ($Parameter.Name -notin $ExcludedParameters) {
                if ($Parameter.Name -notin $ParameterObjects.Name) {
                    $ParameterSetName = @($($ParameterSet.Name))
                    $ParameterObjects += @{
                        Name                            = $Parameter.Name
                        Type                            = $Parameter.ParameterType
                        Alias                           = $Parameter.Aliases
                        ValidateSet                     = $Parameter.ValidateSet
                        Mandatory                       = $Parameter.IsMandatory
                        ParameterSetName                = $ParameterSetName
                        Position                        = $Parameter.Position
                        ValueFromPipelineByPropertyName = $Parameter.ValueFromPipelineByPropertyName
                        HelpMessage                     = $Parameter.HelpMessage
                        DPDictionary                    = $Dictionary
                    }
                }
                else {
                    ($ParameterObjects | Where-Object { $_.Name -eq $Parameter.Name }).ParameterSetName += $($ParameterSet.Name)
                }
            }
        }
    }

    [string[]]$ParameterObjectSetNames = $null
    if (($ParameterObjects.ParameterSetName | Select-Object -Unique | Measure-Object).Count -eq 1 -and [string]::IsNullOrWhiteSpace($ParameterObjects.ParameterSetName)) {
        $ParameterObjectSetNames += "__AllParameterSets"
        $ParameterObjects | ForEach-Object { $_.ParameterSetName = "__AllParameterSets" }
    }
    else {
        $ParameterObjectSetNames += $ParameterObjects.ParameterSetName | Select-Object -Unique
    }

    foreach ($ParameterObject in $ParameterObjects) {
        New-DynamicParam @ParameterObject
    }

    New-DynamicParam -Name "AuthenticationType" -Type "string" -ValidateSet ("OAuth", "Integrated", "Basic", "Browser", "WebView2", "Windows", "None") -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -Value "WebView2" -HelpMessage 'The type of authentication to use for the request. Default is ''WebView2''. The acceptable values for this parameter are:
- ''None'': No explicit authentication is used.
- ''Basic'': Requires Credential. The credentials are sent as an RFC 7617 Basic Authentication ''Authorization: basic'' header in the format of ''base64(user:password)''.
- ''Browser'': Browser-based interactive sign-in. Today this runs on Selenium, which automatically installs and updates to the desired webdriver version based on the currently installed Microsoft Edge browser. The Selenium engine is deprecated and supported until 1 March 2027; in the first release published after that date, ''Browser'' runs on WebView2 instead. ''Browser'' itself is not going away, so no script change is needed at any point - do not migrate to ''WebView2'' to get ahead of this, because that value is deprecated as well. See https://github.com/Fortigi/OmadaWeb.PS/issues/50.
- ''Integrated'': Uses Windows Integrated Authentication.
- ''OAuth'': Requires Credential. OAuth2 authentication with Entra ID by default, other IDPs are possible using additional OAuth parameters.
- ''WebView2'': For environments where Selenium is restricted, you can use the Microsoft WebView2 NuGet package instead. WebView2 does not use the developer tools of the Edge browser and should work when developer options is not allowed. The WebView2 assemblies ship with the module, so no download is needed; a module installed without them falls back to downloading them into %LOCALAPPDATA%\OmadaWeb.PS\Bin on first use. WebView2 uses a dedicated Edge user profile per session (base URL, authentication type and, when known, user), located under %LOCALAPPDATA%\OmadaWeb.PS\Edge User Data.
- ''Windows'': Requires Credential. Uses Windows authentication with the supplied credentials. The credential is passed to the underlying web request, which automatically negotiates using Kerberos/NTLM (''Negotiate'') when the server issues a challenge.

Supplying AuthenticationType overrides any Authorization headers supplied to Headers or included in WebSession.'
    New-DynamicParam -Name "EntraIdTenantId" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "The tenant id or name for -AuthenticationType OAuth." -Alias "AzureAdTenantId"
    New-DynamicParam -Name "EntraApplicationIdUri" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Enter the application ID URI when the base url does not equal the configured application ID URI in Entra ID. This parameter is used for -AuthenticationType OAuth."
    New-DynamicParam -Name "OAuthScope" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "OAuth2 scope to be used. Defaults to the form used for Entra ID. This parameter is used for -AuthenticationType OAuth."
    New-DynamicParam -Name "OAuthUri" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Provide a custom OAuth2 URI. Defaults to the form used for Entra ID based on the provided EntraIdTenantId. This parameter is used for -AuthenticationType OAuth."
    New-DynamicParam -Name "CookiePath" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Attempts to load a stored Omada authentication cookie from this path. This file will be updated when re-authentication is needed. If the file does not exist, it will be created after successful authentication. When this option is used, an encrypted cookie is not cached.

IMPORTANT: Be aware that an unencrypted version of the session cookie is stored on the file system. This parameter only applies in combination with parameter -AuthenticationType Browser and -AuthenticationType WebView2. Make sure it is stored at a secure location so it cannot be accessed by unauthorized users."
    New-DynamicParam -Name "SkipCookieCache" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Do not cache the encrypted Omada authentication cookie. It will also not be cached when -CookiePath is used. This parameter only applies in combination with parameter -AuthenticationType Browser and -AuthenticationType WebView2."
    New-DynamicParam -Name "ForceAuthentication" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Force authentication to Omada even when the cookie is still valid."
    New-DynamicParam -Name "EdgeProfile" -Type "string" -ValidateSet $Script:EdgeProfiles.Name -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Use the specified Edge profile for the authentication request. The acceptable values for this parameter are based on the available profiles on your system.

IMPORTANT: Due to the requirements of Selenium, the selected Edge profile needs to be closed when using this parameter."
    New-DynamicParam -Name "InPrivate" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Use InPrivate mode for the authentication request."
    New-DynamicParam -Name "UseWebView2" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Use WebView2 instead of Selenium WebDriver for browser-based authentication.

IMPORTANT: This parameter is deprecated and obsolete. The default is AuthenticationType WebView2, so this parameter is not needed anymore and will be removed in a future release."
    New-DynamicParam -Name "DebugWebView2" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Use this parameter to enable WebView2 browser debugging options like Developer Tools"
    New-DynamicParam -Name "SessionKey" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Explicitly discriminate the reusable authentication session (cookie, base URL, WebView2/Selenium profile) to use for this call, in addition to the base URL, -AuthenticationType and -Credential (when supplied). Use this to keep multiple concurrent sessions apart when they would otherwise share the same base URL, authentication type and credential - for example two interactive Browser/WebView2 logins to the same tenant before either has a known user identity. Has no effect on which cookie/base URL etc. is used beyond distinguishing sessions from each other; defaults to an empty value, which reproduces prior single-session-per-(base URL, AuthenticationType, Credential) behavior."

    New-DynamicParam -Name "MaximumRetryCount" -Type ([int]) -Alias "MaxRetryCount" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -Value 3 -HelpMessage "How many times a failed request is retried before the error is raised. Defaults to 3, so a request is attempted 4 times in total. Use -MaximumRetryCount 0 to switch retrying off.

Only requests that can be repeated safely are retried: HTTP GET and HEAD, including the page requests -Paged makes. A POST, PUT, PATCH or DELETE may already have been applied by the server, so it is never repeated automatically. Retries are triggered by the transient conditions a multi-tenant cloud produces - HTTP 429, 502, 503 and 504, and socket-level network failures - and never by an authentication failure, which is handled by re-authenticating instead. A client-side timeout is not retried either, so -TimeoutSec keeps bounding the call.

Between attempts the command waits -RetryIntervalSec, doubling that wait after each attempt and varying it slightly so that several clients backing off at once do not retry in lockstep. When the server answers with a Retry-After header, the delay it asks for is used instead. Every retry is reported on the verbose stream with the status code and the delay."
    New-DynamicParam -Name "RetryIntervalSec" -Type ([int]) -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -Value 2 -HelpMessage "The wait in seconds before the first retry, doubled for each attempt after that. Defaults to 2. A Retry-After header sent by the server takes precedence over this value. Has no effect when -MaximumRetryCount is 0."

    if ($FunctionName -eq "Invoke-RestMethod") {
        New-DynamicParam -Name "Paged" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Use this parameter to retrieve all pages of data from the API. This parameter is only applicable to Omada API endpoints that support pagination. Only supported for HTTP GET requests (the default); combining -Paged with -Method PUT, POST, or PATCH throws a terminating error."
    }

    return $Dictionary
}