# OmadaWeb.PS PowerShell module
[![PSGallery Version](https://img.shields.io/powershellgallery/v/OmadaWeb.PS.svg?style=flat&logo=powershell&label=PSGallery%20Version)](https://www.powershellgallery.com/packages/OmadaWeb.PS) [![PSGallery Downloads](https://img.shields.io/powershellgallery/dt/OmadaWeb.PS.svg?style=flat&logo=powershell&label=PSGallery%20Downloads)](https://www.powershellgallery.com/packages/OmadaWeb.PS) [![PowerShell](https://img.shields.io/badge/PowerShell-5.1-blue?style=flat&logo=powershell)](https://www.powershellgallery.com/packages/OmadaWeb.PS) [![PowerShell](https://img.shields.io/badge/PowerShell-7-darkblue?style=flat&logo=powershell)](https://www.powershellgallery.com/packages/OmadaWeb.PS) [![PSGallery Platform](https://img.shields.io/powershellgallery/p/OmadaWeb.PS.svg?style=flat&logo=powershell&label=PSGallery%20Platform)](https://www.powershellgallery.com/packages/OmadaWeb.PS)

## DESCRIPTION

OmadaWeb.PS is a PowerShell module containing commands to manage data via Omada web and OData endpoints in the cloud or on-prem. It serves two scenarios equally:

- **Unattended automation** - scheduled tasks, CI pipelines and servers with no desktop session, using OAuth2 client credentials with a **certificate** or a client secret. No browser, no interaction, nothing to type. See [Unattended automation](#unattended-automation-scheduled-tasks-ci-and-servers-without-a-desktop).
- **Interactive use** - a browser window opens on your Omada instance and you sign in there, at whichever identity provider your tenant uses, multi-factor authentication included.

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

### Unattended automation (scheduled tasks, CI and servers without a desktop)

A REST wrapper for an identity governance product earns its keep in the jobs nobody watches: the nightly reconciliation, the joiner-mover-leaver feed, the pipeline that asserts a policy still holds. Those run where there is no browser, no desktop session and nobody to approve anything, so `-AuthenticationType "OAuth"` is not a fallback for that case - it is the case the module was built to serve.

OAuth here means the OAuth2 **client credentials** grant: the script authenticates as an application, not as a person. The application proves who it is in one of two ways.

| | Certificate | Client secret |
|---|---|---|
| Supplied with | `-ClientId` + `-OAuthCertificateThumbprint` / `-OAuthCertificatePath` / `-OAuthCertificate` | `-Credential` (client id as user name, secret as password) |
| Travels on the wire | A short-lived signature. The private key never leaves the machine | The secret itself, on every request |
| If a log or a script leaks | Nothing reusable | Full access until the secret is rotated |
| Recommended by Microsoft | Yes | Only where a certificate is impossible |

**Use a certificate.** The module signs a JSON Web Token with the certificate's private key ([RFC 7523](https://datatracker.ietf.org/doc/html/rfc7523)) and sends that in place of the secret, which is what Entra ID and every other compliant provider expect.

#### Setting it up end to end

**1. Register the application in Entra ID.** In *Entra admin center → Applications → App registrations → New registration*, register an application for the job. Note its **Application (client) ID** and **Directory (tenant) ID**. No redirect URI is needed - this application never signs a user in.

**2. Give it a credential.**

- *Certificate (recommended).* Create one and keep the private key on the machine that runs the job:

  ```powershell
  $Certificate = New-SelfSignedCertificate -Subject "CN=OmadaWeb.PS automation" -CertStoreLocation "Cert:\CurrentUser\My" -KeyExportPolicy NonExportable -KeySpec Signature -NotAfter (Get-Date).AddYears(1)
  Export-Certificate -Cert $Certificate -FilePath ".\OmadaWeb.PS-automation.cer" | Out-Null
  $Certificate.Thumbprint
  ```

  Upload the exported `.cer` - the public half only - under *Certificates & secrets → Certificates*. A certificate issued by your own PKI works the same way and is preferable where you have one.

  For a job that runs as a service account or in a container, export a password-protected `.pfx` instead and hand it to the command with `-OAuthCertificatePath` and `-OAuthCertificatePassword`.

- *Client secret.* Under *Certificates & secrets → Client secrets*. Store it in [SecretManagement](https://learn.microsoft.com/en-us/powershell/utility-modules/secretmanagement/overview) or another vault, never in the script, and put a rotation date in the calendar.

**3. Grant the application access to the Omada API.** The token has to be issued *for Omada*, which means requesting a scope that belongs to the Omada application rather than to your own. In your tenant, find the enterprise application for your Omada instance, and grant your new application the application permission (app role) it exposes; admin consent is required because there is no user to consent. The audience the module requests is `<Application ID URI>/.default`, where the Application ID URI defaults to the base URL of the request - override it with `-EntraApplicationIdUri` when Omada is registered under a different URI.

**4. Map the application to an Omada account.** A valid token gets the request past authentication; what it may then read or write is decided by Omada. Give the service principal an Omada identity or service account with exactly the data objects and operations the job needs, following [Omada's documentation](https://documentation.omadaidentity.com/) for your version - the exact screen differs between Omada Identity Cloud and on-premises. A job that only reads identities should not be able to write them.

**5. Run it.**

```powershell
# Certificate from the machine's certificate store, named by thumbprint.
$Identities = Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity" -Paged `
    -AuthenticationType "OAuth" `
    -EntraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" `
    -ClientId "a1b2c3d4-5e6f-7890-abcd-ef1234567890" `
    -OAuthCertificateThumbprint "9A8B7C6D5E4F30211A2B3C4D5E6F708192A3B4C5"
```

```powershell
# Certificate from a password-protected .pfx, for a container or a service account.
$CertificatePassword = ConvertTo-SecureString $env:OMADA_PFX_PASSWORD -AsPlainText -Force
$Identities = Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity" -Paged `
    -AuthenticationType "OAuth" `
    -EntraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" `
    -ClientId "a1b2c3d4-5e6f-7890-abcd-ef1234567890" `
    -OAuthCertificatePath "C:\ProgramData\OmadaJobs\automation.pfx" `
    -OAuthCertificatePassword $CertificatePassword
```

```powershell
# Certificate fetched from somewhere the module knows nothing about, such as Azure Key Vault.
$Identities = Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity" -Paged `
    -AuthenticationType "OAuth" `
    -EntraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" `
    -ClientId "a1b2c3d4-5e6f-7890-abcd-ef1234567890" `
    -OAuthCertificate $CertificateFromVault
```

```powershell
# The client secret flow, unchanged. The client id is the credential's user name.
$ClientCredential = Get-Credential
$Identities = Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity" -Paged `
    -AuthenticationType "OAuth" `
    -EntraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" `
    -Credential $ClientCredential
```

The certificate is looked up in `CurrentUser\My` first and then in `LocalMachine\My`, so a scheduled task under a service account and an interactive session each find their own without being told where to look. Verbose output names the certificate that signed the request - thumbprint, subject, expiry - along with the client id and the token endpoint, which is what diagnosing a refused sign-in needs. What never reaches any stream is the credential itself: not the client secret, not the private key, and not the signed assertion.

`-ClientId` is required with a certificate and is never derived from `-Credential`, so a credential the script holds for something else cannot quietly sign an assertion for the wrong application.

#### Any identity provider, not only Entra ID

`-EntraIdTenantId` is a shorthand that builds the Microsoft token endpoint for you. Where Omada is federated to something else, name the endpoint and the scope directly and no Entra-named parameter is involved at all:

```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" `
    -AuthenticationType "OAuth" `
    -OAuthUri "https://dev-505878.okta.com/oauth2/ausc0u4lq9sPySN5W4x7/v1/token" `
    -OAuthScope "omadaIdentityCloud" `
    -ClientId "0oa1b2c3d4e5f6g7h8i9" `
    -OAuthCertificateThumbprint "9A8B7C6D5E4F30211A2B3C4D5E6F708192A3B4C5"
```

The client assertion follows RFC 7523, so it is accepted by Okta, Ping, Keycloak, ADFS and anything else that implements `private_key_jwt`. Providers differ in what they call the scope and whether the assertion audience must be the token endpoint or the issuer; the module sends the token endpoint, which is what the specification requires and what these products expect.

#### What is not here, and why

**Device-code flow is deliberately not implemented.** It was evaluated for this scenario and does not fit it:

- It is a *delegated* flow. The token it returns represents a person, so it does not solve authenticating a job - it only moves where the person has to be. A scheduled task cannot read a code off a console and type it into another device.
- Its refresh token would have to be persisted to survive between runs, which puts a long-lived, user-scoped credential on disk. That is a worse security position than the certificate this module now supports, for less capability.
- It requires the application to be registered as a public client, which is the opposite of what an unattended integration should be.
- The interactive case it would serve is already covered. `-AuthenticationType "WebView2"` signs in through an embedded browser and caches the session, and on a machine where a browser genuinely cannot run, a certificate needs no human at all.

Replacing interactive browser sign-in with token acquisition was investigated separately in [#23](https://github.com/Fortigi/OmadaWeb.PS/issues/23) and closed: Omada is itself the OpenID Connect relying party, and the session it hands back is established in the browser. Device code would not change that either.

**A token is requested per call.** There is no token cache yet, so a script making many calls asks the identity provider for a token each time. That is tracked in [#29](https://github.com/Fortigi/OmadaWeb.PS/issues/29) and does not affect correctness, only the number of round trips.

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

You should not normally be the one to find out. A scheduled job signs in to Entra ID once a day in a real browser and opens an issue when autofill stops recognising a screen, so a change on Microsoft's side is usually already known - and often already fixed - by the time you meet it. See [the Entra sign-in canary](docs/entra-canary.md).

### When Omada refuses the sign-in

A sign-in can also fail on the other side of the redirect. Your identity provider authenticates you, hands the browser back to Omada, and Omada decides it cannot let you in - because the account is not a member of the tenant the Omada application is registered in, because the application registration is not accepted, or for any other reason it reports. That failure is not an HTTP error and not a redirect: it is a message rendered on Omada's own logon page, which then simply sits there.

Nothing that a sign-in usually watches for happens next. No authentication cookie is ever set, so the module used to wait out its response watchdog, close the window, open a new one, and land on the same page again - three times over, half an hour, ending in `Could not authenticate to '...'` with nothing said about why.

The module now reads that page. An error it recognizes as final ends the sign-in immediately, with the message Omada showed:

```text
WARNING: Sign-in was refused and will not be retried.
  Error code : AADSTS50178
  Page URL   : https://example.omada.cloud/logon.aspx
  Engine     : WebView2
  Message    : AADSTS50178: User account '...' from identity provider '...' does not exist in tenant 'Example' and cannot access the application '...' in that tenant. The account needs to be added as an external user in the tenant first.
  Meaning    : The account that signed in is not known in the tenant the Omada application is registered in.
Opening the sign-in window again would land on this same page, so no further attempts are made. ...
```

The request then fails with that same message rather than with a bare "could not authenticate", so what to do next - sign in with an account from the application's own tenant, or have yours invited into it - is in the error itself. Add `-ForceAuthentication` to the retry so the sign-in starts from a clean browser session.

**Only errors a retry cannot change stop the sign-in.** An error you can correct in the window that is open - a wrong password on Omada's own logon form - is reported once and otherwise left alone, and so is one the identity provider may recover from by itself, such as `server_error` or `temporarily_unavailable`. An error whose wording the module does not recognize is treated as final only when the page offers no way to sign in again, which is what a failed federated sign-in looks like whatever the Omada version calls it.

This applies to both browser engines, and the message is redacted and stripped of its query string like every other diagnostic the module prints.

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
| Bundled WebView2 assemblies | `lib\<edition>\<architecture>` inside the installed module | The Microsoft WebView2 assemblies, fetched and verified against their pinned SHA-256 when the module was built (see [SECURITY.md](SECURITY.md)) | File system permissions of the module's install location, usually read-only | For the lifetime of the installed module version; never written to at runtime |
| Downloaded binaries | `%LOCALAPPDATA%\OmadaWeb.PS\Bin` | Selenium, `msedgedriver.exe` and their dependencies - plus WebView2 when the module was installed without its bundle - downloaded on first use (see [SECURITY.md](SECURITY.md) for the full inventory) | File system permissions of your Windows user profile | Until you run `Clear-OmadaWebCache`; re-downloaded when needed |
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
Invoke-OmadaRestMethod -Uri <uri> [-AuthenticationType {OAuth | Integrated | Basic | Browser | WebView2 | Windows | None}] [-EntraIdTenantId <string>] [-EntraApplicationIdUri <string>] [-OAuthScope <string>] [-OAuthUri <string>] [-CookiePath <string>] [-SkipCookieCache <switch>] [-ForceAuthentication <switch>] [-EdgeProfile <string>] [-InPrivate <switch>] [-UseWebView2 <switch>] [-DebugWebView2 <switch>] [-Paged <switch>] [-MaximumRetryCount <int>] [-RetryIntervalSec <int>] [-ClientId <string>] [-OAuthCertificate <x509certificate2>] [-OAuthCertificatePassword <securestring>] [-OAuthCertificatePath <string>] [-OAuthCertificateThumbprint <string>] [-PreferredMfaMethod {PhoneAppNotification | PhoneAppOTP | OneWaySMS | TwoWayVoiceMobile | TwoWayVoiceAlternateMobile | TwoWayVoiceOffice | ConsolidatedTelephony}] [-SessionKey <string>] [<Invoke-RestMethod Parameters>]
```

### Invoke-OmadaRestMethod (StandardMethodNoProxy)

```powershell
Invoke-OmadaRestMethod -Uri <uri> -NoProxy [-AuthenticationType {OAuth | Integrated | Basic | Browser | WebView2 | Windows | None}] [-EntraIdTenantId <string>] [-EntraApplicationIdUri <string>] [-OAuthScope <string>] [-OAuthUri <string>] [-CookiePath <string>] [-SkipCookieCache <switch>] [-ForceAuthentication <switch>] [-EdgeProfile <string>] [-InPrivate <switch>] [-UseWebView2 <switch>] [-DebugWebView2 <switch>] [-Paged <switch>] [-MaximumRetryCount <int>] [-RetryIntervalSec <int>] [-ClientId <string>] [-OAuthCertificate <x509certificate2>] [-OAuthCertificatePassword <securestring>] [-OAuthCertificatePath <string>] [-OAuthCertificateThumbprint <string>] [-PreferredMfaMethod {PhoneAppNotification | PhoneAppOTP | OneWaySMS | TwoWayVoiceMobile | TwoWayVoiceAlternateMobile | TwoWayVoiceOffice | ConsolidatedTelephony}] [-SessionKey <string>] [<Invoke-RestMethod Parameters>]
```

### Invoke-OmadaRestMethod (CustomMethod)

```powershell
Invoke-OmadaRestMethod -Uri <uri> -CustomMethod <string> [-AuthenticationType {OAuth | Integrated | Basic | Browser | WebView2 | Windows | None}] [-EntraIdTenantId <string>] [-EntraApplicationIdUri <string>] [-OAuthScope <string>] [-OAuthUri <string>] [-CookiePath <string>] [-SkipCookieCache <switch>] [-ForceAuthentication <switch>] [-EdgeProfile <string>] [-InPrivate <switch>] [-UseWebView2 <switch>] [-DebugWebView2 <switch>] [-Paged <switch>] [-MaximumRetryCount <int>] [-RetryIntervalSec <int>] [-ClientId <string>] [-OAuthCertificate <x509certificate2>] [-OAuthCertificatePassword <securestring>] [-OAuthCertificatePath <string>] [-OAuthCertificateThumbprint <string>] [-PreferredMfaMethod {PhoneAppNotification | PhoneAppOTP | OneWaySMS | TwoWayVoiceMobile | TwoWayVoiceAlternateMobile | TwoWayVoiceOffice | ConsolidatedTelephony}] [-SessionKey <string>] [<Invoke-RestMethod Parameters>]
```

### Invoke-OmadaRestMethod (CustomMethodNoProxy)

```powershell
Invoke-OmadaRestMethod -Uri <uri> -CustomMethod <string> -NoProxy [-AuthenticationType {OAuth | Integrated | Basic | Browser | WebView2 | Windows | None}] [-EntraIdTenantId <string>] [-EntraApplicationIdUri <string>] [-OAuthScope <string>] [-OAuthUri <string>] [-CookiePath <string>] [-SkipCookieCache <switch>] [-ForceAuthentication <switch>] [-EdgeProfile <string>] [-InPrivate <switch>] [-UseWebView2 <switch>] [-DebugWebView2 <switch>] [-Paged <switch>] [-MaximumRetryCount <int>] [-RetryIntervalSec <int>] [-ClientId <string>] [-OAuthCertificate <x509certificate2>] [-OAuthCertificatePassword <securestring>] [-OAuthCertificatePath <string>] [-OAuthCertificateThumbprint <string>] [-PreferredMfaMethod {PhoneAppNotification | PhoneAppOTP | OneWaySMS | TwoWayVoiceMobile | TwoWayVoiceAlternateMobile | TwoWayVoiceOffice | ConsolidatedTelephony}] [-SessionKey <string>] [<Invoke-RestMethod Parameters>]
```

### Invoke-OmadaWebRequest (StandardMethod)

```powershell
Invoke-OmadaWebRequest -Uri <uri> [-AuthenticationType {OAuth | Integrated | Basic | Browser | WebView2 | Windows | None}] [-EntraIdTenantId <string>] [-EntraApplicationIdUri <string>] [-OAuthScope <string>] [-OAuthUri <string>] [-CookiePath <string>] [-SkipCookieCache <switch>] [-ForceAuthentication <switch>] [-EdgeProfile <string>] [-InPrivate <switch>] [-UseWebView2 <switch>] [-DebugWebView2 <switch>] [-MaximumRetryCount <int>] [-RetryIntervalSec <int>] [-ClientId <string>] [-OAuthCertificate <x509certificate2>] [-OAuthCertificatePassword <securestring>] [-OAuthCertificatePath <string>] [-OAuthCertificateThumbprint <string>] [-PreferredMfaMethod {PhoneAppNotification | PhoneAppOTP | OneWaySMS | TwoWayVoiceMobile | TwoWayVoiceAlternateMobile | TwoWayVoiceOffice | ConsolidatedTelephony}] [-SessionKey <string>] [<Invoke-WebRequest Parameters>]
```

### Invoke-OmadaWebRequest (StandardMethodNoProxy)

```powershell
Invoke-OmadaWebRequest -Uri <uri> -NoProxy [-AuthenticationType {OAuth | Integrated | Basic | Browser | WebView2 | Windows | None}] [-EntraIdTenantId <string>] [-EntraApplicationIdUri <string>] [-OAuthScope <string>] [-OAuthUri <string>] [-CookiePath <string>] [-SkipCookieCache <switch>] [-ForceAuthentication <switch>] [-EdgeProfile <string>] [-InPrivate <switch>] [-UseWebView2 <switch>] [-DebugWebView2 <switch>] [-MaximumRetryCount <int>] [-RetryIntervalSec <int>] [-ClientId <string>] [-OAuthCertificate <x509certificate2>] [-OAuthCertificatePassword <securestring>] [-OAuthCertificatePath <string>] [-OAuthCertificateThumbprint <string>] [-PreferredMfaMethod {PhoneAppNotification | PhoneAppOTP | OneWaySMS | TwoWayVoiceMobile | TwoWayVoiceAlternateMobile | TwoWayVoiceOffice | ConsolidatedTelephony}] [-SessionKey <string>] [<Invoke-WebRequest Parameters>]
```

### Invoke-OmadaWebRequest (CustomMethod)

```powershell
Invoke-OmadaWebRequest -Uri <uri> -CustomMethod <string> [-AuthenticationType {OAuth | Integrated | Basic | Browser | WebView2 | Windows | None}] [-EntraIdTenantId <string>] [-EntraApplicationIdUri <string>] [-OAuthScope <string>] [-OAuthUri <string>] [-CookiePath <string>] [-SkipCookieCache <switch>] [-ForceAuthentication <switch>] [-EdgeProfile <string>] [-InPrivate <switch>] [-UseWebView2 <switch>] [-DebugWebView2 <switch>] [-MaximumRetryCount <int>] [-RetryIntervalSec <int>] [-ClientId <string>] [-OAuthCertificate <x509certificate2>] [-OAuthCertificatePassword <securestring>] [-OAuthCertificatePath <string>] [-OAuthCertificateThumbprint <string>] [-PreferredMfaMethod {PhoneAppNotification | PhoneAppOTP | OneWaySMS | TwoWayVoiceMobile | TwoWayVoiceAlternateMobile | TwoWayVoiceOffice | ConsolidatedTelephony}] [-SessionKey <string>] [<Invoke-WebRequest Parameters>]
```

### Invoke-OmadaWebRequest (CustomMethodNoProxy)

```powershell
Invoke-OmadaWebRequest -Uri <uri> -CustomMethod <string> -NoProxy [-AuthenticationType {OAuth | Integrated | Basic | Browser | WebView2 | Windows | None}] [-EntraIdTenantId <string>] [-EntraApplicationIdUri <string>] [-OAuthScope <string>] [-OAuthUri <string>] [-CookiePath <string>] [-SkipCookieCache <switch>] [-ForceAuthentication <switch>] [-EdgeProfile <string>] [-InPrivate <switch>] [-UseWebView2 <switch>] [-DebugWebView2 <switch>] [-MaximumRetryCount <int>] [-RetryIntervalSec <int>] [-ClientId <string>] [-OAuthCertificate <x509certificate2>] [-OAuthCertificatePassword <securestring>] [-OAuthCertificatePath <string>] [-OAuthCertificateThumbprint <string>] [-PreferredMfaMethod {PhoneAppNotification | PhoneAppOTP | OneWaySMS | TwoWayVoiceMobile | TwoWayVoiceAlternateMobile | TwoWayVoiceOffice | ConsolidatedTelephony}] [-SessionKey <string>] [<Invoke-WebRequest Parameters>]
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

Authentication is selected with -AuthenticationType. The default, WebView2, signs in with an embedded Microsoft Edge browser and works for interactive use, at whichever identity provider your Omada tenant uses, multi-factor authentication included. OAuth authenticates as an application with the client-credentials grant and needs no browser, no desktop session and no interaction at all, which is what unattended scripts, scheduled tasks and CI pipelines should use - with a certificate (-ClientId together with one of the -OAuthCertificate* parameters) in preference to a client secret. Browser, Windows, Integrated and Basic cover Selenium-driven sign-in and the classic on-premises authentication schemes.

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

Extracts all identities without any interaction, authenticating to Entra ID with a client id and secret.

#### Example 4

```powershell
$Identities = Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity" -Paged -AuthenticationType "OAuth" -EntraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" -ClientId "a1b2c3d4-5e6f-7890-abcd-ef1234567890" -OAuthCertificateThumbprint "9A8B7C6D5E4F30211A2B3C4D5E6F708192A3B4C5"
```

The same unattended extraction, authenticating with a certificate from the Windows certificate store instead of a client secret. The private key never leaves the machine, so nothing reusable travels on the wire. This is the form to use in scheduled tasks, CI pipelines and on servers without a desktop session. The certificate is looked for in CurrentUser\My and then in LocalMachine\My.

#### Example 5

```powershell
$CertificatePassword = ConvertTo-SecureString $env:OMADA_PFX_PASSWORD -AsPlainText -Force
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -AuthenticationType "OAuth" -EntraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" -ClientId "a1b2c3d4-5e6f-7890-abcd-ef1234567890" -OAuthCertificatePath "C:\ProgramData\OmadaJobs\automation.pfx" -OAuthCertificatePassword $CertificatePassword
```

Authenticates with a certificate held in a password-protected PKCS#12 file, which is what a container or a job running under an account without a certificate store needs.

#### Example 6

```powershell
$Body = @{ FIRSTNAME = "Jane"; LASTNAME = "Doe" }
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/api/DataObject/Identity" -Method "POST" -Body $Body
```

Creates an object through the Omada API. -Body is accepted as a hashtable and sent as JSON; the Content-Type and Accept headers default to application/json.

#### Example 7

```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -AuthenticationType "Browser"
```

Signs in through a full Microsoft Edge browser driven by Selenium instead of the embedded WebView2 browser. The matching WebDriver version is installed automatically.

#### Example 8

```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -Credential $UserCredential
```

Signs in interactively, but hands the sign-in page the account to use and fills in the password, which saves picking the right account when several are signed in. With number matching multi-factor authentication the number is copied to the clipboard, so with Phone Link and clipboard sharing active it can be pasted straight into the Authenticator app.

#### Example 9

```powershell
Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -AuthenticationType "OAuth" -OAuthUri "https://dev-505878.okta.com/oauth2/ausc0u4lq9sPySN5W4x7/v1/token" -OAuthScope "omadaIdentityCloud" -Credential $ClientCredential
```

Authenticates against an identity provider other than Entra ID - here Okta - by supplying the token endpoint and scope explicitly.

#### Example 10

```powershell
Invoke-OmadaRestMethod -Uri "https://omada.contoso.local/odata/dataobjects/identity(123456)" -AuthenticationType "Integrated"
```

Retrieves an identity from an on-premises installation using Windows Integrated Authentication, without opening a browser.

### Invoke-OmadaWebRequest

Invoke-OmadaWebRequest wraps the built-in Invoke-WebRequest and adds the authentication Omada Identity Cloud and on-premises installations need. Every parameter of Invoke-WebRequest is accepted unchanged, so an existing call can be switched over by changing the command name.

Use this command when the response itself matters - status code, headers, raw content or a file to download. For REST and OData endpoints that return JSON, Invoke-OmadaRestMethod is usually the better fit because it deserializes the response for you and can page through OData feeds.

Authentication is selected with -AuthenticationType. The default, WebView2, signs in with an embedded Microsoft Edge browser and works for interactive use, at whichever identity provider your Omada tenant uses, multi-factor authentication included. OAuth authenticates as an application with the client-credentials grant and needs no browser, no desktop session and no interaction at all, which is what unattended scripts, scheduled tasks and CI pipelines should use - with a certificate (-ClientId together with one of the -OAuthCertificate* parameters) in preference to a client secret. Browser, Windows, Integrated and Basic cover Selenium-driven sign-in and the classic on-premises authentication schemes.

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
Invoke-OmadaWebRequest -Uri "https://example.omada.cloud/Report/Export?id=42" -OutFile "C:\Temp\report.xlsx" -AuthenticationType "OAuth" -EntraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" -ClientId "a1b2c3d4-5e6f-7890-abcd-ef1234567890" -OAuthCertificateThumbprint "9A8B7C6D5E4F30211A2B3C4D5E6F708192A3B4C5"
```

The same download from a scheduled task, authenticating with a certificate from the Windows certificate store rather than a client secret, so no reusable credential travels on the wire or sits in the script.

#### Example 5

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
- `OAuth`: Non-interactive OAuth2 client-credentials authentication, for unattended scripts, scheduled tasks and CI pipelines - it opens no browser and needs no desktop session. The client authenticates either with a certificate (-ClientId together with -OAuthCertificateThumbprint, -OAuthCertificatePath or -OAuthCertificate, which is what Microsoft recommends over a secret) or with a client id and secret in -Credential. Entra ID is the default token endpoint; any other provider is reached with -OAuthUri and -OAuthScope.
- `WebView2`: For environments where Selenium is restricted, you can use the [Microsoft WebView2](https://developer.microsoft.com/en-us/Microsoft-edge/webview2) [NuGet](https://www.nuget.org/packages/microsoft.web.webview2) package instead. WebView2 does not use the developer tools of the Edge browser and should work when developer options is not allowed. The WebView2 assemblies ship with the module, so no download is needed; a module installed without them falls back to downloading them into %LOCALAPPDATA%\OmadaWeb.PS\Bin on first use. WebView2 uses a dedicated Edge user profile per session (base URL, authentication type and, when known, user), located under %LOCALAPPDATA%\OmadaWeb.PS\Edge User Data.
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

Together with -OAuthScope this is the provider-neutral way to reach any OpenID Connect or OAuth2 token endpoint, so an Omada tenant federated to Okta, Ping, ADFS or Keycloak needs no Entra-named parameter at all.

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

#### -MaximumRetryCount <int>
How many times a failed request is retried before the error is raised. Defaults to 3, so a request is attempted 4 times in total. Use -MaximumRetryCount 0 to switch retrying off.

Only requests that can be repeated safely are retried: HTTP GET and HEAD, including the page requests -Paged makes. A POST, PUT, PATCH or DELETE may already have been applied by the server, so it is never repeated automatically. Retries are triggered by the transient conditions a multi-tenant cloud produces - HTTP 429, 502, 503 and 504, and socket-level network failures - and never by an authentication failure, which is handled by re-authenticating instead. A client-side timeout is not retried either, so -TimeoutSec keeps bounding the call.

Between attempts the command waits -RetryIntervalSec, doubling that wait after each attempt and varying it slightly so that several clients backing off at once do not retry in lockstep. When the server answers with a Retry-After header, the delay it asks for is used instead. Every retry is reported on the verbose stream with the status code and the delay.

```yaml
        Type: System.Int32
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: MaxRetryCount
        Dynamic: true
        Accept wildcard characters: false
```

#### -RetryIntervalSec <int>
The wait in seconds before the first retry, doubled for each attempt after that. Defaults to 2. A Retry-After header sent by the server takes precedence over this value. Has no effect when -MaximumRetryCount is 0.

```yaml
        Type: System.Int32
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```

#### -ClientId <string>
The application (client) id of the service principal to authenticate as. This parameter is used for -AuthenticationType OAuth.

It is required whenever one of the -OAuthCertificate* parameters is used. For the client secret flow the client id is taken from the user name of -Credential instead, so -ClientId is not needed there, and supplying it overrides the user name.

With a certificate the client id is never derived from -Credential, even when one is supplied: a credential held for some other purpose would otherwise sign an assertion for the wrong application, and the identity provider's rejection would name neither cause nor cure.

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

#### -OAuthCertificate <x509certificate2>
An already loaded certificate, including its private key, to authenticate the client with instead of a client secret. This parameter is used for -AuthenticationType OAuth in combination with -ClientId.

Use this when the certificate comes from somewhere this module does not know about, such as Azure Key Vault or a SecretManagement vault. To take it from the Windows certificate store or from a file, use -OAuthCertificateThumbprint or -OAuthCertificatePath instead; exactly one of the three may be supplied.

This is not the same parameter as Invoke-RestMethod's -Certificate, which selects a client certificate for the TLS connection. That one is still available and unchanged.

```yaml
        Type: System.Security.Cryptography.X509Certificates.X509Certificate2
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```

#### -OAuthCertificatePassword <securestring>
The password protecting the file named by -OAuthCertificatePath, as a SecureString. Omit it for a file that is not password protected.

```yaml
        Type: System.Security.SecureString
        Required: false
        Position: Named
        Accept pipeline input: false
        Parameter set name: (All)
        Aliases: None
        Dynamic: true
        Accept wildcard characters: false
```

#### -OAuthCertificatePath <string>
Path to a PKCS#12 (.pfx or .p12) file holding the certificate and private key to authenticate the client with instead of a client secret. This parameter is used for -AuthenticationType OAuth in combination with -ClientId. Supply the file's password with -OAuthCertificatePassword.

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

#### -OAuthCertificateThumbprint <string>
The thumbprint of the certificate to authenticate the client with instead of a client secret. This parameter is used for -AuthenticationType OAuth in combination with -ClientId.

The certificate is looked up in `CurrentUser\My` and then in `LocalMachine\My`, so a scheduled task running under a service account and an interactive session find their own certificate without being told where it is. It must have a private key the account can read. Separators are ignored, so a thumbprint copied out of the Windows certificate dialog can be pasted in unchanged.

This is not the same parameter as Invoke-RestMethod's -CertificateThumbprint, which selects a client certificate for the TLS connection. That one is still available and unchanged.

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

#### -PreferredMfaMethod <string>
The multi-factor authentication method to select when Entra ID asks which way to sign in, and the account has more than one method registered. Without this parameter the most secure method the account offers is chosen automatically, preferring an Authenticator approval over a code that has to be typed, a code over a text message, and a text message over a voice call.

The values are the method identifiers Entra ID itself uses, so they mean the same thing whatever language the sign-in page is served in:
- `PhoneAppNotification`: Microsoft Authenticator approval, including number matching.
- `PhoneAppOTP`: A verification code from Microsoft Authenticator.
- `OneWaySMS`: A code sent by text message.
- `TwoWayVoiceMobile`: A call to the registered mobile number.
- `TwoWayVoiceAlternateMobile`: A call to the registered alternate mobile number.
- `TwoWayVoiceOffice`: A call to the registered office number.
- `ConsolidatedTelephony`: The consolidated telephony method.

When the account does not offer the requested method, a warning is written and the most secure method it does offer is used instead, so a preference never fails a sign-in that would otherwise succeed.

> [!IMPORTANT]
> This parameter only applies to -AuthenticationType WebView2, and to -AuthenticationType Browser once that runs on WebView2. Supplying it with any other authentication type raises a terminating error.

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

The binaries the module downloads on first use are pinned to an exact version and SHA-256 in [`OmadaWeb.PS/DependencyLock.psd1`](OmadaWeb.PS/DependencyLock.psd1), which ships with the module. Each download is verified against that hash before it is unpacked or loaded, and anything that does not match is deleted and refused. `msedgedriver.exe` has to match your installed Edge version so it cannot be pinned; its Authenticode signature is verified instead. See [Runtime dependency verification](SECURITY.md#runtime-dependency-verification).

The WebView2 assemblies behind the default `-AuthenticationType WebView2` are not downloaded at all: they ship inside the module under `lib\<edition>\<architecture>`, fetched and verified against the same pin when the module was built. That makes the default work on a machine with no access to nuget.org, and keeps the assemblies out of a user-writable directory. A module installed without them still downloads and verifies them exactly as before. See [Why the WebView2 assemblies are bundled](SECURITY.md#why-the-webview2-assemblies-are-bundled).

Every release has a CycloneDX Software Bill of Materials (`OmadaWeb.PS-<version>.cdx.json`) attached as a release asset, covering the module, the assemblies it bundles and the components it downloads at runtime. The inventory it is generated from is [`Build/Dependencies.psd1`](Build/Dependencies.psd1).

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
