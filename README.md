# OmadaWeb.PS PowerShell module
[![PSGallery Version](https://img.shields.io/powershellgallery/v/OmadaWeb.PS.svg?style=flat&logo=powershell&label=PSGallery%20Version)](https://www.powershellgallery.com/packages/OmadaWeb.PS) [![PSGallery Downloads](https://img.shields.io/powershellgallery/dt/OmadaWeb.PS.svg?style=flat&logo=powershell&label=PSGallery%20Downloads)](https://www.powershellgallery.com/packages/OmadaWeb.PS) [![PowerShell](https://img.shields.io/badge/PowerShell-5.1-blue?style=flat&logo=powershell)](https://www.powershellgallery.com/packages/OmadaWeb.PS) [![PowerShell](https://img.shields.io/badge/PowerShell-7-darkblue?style=flat&logo=powershell)](https://www.powershellgallery.com/packages/OmadaWeb.PS) [![PSGallery Platform](https://img.shields.io/powershellgallery/p/OmadaWeb.PS.svg?style=flat&logo=powershell&label=PSGallery%20Platform)](https://www.powershellgallery.com/packages/OmadaWeb.PS)

## DESCRIPTION

OmadaWeb.PS is a PowerShell module containing commands to manage data via Omada web and OData endpoints in the cloud or on-prem. This module adds support for additional authentication types like OAuth2 based on client credentials and browser-based login.

This module contains two functions that wrap over the built-in PowerShell commands [`Invoke-RestMethod`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod) and [`Invoke-WebRequest`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest). It adds authentication handling to be used with Omada. A third command, `Clear-OmadaWebCache`, reports and removes everything the module stores on the machine.

When using browser based authentication this module is able to sign-in automatically to Entra ID when providing credentials via the -Credential parameter. When using number based MFA it is also capable to copy the required number to you clipboard if you have PhoneLink active. It makes it a little bit easier to past the number directly in the Authenticator app on your phone.

## COMMANDS

<!-- BEGIN GENERATED COMMANDS -->
| Command | Description |
|---|---|
| [`Clear-OmadaWebCache`](#clear-omadawebcache) | Reports and removes the data OmadaWeb.PS stores on this machine. |
| [`Invoke-OmadaRestMethod`](#invoke-omadarestmethod) | Sends a request to an Omada REST or OData endpoint and returns the response as objects. |
| [`Invoke-OmadaWebRequest`](#invoke-omadawebrequest) | Sends a request to an Omada web endpoint and returns the raw HTTP response. |
<!-- END GENERATED COMMANDS -->

Every command documents itself, so `Get-Help` works as you would expect:

```powershell
Get-Help Invoke-OmadaRestMethod -Full
Get-Help Invoke-OmadaRestMethod -Examples
```

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

### Signing in, and what happens when Microsoft changes the sign-in page

Every browser-based authentication type signs in the same way a person does: a browser window opens on your Omada instance, and you complete the sign-in there. Passing a `-Credential` for an Entra tenant adds one convenience on top of that - the module recognizes the Microsoft sign-in pages and fills the fields in for you.

That recognition rests on element IDs Microsoft can change at any time, and does. When a page no longer matches what the module knows, the module stops filling fields in and hands the window back to you with a warning such as:

```text
WARNING: Automated Microsoft sign-in could not continue - handing control back to you.
  State            : ProcessingScenarios/NoMatchingScenario
  Missing elements : i0116, idSIButton9
  Elements present : signInName
  Page URL         : https://login.microsoftonline.com/common/oauth2/authorize
```

**A change to the sign-in page degrades autofill, not login.** The window is open and the request continues as soon as you have signed in yourself, exactly as it does for every tenant that is not on Entra - there, signing in by hand at your own identity provider is the normal path anyway.

The warning names the state, the elements that were expected but absent, and the page the browser was on. That is what a fix needs, so please include it when reporting the change at [GitHub Issues](https://github.com/Fortigi/OmadaWeb.PS/issues). No query string is printed, since sign-in URLs carry request identifiers.

The module waits 60 seconds without progress before it gives up on autofill, so a slow round trip to Microsoft is not mistaken for a changed page. Waiting for you to approve a sign-in request in your authenticator app does not count against that.

### Deprecations

The module carries its own deprecation schedule and warns you at runtime, once per PowerShell
session, when a feature you are using is on it. Nothing switches over silently on a date - each
change lands in the **first release published after** the date below, not on the date itself.

#### Phase 1 - the Selenium browser engine

| | |
|---|---|
| **Deprecated** | The Selenium/EdgeDriver engine currently behind `-AuthenticationType Browser` |
| **Announced** | 19 August 2026 |
| **Replacement** | WebView2 - which `Browser` will itself run on after the switch |
| **Supported until** | **1 March 2027** |
| **New features** | WebView2 only, effective immediately |

Until 1 March 2027 the Selenium engine keeps working and keeps receiving bug fixes. It receives no
new capability - all new work lands in WebView2.

**Windows PowerShell 5.1 support is not affected.** It remains fully supported; only the Selenium
engine is going away.

#### What you need to do

**If you use `-AuthenticationType Browser`: nothing, ever.** `Browser` is the long-term correct
value. Today it runs Selenium; after the switch the same value runs WebView2.

If you would like WebView2 sooner, simply omit the parameter - WebView2 is today's default:

```powershell
Invoke-OmadaRestMethod -Uri $Uri                    # WebView2 today, and after the switch too
```

> [!IMPORTANT]
> Do **not** migrate `Browser` -> `WebView2` to get ahead of this deprecation. `WebView2` is itself
> deprecated (phase 2, see below), so that migration would have to be undone. If you want to name
> the value explicitly, `Browser` is the one to write.

#### Where this is heading

One browser-based login, named for **what** it does rather than **which engine** does it:

```powershell
Invoke-OmadaRestMethod -Uri $Uri -AuthenticationType Browser   # browser login, runs on WebView2
```

| | Today | First release after 1 Mar 2027 | First release after 1 Sep 2027 |
|---|---|---|---|
| Default `-AuthenticationType` | `WebView2` | `Browser` | `Browser` |
| `Browser` runs on | Selenium | **WebView2** | WebView2 |
| `WebView2` runs on | WebView2 | WebView2 *(deprecated)* | - *removed* |
| `-UseWebView2` | redundant, warns | redundant, warns | - *removed* |

Phase 1 (the Selenium engine) is tracked in
[#50](https://github.com/Fortigi/OmadaWeb.PS/issues/50); phase 2 (`WebView2` and `-UseWebView2`) in
[#51](https://github.com/Fortigi/OmadaWeb.PS/issues/51). Nothing in phase 2 breaks before
1 September 2027.

If your environment depends on the Selenium engine and WebView2 is not a viable replacement for you,
say so in [#50](https://github.com/Fortigi/OmadaWeb.PS/issues/50). The timeline can be reconsidered
on evidence; it cannot be reconsidered on silence.

### Local data footprint

Everything the module stores lives under one root: `%LOCALAPPDATA%\OmadaWeb.PS`. This is what ends up there, and why:

| Artefact | Path | Contents | Protection | Lifetime |
|---|---|---|---|---|
| Encrypted cookie cache | `%LOCALAPPDATA%\OmadaWeb.PS\Cookies\<session hash>` | The Omada session cookie, so a later command does not have to sign in again | Encrypted with [DPAPI](https://learn.microsoft.com/en-us/dotnet/standard/security/how-to-use-data-protection), readable only by the current user on the current machine | Until the cookie is rejected, `-ForceAuthentication` or `-SkipCookieCache` is used, or you run `Clear-OmadaWebCache` |
| Custom cookie file | The folder you pass to `-CookiePath` | The same session cookie | **Not encrypted** - protected only by the file system permissions of the location you choose | Until you delete it. It is not touched by `Clear-OmadaWebCache`, because the module does not know where you put it |
| WebView2 browser profiles | `%LOCALAPPDATA%\OmadaWeb.PS\Edge User Data\OmadaWebView2Profile_<session hash>` | A dedicated Edge user profile per session, holding the Entra ID cookies and tokens that make re-authentication silent | File system permissions of your Windows user profile | Until you run `Clear-OmadaWebCache` |
| Selenium browser profiles | `%LOCALAPPDATA%\OmadaWeb.PS\Profiles\<Edge profile>_<session hash>` | The Edge `user-data-dir` used when `-EdgeProfile` is combined with `-AuthenticationType Browser` | File system permissions of your Windows user profile | Until you run `Clear-OmadaWebCache` |
| Downloaded binaries | `%LOCALAPPDATA%\OmadaWeb.PS\Bin` | Selenium, WebView2, `msedgedriver.exe` and their dependencies, downloaded on first use (see [SECURITY.md](SECURITY.md) for the full inventory) | File system permissions of your Windows user profile | Until you run `Clear-OmadaWebCache`; re-downloaded when needed |
| In-memory sessions | Not written to disk | Session cookies, base URLs and browser profile paths for the current PowerShell session | Process memory | Until the PowerShell session ends or you run `Clear-OmadaWebCache` |

> [!NOTE]
> Up to and including the previous release the encrypted cookie cache was written directly into `%TEMP%`, one file per session. Any cache found there is moved to `%LOCALAPPDATA%\OmadaWeb.PS\Cookies` the first time that same session is used again. Caches for sessions you never use again would otherwise stay in `%TEMP%` indefinitely, so `Clear-OmadaWebCache` reports them as a separate artefact and removes them. It identifies them by content as well as by name, and removes only those files - never the `%TEMP%` folder itself, and never files it did not write.

Nothing is sent anywhere except to the Omada instance and identity provider you address, and to the download locations of the components listed above.

### Clearing cached data

`Clear-OmadaWebCache` reports and removes everything in the table above.

```powershell
# See what is stored, without removing anything
Clear-OmadaWebCache -ListOnly | Format-Table Scope, Artefact, Path, ItemCount, SizeBytes

# See what would be removed
Clear-OmadaWebCache -WhatIf

# Sign out everywhere: drop cookies and browser profiles, keep the downloaded binaries
Clear-OmadaWebCache -Scope Cookies, BrowserProfiles

# Remove everything without being prompted
Clear-OmadaWebCache -Force
```

`-Scope` accepts `All` (the default), `Cookies`, `BrowserProfiles`, `Binaries` and `Sessions`. Binaries that are already loaded into the running PowerShell session are locked by Windows; the command reports which ones it could not remove, and they can be removed after closing that session.

## SYNTAX

<!-- BEGIN GENERATED SYNTAX -->
### Clear-OmadaWebCache (__AllParameterSets)

```powershell
Clear-OmadaWebCache [-Scope {All | Cookies | BrowserProfiles | Binaries | Sessions}] [-ListOnly <switch>] [-Force <switch>] [-WhatIf <switch>] [-Confirm <switch>] [<CommonParameters>]
```

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

<!-- BEGIN GENERATED EXAMPLES -->
### Clear-OmadaWebCache

OmadaWeb.PS keeps state between commands so you do not have to sign in again for every call. All of it lives under %LOCALAPPDATA%\OmadaWeb.PS:

- Cookies: the Omada session cookie of each session, encrypted with DPAPI for the current user. Caches left in %TEMP% by an earlier version of the module are reported as one extra artefact and removed file by file; the %TEMP% folder itself is never touched, and files there that were not written by this module are left alone.
- BrowserProfiles: the per-session Edge user profiles used by WebView2 and by Selenium. These hold the Entra ID cookies and tokens that make re-authentication silent, so they are the artefacts to remove when you want to sign out completely or switch user.
- Binaries: Selenium, WebView2, msedgedriver.exe and their dependencies, downloaded on first use. Removing them only costs a fresh download next time.
- Sessions: the authentication state held in memory by the current PowerShell session.

Run with -ListOnly to see what is stored without changing anything. Without -ListOnly the artefacts are removed, after confirmation; use -WhatIf to preview and -Force to skip the prompt.

In both cases one object per artefact is returned, reporting the path, how many items it holds, how large it is, how it is protected and whether it was removed.

A binary that is already loaded into the running PowerShell session is locked by Windows and cannot be removed. The command reports which ones it could not remove and continues; close that PowerShell session and run it again to remove them.

Files written by -CookiePath are not touched, because their location is chosen by the caller and is not known to the module. Remove those yourself.

#### Example 1

```powershell
Clear-OmadaWebCache -ListOnly | Format-Table Scope, Artefact, Path, ItemCount, SizeBytes
```

Shows everything the module has stored on this machine without removing any of it.

#### Example 2

```powershell
Clear-OmadaWebCache -WhatIf
```

Reports exactly what would be removed, and removes nothing.

#### Example 3

```powershell
Clear-OmadaWebCache -Scope Cookies, BrowserProfiles
```

Signs out everywhere by dropping the cached session cookies and the Edge profiles holding the Entra ID tokens, while keeping the downloaded binaries so the next command does not have to download them again. Asks for confirmation first.

#### Example 4

```powershell
Clear-OmadaWebCache -Force
```

Removes everything the module stores, without prompting. Useful when handing a machine over, or as a cleanup step at the end of an automated run.

### Invoke-OmadaRestMethod

Invoke-OmadaRestMethod wraps the built-in Invoke-RestMethod and adds the authentication Omada Identity Cloud and on-premises installations need. Every parameter of Invoke-RestMethod is accepted unchanged, so an existing call can be switched over by changing the command name.

Authentication is selected with -AuthenticationType. The default, WebView2, signs in with an embedded Microsoft Edge browser and works for interactive use, including Entra ID and multi-factor authentication. OAuth authenticates with a client credential and needs no interaction, which is what unattended scripts and scheduled jobs should use. Browser, Windows, Integrated and Basic cover Selenium-driven sign-in and the classic on-premises authentication schemes.

After a successful interactive sign-in the session cookie is cached, encrypted with DPAPI for the current user, so subsequent commands in the same or a later PowerShell session do not prompt again. Use Clear-OmadaWebCache to remove it, or -SkipCookieCache to never write it. Sessions are kept apart by base URL, authentication type and, when known, user, so several Omada environments can be addressed from the same PowerShell session.

For OData feeds that return results one page at a time, -Paged follows every @odata.nextLink and returns the complete result set as a single object.

The command name Invoke-OmadaODataMethod is an alias for this command.

#### Example 1

```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)"
```

Retrieves one identity from the OData endpoint. Because no -AuthenticationType is given, an embedded Edge browser opens for sign-in the first time; later commands reuse the cached session cookie.

#### Example 2

```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity" -Paged
```

Retrieves every identity from a paged OData feed. Without -Paged only the first page is returned, together with an @odata.nextLink property.

#### Example 3

```powershell
$ClientCredential = Get-Credential
$Identities = Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity" -Paged -AuthenticationType "OAuth" -EntraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" -Credential $ClientCredential
```

Extracts all identities without any interaction, authenticating to Entra ID with a client id and secret. This is the form to use in unattended scripts and scheduled tasks.

#### Example 4

```powershell
$Body = @{ FIRSTNAME = "Jane"; LASTNAME = "Doe" }
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/api/DataObject/Identity" -Method "POST" -Body $Body
```

Creates an object through the Omada API. -Body is accepted as a hashtable and sent as JSON; the Content-Type and Accept headers default to application/json.

#### Example 5

```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -AuthenticationType "Browser"
```

Signs in through a full Microsoft Edge browser driven by Selenium instead of the embedded WebView2 browser. The matching WebDriver version is installed automatically.

#### Example 6

```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -Credential $UserCredential
```

Signs in interactively, but hands the sign-in page the account to use and fills in the password, which saves picking the right account when several are signed in. With number matching multi-factor authentication the number is copied to the clipboard, so with Phone Link and clipboard sharing active it can be pasted straight into the Authenticator app.

#### Example 7

```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -AuthenticationType "OAuth" -OAuthUri "https://dev-505878.okta.com/oauth2/ausc0u4lq9sPySN5W4x7/v1/token" -OAuthScope "omadaIdentityCloud" -Credential $ClientCredential
```

Authenticates against an identity provider other than Entra ID - here Okta - by supplying the token endpoint and scope explicitly.

#### Example 8

```powershell
Invoke-OmadaRestMethod -Uri "https://omada.contoso.local/odata/dataobjects/identity(123456)" -AuthenticationType "Integrated"
```

Retrieves an identity from an on-premises installation using Windows Integrated Authentication, without opening a browser.

### Invoke-OmadaWebRequest

Invoke-OmadaWebRequest wraps the built-in Invoke-WebRequest and adds the authentication Omada Identity Cloud and on-premises installations need. Every parameter of Invoke-WebRequest is accepted unchanged, so an existing call can be switched over by changing the command name.

Use this command when the response itself matters - status code, headers, raw content or a file to download. For REST and OData endpoints that return JSON, Invoke-OmadaRestMethod is usually the better fit because it deserializes the response for you and can page through OData feeds.

Authentication is selected with -AuthenticationType. The default, WebView2, signs in with an embedded Microsoft Edge browser and works for interactive use, including Entra ID and multi-factor authentication. OAuth authenticates with a client credential and needs no interaction, which is what unattended scripts and scheduled jobs should use. Browser, Windows, Integrated and Basic cover Selenium-driven sign-in and the classic on-premises authentication schemes.

After a successful interactive sign-in the session cookie is cached, encrypted with DPAPI for the current user, so subsequent commands in the same or a later PowerShell session do not prompt again. Use Clear-OmadaWebCache to remove it, or -SkipCookieCache to never write it. Sessions are kept apart by base URL, authentication type and, when known, user, so several Omada environments can be addressed from the same PowerShell session.

#### Example 1

```powershell
Invoke-OmadaWebRequest -Uri "https://example.omada.cloud"
```

Signs in to the Omada portal through an embedded Edge browser and returns the response. Useful as a first call to confirm that authentication works and to prime the cookie cache.

#### Example 2

```powershell
$Response = Invoke-OmadaWebRequest -Uri "https://example.omada.cloud/api/Health"
$Response.StatusCode
```

Keeps the full response so the status code and headers can be inspected, which Invoke-OmadaRestMethod does not expose.

#### Example 3

```powershell
$ClientCredential = Get-Credential
Invoke-OmadaWebRequest -Uri "https://example.omada.cloud/Report/Export?id=42" -OutFile "C:\Temp\report.xlsx" -AuthenticationType "OAuth" -EntraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" -Credential $ClientCredential
```

Downloads a report to disk without any interaction, authenticating to Entra ID with a client id and secret.

#### Example 4

```powershell
Invoke-OmadaWebRequest -Uri "https://omada.contoso.local/OData/DataObjects" -AuthenticationType "Windows" -Credential $UserCredential
```

Requests an on-premises endpoint with explicit Windows credentials, negotiating Kerberos or NTLM when the server issues a challenge.
<!-- END GENERATED EXAMPLES -->

## PARAMETERS

<!-- BEGIN GENERATED PARAMETERS -->
### Invoke-OmadaRestMethod and Invoke-OmadaWebRequest parameters

These are added on top of the parameters of the wrapped cmdlet and are the same for both commands, unless stated otherwise.

#### -AuthenticationType <string>
The type of authentication to use for the request. Default is `WebView2`. The acceptable values for this parameter are:
- `None`: No explicit authentication is used.
- `Basic`: Requires **Credential**. The credentials are sent as an RFC 7617 Basic Authentication `Authorization: basic` header in the format of `base64(user:password)`.
- `Browser`: Browser-based interactive sign-in. Today this runs on Selenium, which automatically installs and updates to the desired webdriver version based on the currently installed Microsoft Edge browser. The Selenium engine is deprecated and supported until 1 March 2027; in the first release published after that date, `Browser` runs on WebView2 instead. `Browser` itself is not going away, so no script change is needed at any point - do not migrate to `WebView2` to get ahead of this, because that value is deprecated as well. See https://github.com/Fortigi/OmadaWeb.PS/issues/50.
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

#### -EntraIdTenantId <string>
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

#### -EntraApplicationIdUri <string>
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

#### -OAuthScope <string>
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

#### -OAuthUri <string>
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

#### -CookiePath <string>
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

#### -SkipCookieCache <switch>
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

#### -ForceAuthentication <switch>
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

#### -EdgeProfile <string>
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

#### -InPrivate <switch>
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

#### -UseWebView2 <switch>
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

#### -DebugWebView2 <switch>
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

#### -Paged <switch>
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

#### -SessionKey <string>
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

### Clear-OmadaWebCache parameters

#### -Force <switch>
Remove without asking for confirmation. -WhatIf still takes precedence.

```yaml
        Type: System.Management.Automation.SwitchParameter
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: false
        Accept wildcard characters: false
```

#### -ListOnly <switch>
Report what is stored without removing anything.

```yaml
        Type: System.Management.Automation.SwitchParameter
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: false
        Accept wildcard characters: false
```

#### -Scope <string[]>
Which artefacts to report and remove: All (the default), Cookies, BrowserProfiles,
Binaries or Sessions. More than one value can be given.

```yaml
        Type: System.String[]
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: false
        Accept wildcard characters: false
```
<!-- END GENERATED PARAMETERS -->

### Invoke-RestMethod Parameters / Invoke-WebRequest Parameters
All other parameters, except the exclusion list below, are inherited from the PowerShell built-in functions [`Invoke-RestMethod`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod) for `Invoke-OmadaRestMethod` and [`Invoke-WebRequest`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest) for `Invoke-OmadaWebRequest`.

The following native parameters are excluded because they are handled within the module: `-Session`, `-WebSession`, `-Authentication`, `-SessionVariable`, `-UseDefaultCredentials`, `-UseBasicParsing`.

Please see Microsoft documentation for all other available options.

## SECURITY

Found a security problem? Please report it privately through [GitHub Security Advisories](https://github.com/Fortigi/OmadaWeb.PS/security/advisories/new) instead of opening an issue. See [SECURITY.md](SECURITY.md) for supported versions, response targets and scope.

Every release has a CycloneDX Software Bill of Materials (`OmadaWeb.PS-<version>.cdx.json`) attached as a release asset, covering the module and the components it downloads at runtime. The inventory it is generated from is [`Build/Dependencies.psd1`](Build/Dependencies.psd1).

## CONTRIBUTING

Contributions are welcome! If you have ideas for improvements or bug fixes, feel free to open a pull request on [GitHub](https://github.com/Fortigi/OmadaWeb.PS).

The COMMANDS, SYNTAX, EXAMPLES and PARAMETERS sections of this README are generated from the module, so help is written once:

- Comment-based help in `OmadaWeb.PS/Public/*.ps1` is the source of every synopsis, description and example, and of the parameter descriptions of commands that declare their parameters normally. It is the same help `Get-Help` shows.
- The `-HelpMessage` strings in `OmadaWeb.PS/Private/Set-DynamicParameter.ps1` are the source of the parameter descriptions of `Invoke-OmadaRestMethod` and `Invoke-OmadaWebRequest`, whose parameters are all added at runtime and so cannot carry comment-based `.PARAMETER` entries. `Get-Help` reads the same strings.

After changing either, run `Build/Update-ReadmeHelp.ps1` (PowerShell 7) to refresh those sections before committing. Do not edit them by hand. `Build/Test-CommentBasedHelp.ps1` runs as part of the build and fails when an exported command is missing a synopsis, a description, at least three examples, a link, or help for one of its parameters.

## RELATED LINKS

[`Invoke-RestMethod`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod)

[`Invoke-WebRequest`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest)

[`Omada Documentation`](https://documentation.omadaidentity.com/)
## LICENSE

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
