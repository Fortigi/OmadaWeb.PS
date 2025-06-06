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

## USAGE

### Requirements

This module requires:
- Windows operating system;
- Windows PowerShell 5.1 or higher (PowerShell 7 is preferred);
- Windows with Edge Chromium installed (Only for -AuthenticationType "Browser").

### Importing the Module

To import the module, use the following command:

```powershell
Import-Module OmadaWeb.PS
```

When using -AuthenticationType "Browser", on the first authentication attempt, the module will download the latest versions of [Selenium](https://github.com/SeleniumHQ/selenium) and the [Edge Driver](https://developer.microsoft.com/en-us/microsoft-edge/tools/webdriver). Binaries will be placed in %LOCALAPPDATA%\OmadaWeb.PS. Edge Webdriver updates automatically when a newer Edge version is detected during execution.

## SYNTAX

### Invoke-OmadaRestMethod

```powershell
Invoke-OmadaRestMethod -Uri <uri> [-AuthenticationType {OAuth | Integrated | Basic | Browser | Windows}] [-CookiePath <string>]	[-SkipCookieCache <switch>] 	[-ForceAuthentication <switch>]	[-EdgeProfile <string>]	[-InPrivate <switch>] [<Invoke-RestMethod Parameters>]
```

### Invoke-OmadaRestMethod AuthenticationType: OAuth

```powershell
Invoke-OmadaRestMethod -Uri <uri> [-AuthenticationType {OAuth}] [-CookiePath <string>]	[-SkipCookieCache <switch>] 	[-ForceAuthentication <switch>]	[-EdgeProfile <string>]	[-InPrivate <switch>] [-EntraIdTenantId <string>] [<Invoke-RestMethod Parameters>]
```

### Invoke-OmadaWebRequest

```powershell
Invoke-OmadaWebRequest -Uri <uri> [-AuthenticationType {OAuth | Integrated | Basic | Browser | Windows}] [-CookiePath <string>]	[-SkipCookieCache <switch>] 	[-ForceAuthentication <switch>]	[-EdgeProfile <string>]	[-InPrivate <switch>] [<Invoke-RestMethod Parameters>]
```

### Invoke-OmadaWebRequest AuthenticationType: OAuth

```powershell
Invoke-OmadaWebRequest -Uri <uri> [-AuthenticationType {OAuth}] [-CookiePath <string>]	[-SkipCookieCache <switch>] 	[-ForceAuthentication <switch>]	[-EdgeProfile <string>]	[-InPrivate <switch>] [-EntraIdTenantId <string>] [<Invoke-RestMethod Parameters>]
```

## EXAMPLES

Here are some example commands you can use with the OmadaWeb.PS module:

### Example 1: Example command to invoke a web request. This uses -AuthenticationType "Browser" by default.
```powershell
Invoke-OmadaWebRequest -Uri "https://example.omada.cloud"
```

### Example 2: Retrieve an Identity object to the OData endpoint using Browser based authentication.
```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -AuthenticationType "Browser"
```

### Example 3: Retrieve Identity object using EntraId OAuth authentication
```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -AuthenticationType "OAuth" -EmtraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" -Credential $Credential
```

### Example 4: Retrieve Identity object using Browser authentication on EntraID with a credential specified
When adding a credential parameter the sign-in process will try to automatically select the correct user when already signed-in or and enters the provided credentials automatically. When PhoneLink is active, you have clipboard sharing configured, number based MFA is used, the required value is copied to the clipboard so you only need to paste it in the authenticator app.
```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -AuthenticationType "Browser" -Credential $Credential
```

## PARAMETERS
The built-in are the same for both Invoke-OmadaRestMethod and Invoke-OmadaWebRequest.

###    -AuthenticationType <string>
The type of authentication to use for the request. Default is `Browser`. The acceptable values for this parameter are:
- Basic
- Browser
- Integrated
- OAuth
- Windows

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

###    -EdgeProfile <string>
Use the specified Edge profile for the authentication request. The acceptable values for this parameter is based on the available profiles on your system.

> [!IMPORTANT]
> Due the requirements of Selenium the selected Edge profile needs to be closed when using this parameter.

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

### -SkipCookieCache <boolean>
Do not cache the encrypted Omada authentication cookie. It wil also not be cached when -CookiePath is used. This parameter only applies in combination with parameter -AuthenticationMethod Browser.

```yaml
        Type: System.Boolean
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```

### -CookiePath <string>
Attempts to load a stored Omada authentication cookie from this path. This file will be updated re-authentication is needed. If the file does not exist, it will be created after successful authentication. When this option is used, an encrypted cookie is not cached. This parameter only applies in combination with parameter -AuthenticationMethod Browser.

> [!IMPORTANT]
> Be aware that an unencrypted version of the session cookie is stored on the file system. Make sure it is stored at a secure location so it cannot be accessed by unauthorized users.

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

### Invoke-RestMethod Parameters / Invoke-WebRequest Parameters
All other parameters, except the exclusion list below, are inherited from the PowerShell built-in functions [`Invoke-RestMethod`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod) for `Invoke-OmadaRestMethod` and [`Invoke-WebRequest`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest) for `Invoke-OmadaWebRequest`.

The following native parameters are excluded because they are handled within the module: `-Session`, `-WebSession`, `-Authentication`, `-SessionVariable`, `-UseDefaultCredentials`, `-UseBasicParsing`.

Please see Microsoft documentation for all other available options.

## RELATED LINKS

[`Invoke-RestMethod`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod)

[`Invoke-WebRequest`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest)

[`Omada Documentation`](https://documentation.omadaidentity.com/)
## LICENSE

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
