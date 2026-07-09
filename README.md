# OmadaWeb.PS PowerShell module
[![PSGallery Version](https://img.shields.io/powershellgallery/v/OmadaWeb.PS.svg?style=flat&logo=powershell&label=PSGallery%20Version)](https://www.powershellgallery.com/packages/OmadaWeb.PS) [![PSGallery Downloads](https://img.shields.io/powershellgallery/dt/OmadaWeb.PS.svg?style=flat&logo=powershell&label=PSGallery%20Downloads)](https://www.powershellgallery.com/packages/OmadaWeb.PS) [![PowerShell](https://img.shields.io/badge/PowerShell-5.1-blue?style=flat&logo=powershell)](https://www.powershellgallery.com/packages/OmadaWeb.PS) [![PowerShell](https://img.shields.io/badge/PowerShell-7-darkblue?style=flat&logo=powershell)](https://www.powershellgallery.com/packages/OmadaWeb.PS) [![PSGallery Platform](https://img.shields.io/powershellgallery/p/OmadaWeb.PS.svg?style=flat&logo=powershell&label=PSGallery%20Platform)](https://www.powershellgallery.com/packages/OmadaWeb.PS)

## DESCRIPTION

OmadaWeb.PS is a PowerShell module containing commands to manage data via Omada web and OData endpoints in the cloud or on-prem. This module adds support for additional authentication types like OAuth2 based on client credentials and browser-based login.

This module contains two functions that wraps over the built-in PowerShell commands [`Invoke-RestMethod`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod) and [`Invoke-WebRequest`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest). It adds authentication handling to be used with Omada.

When using browser based authentication this module is able to sign-in automatically to Entra ID when providing credentials via the -Credential parameter. When using number based MFA it is also capable to copy the required number to you clipboard if you have PhoneLink active. It makes it a little bit easier to past the number directly in the Authenticator app on your phone.

## INSTALLATION

To install the module from the PowerShell Gallery, you can use the following command:

```powershell
Install-Module -Name OmadaWeb.PS
```

## UPDATE

To update the module from the PowerShell Gallery, you can use the following command:

```powershell
Update-Module -Name OmadaWeb.PS
```

## USAGE

### Requirements

This module requires:
- Windows operating system (x86 or x64 architecture);
- Windows PowerShell 5.1 or higher (PowerShell 7 is preferred);
- Windows with Edge Chromium installed (Only for -AuthenticationType "Browser" ).

### Importing the Module

To import the module, use the following command:

```powershell
Import-Module OmadaWeb.PS
```

```powershell
# Use WebView2 for a request
Invoke-OmadaWebRequest -Uri "https://your-omada-instance.com/api/data"
```

### Authentication Types

```powershell
# Use Selenium for a request
Invoke-OmadaWebRequest -Uri "https://your-omada-instance.com/api/data" -AuthenticationType "Browser"
```

## SYNTAX

<!-- BEGIN GENERATED SYNTAX -->
### Invoke-OmadaRestMethod (StandardMethod)

```powershell
Invoke-OmadaRestMethod -Uri <uri> [-AuthenticationType {OAuth | Integrated | Basic | Browser | WebView2 | Windows | None}] [-EntraIdTenantId <string>] [-EntraApplicationIdUri <string>] [-OAuthScope <string>] [-OAuthUri <string>] [-CookiePath <string>] [-SkipCookieCache <switch>] [-ForceAuthentication <switch>] [-EdgeProfile <string>] [-InPrivate <switch>] [-UseWebView2 <switch>] [-DebugWebView2 <switch>] [-Paged <switch>] [-SessionKey <string>] [<Invoke-RestMethod Parameters>]
```

### Invoke-OmadaRestMethod (StandardMethodNoProxy)

```powershell
Invoke-OmadaRestMethod -Uri <uri> -NoProxy [-AuthenticationType {OAuth | Integrated | Basic | Browser | WebView2 | Windows | None}] [-EntraIdTenantId <string>] [-EntraApplicationIdUri <string>] [-OAuthScope <string>] [-OAuthUri <string>] [-CookiePath <string>] [-SkipCookieCache <switch>] [-ForceAuthentication <switch>] [-EdgeProfile <string>] [-InPrivate <switch>] [-UseWebView2 <switch>] [-DebugWebView2 <switch>] [-Paged <switch>] [-SessionKey <string>] [<Invoke-RestMethod Parameters>]
```

### Invoke-OmadaRestMethod (CustomMethod)

```powershell
Invoke-OmadaRestMethod -Uri <uri> -CustomMethod <string> [-AuthenticationType {OAuth | Integrated | Basic | Browser | WebView2 | Windows | None}] [-EntraIdTenantId <string>] [-EntraApplicationIdUri <string>] [-OAuthScope <string>] [-OAuthUri <string>] [-CookiePath <string>] [-SkipCookieCache <switch>] [-ForceAuthentication <switch>] [-EdgeProfile <string>] [-InPrivate <switch>] [-UseWebView2 <switch>] [-DebugWebView2 <switch>] [-Paged <switch>] [-SessionKey <string>] [<Invoke-RestMethod Parameters>]
```

### Invoke-OmadaRestMethod (CustomMethodNoProxy)

```powershell
Invoke-OmadaRestMethod -Uri <uri> -CustomMethod <string> -NoProxy [-AuthenticationType {OAuth | Integrated | Basic | Browser | WebView2 | Windows | None}] [-EntraIdTenantId <string>] [-EntraApplicationIdUri <string>] [-OAuthScope <string>] [-OAuthUri <string>] [-CookiePath <string>] [-SkipCookieCache <switch>] [-ForceAuthentication <switch>] [-EdgeProfile <string>] [-InPrivate <switch>] [-UseWebView2 <switch>] [-DebugWebView2 <switch>] [-Paged <switch>] [-SessionKey <string>] [<Invoke-RestMethod Parameters>]
```

### Invoke-OmadaWebRequest (StandardMethod)

```powershell
Invoke-OmadaWebRequest -Uri <uri> [-AuthenticationType {OAuth | Integrated | Basic | Browser | WebView2 | Windows | None}] [-EntraIdTenantId <string>] [-EntraApplicationIdUri <string>] [-OAuthScope <string>] [-OAuthUri <string>] [-CookiePath <string>] [-SkipCookieCache <switch>] [-ForceAuthentication <switch>] [-EdgeProfile <string>] [-InPrivate <switch>] [-UseWebView2 <switch>] [-DebugWebView2 <switch>] [-SessionKey <string>] [<Invoke-WebRequest Parameters>]
```

### Invoke-OmadaWebRequest (StandardMethodNoProxy)

```powershell
Invoke-OmadaWebRequest -Uri <uri> -NoProxy [-AuthenticationType {OAuth | Integrated | Basic | Browser | WebView2 | Windows | None}] [-EntraIdTenantId <string>] [-EntraApplicationIdUri <string>] [-OAuthScope <string>] [-OAuthUri <string>] [-CookiePath <string>] [-SkipCookieCache <switch>] [-ForceAuthentication <switch>] [-EdgeProfile <string>] [-InPrivate <switch>] [-UseWebView2 <switch>] [-DebugWebView2 <switch>] [-SessionKey <string>] [<Invoke-WebRequest Parameters>]
```

### Invoke-OmadaWebRequest (CustomMethod)

```powershell
Invoke-OmadaWebRequest -Uri <uri> -CustomMethod <string> [-AuthenticationType {OAuth | Integrated | Basic | Browser | WebView2 | Windows | None}] [-EntraIdTenantId <string>] [-EntraApplicationIdUri <string>] [-OAuthScope <string>] [-OAuthUri <string>] [-CookiePath <string>] [-SkipCookieCache <switch>] [-ForceAuthentication <switch>] [-EdgeProfile <string>] [-InPrivate <switch>] [-UseWebView2 <switch>] [-DebugWebView2 <switch>] [-SessionKey <string>] [<Invoke-WebRequest Parameters>]
```

### Invoke-OmadaWebRequest (CustomMethodNoProxy)

```powershell
Invoke-OmadaWebRequest -Uri <uri> -CustomMethod <string> -NoProxy [-AuthenticationType {OAuth | Integrated | Basic | Browser | WebView2 | Windows | None}] [-EntraIdTenantId <string>] [-EntraApplicationIdUri <string>] [-OAuthScope <string>] [-OAuthUri <string>] [-CookiePath <string>] [-SkipCookieCache <switch>] [-ForceAuthentication <switch>] [-EdgeProfile <string>] [-InPrivate <switch>] [-UseWebView2 <switch>] [-DebugWebView2 <switch>] [-SessionKey <string>] [<Invoke-WebRequest Parameters>]
```

<!-- END GENERATED SYNTAX -->

## EXAMPLES

Here are some example commands you can use with the OmadaWeb.PS module:

### Example 1: Example command to invoke a web request. This uses -AuthenticationType "WebView2" by default.
```powershell
Invoke-OmadaWebRequest -Uri "https://example.omada.cloud"
```

### Example 2: Retrieve an Identity object to the OData endpoint using explicit WebView2 based authentication.
```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -AuthenticationType "WebView2"
```

### Example 3: Retrieve an Identity object to the OData endpoint using Browser based authentication by using the Microsoft Web Driver (Selenium) engine.
```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -AuthenticationType "Browser"
```

### Example 4: Retrieve Identity object using EntraId OAuth authentication
```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -AuthenticationType "OAuth" -EntraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" -Credential $ClientCredential
```

### Example 5: Retrieve Identity object using WebView2 authentication on EntraID with a credential specified
When adding a credential parameter the sign-in process will try to automatically select the correct user when already signed-in or and enters the provided credentials automatically. When PhoneLink is active, you have clipboard sharing configured, number based MFA is used, the required value is copied to the clipboard so you only need to paste it in the authenticator app.
```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -AuthenticationType "Browser" -Credential $UserCredential
```

### Example 6: Retrieve Identity object using Okta OAuth authentication
```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -AuthenticationType "OAuth" -EntraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" -OAuthUri "https://dev-505878.okta.com/oauth2/ausc0u4lq9sPySN5W4x7/v1/token" -OAuthScope "omadaIdentityCloud" -Credential $ClientCredential
```

### Example 7: Retrieve all Identity objects for paged OData feeds
```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity" -Paged
```

## PARAMETERS
The built-in are the same for both Invoke-OmadaRestMethod and Invoke-OmadaWebRequest.

<!-- BEGIN GENERATED PARAMETERS -->
### -AuthenticationType <string>
The type of authentication to use for the request. Default is `WebView2`. The acceptable values for this parameter are:
- `None`: No explicit authentication is used.
- `Basic`: Requires **Credential**. The credentials are sent as an RFC 7617 Basic Authentication `Authorization: basic` header in the format of `base64(user:password)`.
- `Browser`: Uses Selenium for authentication with Omada. It automatically installs and updates to the desired webdriver version based on the currently installed Microsoft Edge browser.
- `Integrated`: Uses Windows Integrated Authentication.
- `OAuth`: Requires **Credential**. OAuth2 authentication with Entra ID by default, other IDPs are possible using additional OAuth parameters.
- `WebView2`: For environments where Selenium is restricted, you can use the [Microsoft WebView2](https://developer.microsoft.com/en-us/Microsoft-edge/webview2) [NuGet](https://www.nuget.org/packages/microsoft.web.webview2) package instead. WebView2 does not use the developer tools of the Edge browser and should work when developer options is not allowed. Binaries will be placed in %LOCALAPPDATA%\OmadaWeb.PS\Bin and downloaded automatically when not present. WebView2 uses a dedicated Edge user profile per session (base URL, authentication type and, when known, user), located under %LOCALAPPDATA%\OmadaWeb.PS\Edge User Data.
- `Windows`: Requires **Credential**. Uses Windows authentication with the supplied credentials. The credential is passed to the underlying web request, which automatically negotiates using Kerberos/NTLM (`Negotiate`) when the server issues a challenge.

Supplying **AuthenticationType** overrides any Authorization headers supplied to Headers or included in WebSession.

```yaml
        Type: System.String
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```

### -EntraIdTenantId <string>
The tenant id or name for -AuthenticationType OAuth.

```yaml
        Type: System.String
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: AzureAdTenantId
        Dynamic: true
        Accept wildcard characters: false
```

### -EntraApplicationIdUri <string>
Enter the application ID URI when the base url does not equal the configured application ID URI in Entra ID. This parameter is used for -AuthenticationType OAuth.

```yaml
        Type: System.String
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```

### -OAuthScope <string>
OAuth2 scope to be used. Defaults to the form used for Entra ID. This parameter is used for -AuthenticationType OAuth.

```yaml
        Type: System.String
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```

### -OAuthUri <string>
Provide a custom OAuth2 URI. Defaults to the form used for Entra ID based on the provided EntraIdTenantId. This parameter is used for -AuthenticationType OAuth.

```yaml
        Type: System.String
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```

### -CookiePath <string>
Attempts to load a stored Omada authentication cookie from this path. This file will be updated when re-authentication is needed. If the file does not exist, it will be created after successful authentication. When this option is used, an encrypted cookie is not cached.

> [!IMPORTANT]
> Be aware that an unencrypted version of the session cookie is stored on the file system. This parameter only applies in combination with parameter -AuthenticationType Browser and -AuthenticationType WebView2. Make sure it is stored at a secure location so it cannot be accessed by unauthorized users.

```yaml
        Type: System.String
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```

### -SkipCookieCache <switch>
Do not cache the encrypted Omada authentication cookie. It will also not be cached when -CookiePath is used. This parameter only applies in combination with parameter -AuthenticationType Browser and -AuthenticationType WebView2.

```yaml
        Type: System.Management.Automation.SwitchParameter
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```

### -ForceAuthentication <switch>
Force authentication to Omada even when the cookie is still valid.

```yaml
        Type: System.Management.Automation.SwitchParameter
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```

### -EdgeProfile <string>
Use the specified Edge profile for the authentication request. The acceptable values for this parameter are based on the available profiles on your system.

> [!IMPORTANT]
> Due to the requirements of Selenium, the selected Edge profile needs to be closed when using this parameter.

```yaml
        Type: System.String
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```

### -InPrivate <switch>
Use InPrivate mode for the authentication request.

```yaml
        Type: System.Management.Automation.SwitchParameter
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```

### -UseWebView2 <switch>
Use WebView2 instead of Selenium WebDriver for browser-based authentication.

> [!IMPORTANT]
> This parameter is deprecated and obsolete. The default is AuthenticationType WebView2, so this parameter is not needed anymore and will be removed in a future release.

```yaml
        Type: System.Management.Automation.SwitchParameter
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```

### -DebugWebView2 <switch>
Use this parameter to enable WebView2 browser debugging options like Developer Tools

```yaml
        Type: System.Management.Automation.SwitchParameter
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```

### -Paged <switch>
Use this parameter to retrieve all pages of data from the API. This parameter is only applicable to Omada API endpoints that support pagination. Only supported for HTTP GET requests (the default); combining -Paged with -Method PUT, POST, or PATCH throws a terminating error.

This parameter only applies to Invoke-OmadaRestMethod.

```yaml
        Type: System.Management.Automation.SwitchParameter
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```

### -SessionKey <string>
Explicitly discriminate the reusable authentication session (cookie, base URL, WebView2/Selenium profile) to use for this call, in addition to the base URL, -AuthenticationType and -Credential (when supplied). Use this to keep multiple concurrent sessions apart when they would otherwise share the same base URL, authentication type and credential - for example two interactive Browser/WebView2 logins to the same tenant before either has a known user identity. Has no effect on which cookie/base URL etc. is used beyond distinguishing sessions from each other; defaults to an empty value, which reproduces prior single-session-per-(base URL, AuthenticationType, Credential) behavior.

```yaml
        Type: System.String
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```
<!-- END GENERATED PARAMETERS -->

### Invoke-RestMethod Parameters / Invoke-WebRequest Parameters
All other parameters, except the exclusion list below, are inherited from the PowerShell built-in functions [`Invoke-RestMethod`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod) for `Invoke-OmadaRestMethod` and [`Invoke-WebRequest`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest) for `Invoke-OmadaWebRequest`.

The following native parameters are excluded because they are handled within the module: `-Session`, `-WebSession`, `-Authentication`, `-SessionVariable`, `-UseDefaultCredentials`, `-UseBasicParsing`.

Please see Microsoft documentation for all other available options.

## CONTRIBUTING

Contributions are welcome! If you have ideas for improvements or bug fixes, feel free to open a pull request on [GitHub](https://github.com/Fortigi/OmadaWeb.PS).

After changing dynamic parameters in `OmadaWeb.PS/Private/Set-DynamicParameter.ps1`, run `Build/Update-ReadmeHelp.ps1` (PowerShell 7) to refresh the generated SYNTAX and PARAMETERS sections of this README before committing.

## RELATED LINKS

[`Invoke-RestMethod`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod)

[`Invoke-WebRequest`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest)

[`Omada Documentation`](https://documentation.omadaidentity.com/)
## LICENSE

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
