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
    # The names are tracked separately rather than read back off $ParameterObjects. Reading a property
    # from an array enumerates its elements, and doing that to the empty array of the first iteration
    # is an error under StrictMode - which is how this function used to fail before a single dynamic
    # parameter had been built.
    [string[]]$SeenParameterNames = @()
    foreach ($ParameterSet in $FunctionObject.ParameterSets) {
        foreach ($Parameter in $ParameterSet.Parameters) {
            if ($Parameter.Name -notin $ExcludedParameters) {
                if ($Parameter.Name -notin $SeenParameterNames) {
                    $SeenParameterNames += $Parameter.Name
                    $ParameterSetName = @($($ParameterSet.Name))
                    $ParameterObjects += @{
                        Name                            = $Parameter.Name
                        Type                            = $Parameter.ParameterType
                        Alias                           = $Parameter.Aliases
                        # No ValidateSet is copied across. CommandParameterInfo has no such member -
                        # the validate sets live in its Attributes collection - so the read that used
                        # to sit here yielded $null for every parameter and no inherited parameter has
                        # ever carried one. It is left that way deliberately rather than derived from
                        # Attributes: the value is splatted on to the real Invoke-RestMethod /
                        # Invoke-WebRequest, which enforces its own validation, so deriving it here
                        # would only move the same rejection earlier and could reject values the
                        # module accepts today.
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
    # Same reason as above: $ParameterObjects is empty when every parameter of the wrapped cmdlet was
    # excluded, so the set names are materialised once behind a count check rather than read off the
    # array twice inline.
    [string[]]$DeclaredParameterSetNames = @()
    if ($ParameterObjects.Count -gt 0) {
        $DeclaredParameterSetNames = @($ParameterObjects.ParameterSetName)
    }

    # The uniqued list is indexed rather than passed whole to IsNullOrWhiteSpace, which would rely on
    # an array-to-string conversion to say anything at all. The Count test in front of it means there
    # is exactly one element to look at, so this asks the question the condition actually means: the
    # wrapped cmdlet declared a single, unnamed parameter set.
    $UniqueParameterSetNames = @($DeclaredParameterSetNames | Select-Object -Unique)
    if ($UniqueParameterSetNames.Count -eq 1 -and [string]::IsNullOrWhiteSpace($UniqueParameterSetNames[0])) {
        $ParameterObjectSetNames += "__AllParameterSets"
        $ParameterObjects | ForEach-Object { $_.ParameterSetName = "__AllParameterSets" }
    }
    else {
        $ParameterObjectSetNames += $DeclaredParameterSetNames | Select-Object -Unique
    }

    foreach ($ParameterObject in $ParameterObjects) {
        New-DynamicParam @ParameterObject
    }

    New-DynamicParam -Name "AuthenticationType" -Type "string" -ValidateSet ("OAuth", "Integrated", "Basic", "Browser", "WebView2", "Windows", "None") -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -Value "WebView2" -HelpMessage 'The type of authentication to use for the request. Default is ''WebView2''. The acceptable values for this parameter are:
- ''None'': No explicit authentication is used.
- ''Basic'': Requires Credential. The credentials are sent as an RFC 7617 Basic Authentication ''Authorization: basic'' header in the format of ''base64(user:password)''.
- ''Browser'': Browser-based interactive sign-in. Today this runs on Selenium, which automatically installs and updates to the desired webdriver version based on the currently installed Microsoft Edge browser. The Selenium engine is deprecated and supported until 1 March 2027; in the first release published after that date, ''Browser'' runs on WebView2 instead. ''Browser'' itself is not going away, so no script change is needed at any point - do not migrate to ''WebView2'' to get ahead of this, because that value is deprecated as well. See https://github.com/Fortigi/OmadaWeb.PS/issues/50.
- ''Integrated'': Uses Windows Integrated Authentication.
- ''OAuth'': Non-interactive OAuth2 client-credentials authentication, for unattended scripts, scheduled tasks and CI pipelines - it opens no browser and needs no desktop session. The client authenticates either with a certificate (-ClientId together with -OAuthCertificateThumbprint, -OAuthCertificatePath or -OAuthCertificate, which is what Microsoft recommends over a secret) or with a client id and secret in -Credential. Entra ID is the default token endpoint; any other provider is reached with -OAuthUri and -OAuthScope.
- ''WebView2'': For environments where Selenium is restricted, you can use the Microsoft WebView2 NuGet package instead. WebView2 does not use the developer tools of the Edge browser and should work when developer options is not allowed. The WebView2 assemblies ship with the module, so no download is needed; a module installed without them falls back to downloading them into %LOCALAPPDATA%\OmadaWeb.PS\Bin on first use. WebView2 uses a dedicated Edge user profile per session (base URL, authentication type and, when known, user), located under %LOCALAPPDATA%\OmadaWeb.PS\Edge User Data.
- ''Windows'': Requires Credential. Uses Windows authentication with the supplied credentials. The credential is passed to the underlying web request, which automatically negotiates using Kerberos/NTLM (''Negotiate'') when the server issues a challenge.

Supplying AuthenticationType overrides any Authorization headers supplied to Headers or included in WebSession.'
    New-DynamicParam -Name "EntraIdTenantId" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "The tenant id or name for -AuthenticationType OAuth." -Alias "AzureAdTenantId"
    New-DynamicParam -Name "EntraApplicationIdUri" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Enter the application ID URI when the base url does not equal the configured application ID URI in Entra ID. This parameter is used for -AuthenticationType OAuth."
    New-DynamicParam -Name "OAuthScope" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "OAuth2 scope to be used. Defaults to the form used for Entra ID. This parameter is used for -AuthenticationType OAuth."
    New-DynamicParam -Name "OAuthUri" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Provide a custom OAuth2 URI. Defaults to the form used for Entra ID based on the provided EntraIdTenantId. This parameter is used for -AuthenticationType OAuth.

Together with -OAuthScope this is the provider-neutral way to reach any OpenID Connect or OAuth2 token endpoint, so an Omada tenant federated to Okta, Ping, ADFS or Keycloak needs no Entra-named parameter at all."
    New-DynamicParam -Name "ClientId" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "The application (client) id of the service principal to authenticate as. This parameter is used for -AuthenticationType OAuth.

It is required whenever one of the -OAuthCertificate* parameters is used. For the client secret flow the client id is taken from the user name of -Credential instead, so -ClientId is not needed there, and supplying it overrides the user name.

With a certificate the client id is never derived from -Credential, even when one is supplied: a credential held for some other purpose would otherwise sign an assertion for the wrong application, and the identity provider's rejection would name neither cause nor cure."
    New-DynamicParam -Name "OAuthCertificate" -Type ([System.Security.Cryptography.X509Certificates.X509Certificate2]) -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "An already loaded certificate, including its private key, to authenticate the client with instead of a client secret. This parameter is used for -AuthenticationType OAuth in combination with -ClientId.

Use this when the certificate comes from somewhere this module does not know about, such as Azure Key Vault or a SecretManagement vault. To take it from the Windows certificate store or from a file, use -OAuthCertificateThumbprint or -OAuthCertificatePath instead; exactly one of the three may be supplied.

This is not the same parameter as Invoke-RestMethod's -Certificate, which selects a client certificate for the TLS connection. That one is still available and unchanged."
    New-DynamicParam -Name "OAuthCertificateThumbprint" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "The thumbprint of the certificate to authenticate the client with instead of a client secret. This parameter is used for -AuthenticationType OAuth in combination with -ClientId.

The certificate is looked up in 'CurrentUser\My' and then in 'LocalMachine\My', so a scheduled task running under a service account and an interactive session find their own certificate without being told where it is. It must have a private key the account can read. Separators are ignored, so a thumbprint copied out of the Windows certificate dialog can be pasted in unchanged.

This is not the same parameter as Invoke-RestMethod's -CertificateThumbprint, which selects a client certificate for the TLS connection. That one is still available and unchanged."
    New-DynamicParam -Name "OAuthCertificatePath" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Path to a PKCS#12 (.pfx or .p12) file holding the certificate and private key to authenticate the client with instead of a client secret. This parameter is used for -AuthenticationType OAuth in combination with -ClientId. Supply the file's password with -OAuthCertificatePassword."
    New-DynamicParam -Name "OAuthCertificatePassword" -Type ([System.Security.SecureString]) -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "The password protecting the file named by -OAuthCertificatePath, as a SecureString. Omit it for a file that is not password protected."
    New-DynamicParam -Name "CookiePath" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Attempts to load a stored Omada authentication cookie from this path. This file will be updated when re-authentication is needed. If the file does not exist, it will be created after successful authentication. When this option is used, the default cookie cache is not written - this file takes its place.

The file is encrypted with DPAPI, exactly like the default cookie cache, so it is readable only by the user who created it on the machine where it was created. There is no option to write it unencrypted. This parameter only applies in combination with parameter -AuthenticationType Browser or -AuthenticationType WebView2.

IMPORTANT: Because the protection is tied to the user and the machine, a cookie file cannot be copied to another user or another computer. A file written unencrypted by an earlier version of this module is still accepted: it is read once, immediately re-written encrypted, and a warning is shown."
    New-DynamicParam -Name "SkipCookieCache" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Do not cache the encrypted Omada authentication cookie. It will also not be cached when -CookiePath is used. This parameter only applies in combination with parameter -AuthenticationType Browser and -AuthenticationType WebView2."
    New-DynamicParam -Name "ForceAuthentication" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Force authentication to Omada even when the cookie is still valid."
    New-DynamicParam -Name "EdgeProfile" -Type "string" -ValidateSet $Script:EdgeProfiles.Name -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Use the specified Edge profile for the authentication request. The acceptable values for this parameter are based on the available profiles on your system.

IMPORTANT: Due to the requirements of Selenium, the selected Edge profile needs to be closed when using this parameter."
    New-DynamicParam -Name "InPrivate" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Use InPrivate mode for the authentication request."
    New-DynamicParam -Name "UseWebView2" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Use WebView2 instead of Selenium WebDriver for browser-based authentication.

IMPORTANT: This parameter is deprecated and obsolete. The default is AuthenticationType WebView2, so this parameter is not needed anymore and will be removed in a future release."
    New-DynamicParam -Name "PreferredMfaMethod" -Type "string" -ValidateSet ("PhoneAppNotification", "PhoneAppOTP", "OneWaySMS", "TwoWayVoiceMobile", "TwoWayVoiceAlternateMobile", "TwoWayVoiceOffice", "ConsolidatedTelephony") -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage 'The multi-factor authentication method to select when Entra ID asks which way to sign in, and the account has more than one method registered. Without this parameter the most secure method the account offers is chosen automatically, preferring an Authenticator approval over a code that has to be typed, a code over a text message, and a text message over a voice call.

The values are the method identifiers Entra ID itself uses, so they mean the same thing whatever language the sign-in page is served in:
- ''PhoneAppNotification'': Microsoft Authenticator approval, including number matching.
- ''PhoneAppOTP'': A verification code from Microsoft Authenticator.
- ''OneWaySMS'': A code sent by text message.
- ''TwoWayVoiceMobile'': A call to the registered mobile number.
- ''TwoWayVoiceAlternateMobile'': A call to the registered alternate mobile number.
- ''TwoWayVoiceOffice'': A call to the registered office number.
- ''ConsolidatedTelephony'': The consolidated telephony method.

When the account does not offer the requested method, a warning is written and the most secure method it does offer is used instead, so a preference never fails a sign-in that would otherwise succeed.

IMPORTANT: This parameter only applies to -AuthenticationType WebView2, and to -AuthenticationType Browser once that runs on WebView2. Supplying it with any other authentication type raises a terminating error.'
    New-DynamicParam -Name "DebugWebView2" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Use this parameter to enable WebView2 browser debugging options like Developer Tools"
    New-DynamicParam -Name "SessionKey" -Type "string" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Explicitly discriminate the reusable authentication session (cookie, base URL, WebView2/Selenium profile) to use for this call, in addition to the base URL, -AuthenticationType and -Credential (when supplied). Use this to keep multiple concurrent sessions apart when they would otherwise share the same base URL, authentication type and credential - for example two interactive Browser/WebView2 logins to the same tenant before either has a known user identity. Has no effect on which cookie/base URL etc. is used beyond distinguishing sessions from each other; defaults to an empty value, which reproduces prior single-session-per-(base URL, AuthenticationType, Credential) behavior."

    New-DynamicParam -Name "SkipBodyRedaction" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Write the request body to the verbose stream as it was sent, instead of as its keys and value shapes. Use this when the body itself is what you are troubleshooting - the query an Omada SQL troubleshooting call sent, for example - and the shape summary does not tell you what went wrong.

This lifts one rule only. Inside the body, a member whose name names a secret is still masked, credentials and secure strings are still masked by type, and a token or authorization header appearing inside a body value is still caught. Everything outside the body - headers, credential, session cookie - is unaffected.

Only use it when the body carries no secret you would mind reading back: the verbose stream is what callers capture into their own logs and export to a file, so anything shown here can end up attached to a support ticket."

    New-DynamicParam -Name "MaximumRetryCount" -Type ([int]) -Alias "MaxRetryCount" -ValidateRange @(0, [int]::MaxValue) -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -Value 3 -HelpMessage "How many times a failed request is retried before the error is raised. Defaults to 3, so a request is attempted 4 times in total. Use -MaximumRetryCount 0 to switch retrying off.

Only requests that can be repeated safely are retried: HTTP GET and HEAD, including the page requests -Paged makes. A POST, PUT, PATCH or DELETE may already have been applied by the server, so it is never repeated automatically. Retries are triggered by the transient conditions a multi-tenant cloud produces - HTTP 429, 502, 503 and 504, and socket-level network failures - and never by an authentication failure, which is handled by re-authenticating instead. A client-side timeout is not retried either, so -TimeoutSec keeps bounding the call.

Between attempts the command waits -RetryIntervalSec, doubling that wait after each attempt and varying it slightly so that several clients backing off at once do not retry in lockstep. When the server answers with a Retry-After header, the delay it asks for is used instead. Every retry is reported on the verbose stream with the status code and the delay."
    New-DynamicParam -Name "RetryIntervalSec" -Type ([int]) -ValidateRange @(0, [int]::MaxValue) -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -Value 2 -HelpMessage "The wait in seconds before the first retry, doubled for each attempt after that. Defaults to 2. A Retry-After header sent by the server takes precedence over this value. Has no effect when -MaximumRetryCount is 0."

    if ($FunctionName -eq "Invoke-RestMethod") {
        New-DynamicParam -Name "Paged" -Type "System.Management.Automation.SwitchParameter" -ParameterSetName $ParameterObjectSetNames -DPDictionary $Dictionary -HelpMessage "Use this parameter to retrieve all pages of data from the API. This parameter is only applicable to Omada API endpoints that support pagination. Only supported for HTTP GET requests (the default); combining -Paged with -Method PUT, POST, or PATCH throws a terminating error."
    }

    return $Dictionary
}