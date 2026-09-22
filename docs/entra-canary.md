# The Entra canaries

Two scheduled GitHub Actions jobs against one tenant, watching the two things the module needs
Microsoft to keep doing:

| Job | Watches | Red means |
|---|---|---|
| **Entra ID sign-in** | Credential autofill against Microsoft's sign-in screens, in a real browser | a selector needs updating |
| **Entra ID service principal** | The client-credentials grant, once per credential form the module documents | the tenant, a credential, or the client assertion |

They live in one workflow file because they share a tenant, an environment and the alerting
machinery, and they are separate jobs because they share nothing else: one opens a browser and one
never does, so a failure in either must never be described in the other's vocabulary.

Delivers roadmap item E5 ([#33](https://github.com/Fortigi/OmadaWeb.PS/issues/33)).

> **No tenant identifier, domain, account name or password appears anywhere in this repository.**
> Every value the canary needs is a GitHub environment secret you set yourself. Everything below
> uses placeholders.

## Why it exists

Credential autofill is one optional tier of sign-in: it engages only when `-Credential` is supplied,
and it is the module's only dependency on Microsoft's sign-in DOM. Microsoft changes that DOM on its
own schedule, and until now the detection mechanism was a user bug report.

`Build/psakeBuild.ps1` has excluded the `E2E` tag from every build since long before this workflow
existed, with a comment promising a separate scheduled pipeline. This is that pipeline.

## The three scenarios

Each run drives three sign-ins, one after the other. They cannot share a run: each needs its own
browser window, and two of them are sign-ins that deliberately never finish.

| Scenario | Given | Green when |
|---|---|---|
| `PasswordAutofill` | a user name and a password | the sign-in completes and the resource comes back — the original canary |
| `UserNameOnly` | a user name, no password | the account reaches Entra **inside the authorization request** (`login_hint`), the password page is reached, no empty password is submitted, and the window is handed back saying it is waiting for you |
| `NoUserName` | neither | nothing is added to the request and nothing is driven at all — the default has to stay indistinguishable from the module not being involved in the choice |

The last two never complete, so they are watched rather than awaited: the sign-in runs in a child
process for a fixed 135 seconds — long enough for the redirect chain, the sign-in page, and the 60
seconds of no progress that ends in the handover — and is then stopped from inside the test, which
asserts against everything the module traced. A separate process is what makes that possible at all:
the WinForms dialog blocks the thread it is shown on, so nothing inside that process can be
interrupted once the window is up. That process is started `-STA`, because WebView2 is COM and cannot
be created on a multi-threaded apartment — which is what a PowerShell background job is, and why
these two scenarios failed on their first scheduled run
([#90](https://github.com/Fortigi/OmadaWeb.PS/issues/90)).

`UserNameOnly` and `NoUserName` are given an authorization request carrying **no** `prompt` and **no**
`login_hint`. For the first that is the point — whatever reaches Entra must have been put there by
the module — and for the second it is what makes "the module added nothing" mean something.

## What it covers, and what it deliberately does not

| | |
|---|---|
| **Covers** | The username screen, the password screen and "Stay signed in?" — the screens a password sign-in actually renders — driven by the shipping code path: `Invoke-WebView2MicrosoftLogin` over what `Get-EntraSignInProbeScript` reads and `Resolve-EntraSignInScreen` judges. |
| **Covers** | That an account named with `-UserName` reaches Entra as part of the request, that a missing password is waited for rather than invented, and that naming no account leaves the request alone. |
| **Does not cover** | Multi-factor authentication. An interactive approval cannot be automated, so the canary account is exempt by policy. The MFA screens in `Resolve-EntraSignInScreen` are covered by unit tests against recorded page snapshots instead. |
| **Does not cover** | Interactive sign-in in general. That is IdP-agnostic — a tenant on Ping, Okta or ADFS reaches none of this code — so there is nothing here for the canary to watch. |
| **Does not cover** | Omada itself. The canary needs no Omada environment; see below. |

**A red canary means "autofill needs a selector update", not "login is broken".** Since
[#52](https://github.com/Fortigi/OmadaWeb.PS/pull/52) a selector break turns autofill off and hands
the window to the user, so the blast radius is already capped. The canary is what makes that visible
before a user hits it.

## How it works without an Omada environment

`Initialize-WebView2` navigates to the session's `BaseUrl` and then, on each timer tick, switches on
the host the browser is currently on: the `BaseUrl` host means "look for the session cookie", and
`login.microsoftonline.com` means "drive the sign-in". A local listener standing in for the Omada
host is therefore enough to get the entire real code path:

```
Invoke-OmadaWebRequest -Uri http://localhost:8400/api/ping -AuthenticationType WebView2 -Credential <canary>
        │
        ▼
  http://localhost:8400/            302  ──▶  login.microsoftonline.com/<tenant>/oauth2/v2.0/authorize
        │                                              │
        │                                              │  ◀── the tier under test drives these screens
        │                                              ▼
  http://localhost:8400/canary  ◀── 302 ── Entra redirects back with a code
        │
        └─ sets oisauthtoken, returns 200 → Get-WebView2Cookie closes the window → request completes
```

The listener is `Tests/E2E/Start-CanaryRelyingParty.ps1`. The authorization code is never redeemed:
the canary asserts that the sign-in screens were driven, not that a token was issued.

Two details in that listener are load-bearing and should not be "tidied up":

- **The redirect path is `/canary`.** `Get-OmadaLogonErrorScript` treats a path matching
  `logon|login|signin|sign-in|error` as an Omada logon page and then sweeps the body for anything
  carrying an error severity. A path like `/signin-callback` would have the module scraping this page
  for a failure banner.
- **The redirect is stateless.** `Test-EnvironmentSuspended` fetches the `BaseUrl` with its own
  redirect-following client before the browser ever opens, so a listener that redirected only once
  would have nothing left to send the browser.

## Setting up the tenant

Use a dedicated tenant you are willing to have a password-only account in. A free trial tenant with
nothing else in it is the right shape.

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser

Connect-MgGraph -Scopes 'User.ReadWrite.All','Application.ReadWrite.All',
                        'DelegatedPermissionGrant.ReadWrite.All','Directory.Read.All',
                        'Policy.Read.All','Policy.ReadWrite.ConditionalAccess'

# Review everything it would do first.
./Build/New-EntraCanaryConfiguration.ps1 -WhatIf

# Then provision, and push the secrets straight into GitHub so they are never displayed.
./Build/New-EntraCanaryConfiguration.ps1 -GitHubRepository 'Fortigi/OmadaWeb.PS'
```

The script is idempotent — every object is looked up before it is created — so re-running it is how
you rotate the password.

### What it creates

1. **A canary user** in the tenant's initial `onmicrosoft.com` domain, with a generated password, no
   licence, no directory role and no group membership. Signing in is the only thing it can do. Its
   password is set not to expire and not to require a change at first sign-in; both prompts are
   screens the automation would not recognise.
2. **A public-client app registration** whose only redirect URI is `http://localhost:8400/canary`,
   requesting `openid`, `profile` and `User.Read` — **with tenant-wide admin consent granted**. The
   consent is not optional: an unconsented application shows a consent screen, the automation does
   not recognise it, and the canary would go red claiming Microsoft had changed something when in
   fact the tenant was simply not finished being set up.
3. **A Conditional Access policy** blocking the canary account from every application except the
   canary one. This is the containment — the account is powerless elsewhere by policy, not merely by
   holding no permissions.

### The MFA exemption

The canary cannot answer an MFA prompt, so the account has to be exempt, and the exemption is made
explicit rather than left as an absence:

- **Security defaults** are reported, and disabled only if you pass `-DisableSecurityDefaults`.
  Turning them off changes the posture of the whole tenant, which is not something a provisioning
  script should do as a side effect. While they are on, every sign-in is challenged for MFA
  registration and the canary will fail.
- **Every enabled Conditional Access policy that requires MFA** gets the canary account added to its
  excluded users. Expressed as an exclusion on each policy rather than as a permissive policy of its
  own, because a grant control is a requirement and never a waiver: a policy saying "this account may
  sign in without MFA" would not override one saying "everyone must use MFA".

In an empty tenant there are no such policies, and the script's summary says so rather than implying
an exemption was applied.

### Licensing

Conditional Access needs Microsoft Entra ID P1; a P2 trial includes it. Without P1, pass
`-SkipConditionalAccess`. The account is then contained only by holding no permissions, which is
weaker — nothing stops it signing in to other applications — and the script says so in its summary.

### IP restriction

`-AllowedIpRange` takes a list of CIDR ranges, creates a named location from them, and adds a second
policy blocking the account from anywhere else.

It is a list you supply rather than a switch that fetches GitHub's ranges, because that would not
work: GitHub-hosted runners publish several thousand CIDRs, which exceeds the 2000 ranges Entra
allows in a single named location, and they change without notice. **IP restriction is therefore
worth having on a self-hosted or fixed-egress runner and is impractical on a GitHub-hosted one.** On
GitHub-hosted runners the containment policy is what limits the account instead.

## The GitHub side

The workflow reads its secrets from an **environment** named `entra-canary`, not from repository
secrets, so no pull-request workflow can reach them.

| Secret | Contains |
|---|---|
| `CANARY_TENANT_ID` | Directory (tenant) ID |
| `CANARY_CLIENT_ID` | Application (client) ID of the canary app registration |
| `CANARY_USERNAME` | The canary account's user principal name |
| `CANARY_PASSWORD` | The canary account's password |

`New-EntraCanaryConfiguration.ps1 -GitHubRepository <owner/repo>` writes these, and the
service-principal canary's own secrets listed further down, through `gh secret set` on standard
input, so they never appear on a command line or on screen.

If the environment is empty the workflow **skips** with a notice rather than passing quietly, so a
canary that has silently stopped running is visible.

### The browser host check

Before the sign-in, the job runs `Tests/E2E/Test-CanaryBrowserHost.ps1`, which opens a WebView2
window on `about:blank` and closes it. It knows nothing about Entra ID or credentials, and that is
the point: without it, a runner that cannot open a browser fails every canary assertion at once and
the diagnostic reads "the sign-in page was not recognised" — true, and pointing at exactly the wrong
thing.

It fails the job on its own and deliberately **does not** file an issue, because nothing about the
sign-in page has changed and an alert saying otherwise would be a lie.

Run it on its own against a new runner image with the **Run workflow** button and the
`browser_host_check_only` input, which skips the sign-in entirely and so needs no tenant at all. It
also runs standalone:

```powershell
./Build/build.ps1 -Task Build -BuildVersion '0.0.0'
./Tests/E2E/Test-CanaryBrowserHost.ps1
```

### Flake policy

Microsoft's sign-in service has transient bad minutes, and a canary that alerts on one of them gets
muted by its audience — the only failure mode worse than having no canary. So each scenario runs, and on
failure waits 120 seconds and runs **once** more. The job fails only if a scenario fails twice. A
first attempt that the retry cleared is still reported as a warning annotation, so flakes stay
visible. Every failed assertion in the report is prefixed with the scenario it came from.

### Notification

Scheduled-workflow failure mail goes to whoever last touched the file and is easy to miss. Instead, a
double failure opens an issue titled **"Entra sign-in canary is failing"**, labelled `canary`,
carrying the diagnostic and a link to the run; a later green run comments on it and closes it. It
uses the built-in `GITHUB_TOKEN`, so there is no extra secret.

The alert step is gated on the canary having reached a verdict, not merely on the job having failed —
a checkout or build failure must not file an issue claiming Microsoft changed its sign-in page.

Secret values are masked with `::add-mask::` before anything else runs, and the issue body is passed
through a second literal replacement of all four values, because that text is about to become public.

## When the canary goes red

1. **Read the diagnostic in the issue.** It is what `Switch-ToManualLogin` emitted, and it names the
   state, the elements that were expected but absent, the ones that were present, and the page path.
2. **Decide which failure it is.** The canary asserts several things separately, on purpose. Read
   them together — the combination is what names the cause, and no single one of them means
   "Microsoft changed the sign-in page" on its own:
   - *"Signed in with the credential, without falling back to manual entry"* failed **and a
     `Switch-ToManualLogin` diagnostic is in the report** → a selector broke. This is the one the
     canary exists for. Note that the assertion rests on whether the sign-in actually completed
     rather than on catching the warning: nobody is at this browser, so if autofill stops filling
     fields the sign-in simply never finishes. The diagnostic enriches that verdict; it does not
     carry it.
   - The same assertion failed **with no diagnostic, and "Actually travelled through Entra and back"
     failed with 0** → the sign-in never reached Microsoft, so the selector table is ruled out
     entirely. Read the error text. Issue #79 was exactly this: a console-handle bug in
     `Start-WebView2Login` failed the sign-in in 142 ms, before a browser window existed, and the
     alert nonetheless sent its reader to the selector table. Both the assertion message and the
     alert body now decide their wording from the evidence instead.
   - *"Did not report a selector it no longer recognizes"* failed on its own → the sign-in completed
     but the module still reported a page it did not recognise. Worth reading: something changed that
     the automation recovered from.
   - *"Was not refused by Entra ID"* failed → tenant configuration, not Microsoft. An OAuth error code
     is reported: a disabled account, an expired password, a Conditional Access block, or consent
     that was revoked.
   - *"Actually travelled through Entra and back"* failed → the browser never reached Entra. Look at
     the runner and the listener, not at the selector table.
   - The trace stops at *"Failed to start CoreWebView2Environment"* → no browser was ever created, so
     nothing downstream of it ran and every assertion in that scenario failed for the one reason.
     Read the line after it: since [#90](https://github.com/Fortigi/OmadaWeb.PS/issues/90)
     `Start-WebView2Login` prints why. `Cannot change thread mode after it is set
     (RPC_E_CHANGED_MODE)` means the sign-in was driven from a multi-threaded apartment — a
     PowerShell background job, or a runspace created without `ApartmentState.STA` — which WebView2
     cannot live in; the two watched scenarios are driven from a `-STA` child process for exactly
     this reason, see `Tests/E2E/Start-WatchedSignIn.ps1`. Anything else there is the runner or the
     WebView2 runtime, and the selector table is ruled out either way.
   - The **browser host check** failed instead, and no issue was filed → the runner could not open a
     window at all. Nothing about the sign-in page is implicated.
3. **Fix a selector break** by updating `$Script:EntraSignInElementId` in
   `OmadaWeb.PS/OmadaWeb.PS.psm1`. That table is read both by the script that reads the page and by
   the rules that judge it, so it is a one-line change — see
   [#32](https://github.com/Fortigi/OmadaWeb.PS/issues/32) and
   [#30](https://github.com/Fortigi/OmadaWeb.PS/issues/30).
4. **Re-run the workflow** from the Actions tab. A green run closes the issue by itself.

## The service-principal canary

Unattended authentication — `-AuthenticationType OAuth`, the client-credentials grant that scheduled
tasks, containers and CI pipelines use. It is the one part of the module with nobody in front of it,
so a break is discovered by a job that quietly stopped running.

### Why a unit test is not enough

`New-OAuthClientAssertion` signs an RS256 JWT carrying `x5t`, `aud`, `iss`, `sub`, `jti` and `exp`.
`Tests/Unit/Invoke-OAuth2Authentication.Tests.ps1` and `Tests/Unit/Get-OAuthClientCertificate.Tests.ps1`
cover how it is built, but they mock `Invoke-RestMethod` — and **a mock accepts any JWT**. Only
Microsoft can reject a bad one. The same goes for everything around it: a certificate credential
Entra will not take, a scope that resolves to nothing, a client holding no application role.

### The assertion everything rests on

The canary asserts against the token that actually arrived at the resource, which
`Tests/E2E/Start-CanaryRelyingParty.ps1` records as `ResourceBearer`. Two reasons:

- **The stand-in authorizes nothing.** It answers `200` to any `/api/*` request, credential or not,
  because it is a loopback listener and not Omada. "The request succeeded" therefore says nothing
  about what was presented.
- **It is the regression guard for [#102](https://github.com/Fortigi/OmadaWeb.PS/issues/102).** Until
  that was fixed, a failed token request fell through to `Authorization: Bearer ` and the user saw an
  unexplained 401 from Omada instead of the identity provider's error. `Invoke-OAuthTokenRequest` now
  stops on error and `New-OAuthTokenRequestError` re-throws carrying the `AADSTS` code, so the
  empty-bearer case should no longer be reachable — and this is what keeps that a fact rather than an
  assumption.

### The tenant is shaped like a customer's

Omada's [OAuth documentation](https://documentation.omadaidentity.com/docs/getting-started/authentication-sso/oauth/)
describes **two** app registrations, and `New-EntraCanaryConfiguration.ps1` creates the same two:

1. **The resource** — the stand-in for the OpenID Connect application Omada is configured with. It
   carries the Application ID URI (`api://<application id>`, the on-premises form; Identity Cloud
   uses the Omada host name instead), exposes the application role, and sets
   `requestedAccessTokenVersion` to 2.
2. **The OAuth client** — a separate confidential registration holding the credentials, because
   Omada is explicit that the OIDC registration "cannot be used with client secret grants, i.e., one
   new application registration must be created per client application that connects to ES".

The client is granted the resource's application role. That grant is not decoration: without it Entra
either refuses the token or, where the resource does not require assignment, issues one carrying no
roles at all — which authenticates nothing at Omada. The canary asserts the role is in the token so
those two cases cannot be confused.

The claims checked are the ones Omada's own documentation tells an administrator to verify:
**`aud` is the OIDC application** and **`azp` is the OAuth client**.

**Not covered:** Omada maps the service principal to an Omada user whose *Username* is the client id,
in the *Impersonation service users* group. That is Omada-side configuration and the canary has no
Omada environment — the same loopback stand-in used by the sign-in canary serves the resource here.

### The four scenarios

One per credential form the module documents. They are separate runs because supplying two
credentials at once means only one is under test: given both, the module uses the certificate and
warns that it ignored the secret.

| Scenario | Credential |
|---|---|
| `OAuthClientSecret` | `-Credential` holding the client id and secret |
| `OAuthCertificateStore` | `-OAuthCertificateThumbprint`, from `CurrentUser\My` |
| `OAuthCertificateFile` | `-OAuthCertificatePath` — what a container or a store-less account uses |
| `OAuthCertificateObject` | `-OAuthCertificate`, a certificate the caller already holds |

A scenario whose credential is not stored is simply not run, so a tenant provisioned with only one of
the two still exercises what it has.

### Its secrets

Alongside `CANARY_TENANT_ID` in the same `entra-canary` environment:

| Secret | Contains |
|---|---|
| `CANARY_SP_CLIENT_ID` | Application (client) id of the OAuth client |
| `CANARY_SP_CLIENT_SECRET` | Its client secret |
| `CANARY_SP_CERT_PFX_BASE64` | The client certificate as a base64 PKCS#12 file |
| `CANARY_SP_CERT_PASSWORD` | That file's password |
| `CANARY_SP_RESOURCE_URI` | The resource's Application ID URI — passed as `-EntraApplicationIdUri` |
| `CANARY_SP_RESOURCE_CLIENT_ID` | The resource's client id — the expected `aud` |
| `CANARY_SP_APP_ROLE` | The application role value expected in `roles` |
| `CANARY_SP_SECRET_EXPIRY` | When the client secret expires, for the warning below |

### Rotation, and hearing about it first

Both credentials expire. The job reads the certificate's `notAfter` from the PFX it already holds and
the secret's expiry from `CANARY_SP_SECRET_EXPIRY`, and emits a **warning annotation below 30 days** —
so rotation happens before a red run rather than because of one.

Rotating is a deliberate switch rather than something every run does, because a secret's value can be
read only at creation: rotating without `-GitHubRepository` would invalidate the credential GitHub is
holding and hand the replacement to nobody.

```powershell
./Build/New-EntraCanaryConfiguration.ps1 -RotateServicePrincipalCredential -GitHubRepository 'Fortigi/OmadaWeb.PS'
```

`-SkipServicePrincipalCanary` provisions the sign-in canary alone. Granting the application role
needs the `AppRoleAssignment.ReadWrite.All` Graph scope on top of the ones the sign-in canary uses.

### When it goes red

**Never a sign-in page change** — no browser is involved anywhere in this job.

- **An `AADSTS` code is reported** → Entra answered and refused, so this is the tenant and not the
  module. `AADSTS7000222` is an expired client secret, `AADSTS700027` an expired or unregistered
  certificate; both are fixed by rotating. Others: a revoked grant, a disabled service principal.
- **"Presented a bearer token at the resource" failed with no `AADSTS` code** → the token request
  failed some other way, or a request reached the resource carrying no token — the regression #102
  fixed. The stand-in answers `200` either way, so the status code proves nothing on its own; read
  the diagnostic.
- **"Carried the application role granted to the client" failed on its own** → a token was issued but
  the app-role grant is missing or was never consented. Re-run the provisioning script.
- **"Was issued a token the way Omada expects one" failed on `ver`** → `requestedAccessTokenVersion`
  on the resource registration is no longer 2, so the claims are v1 and differ from the ones Omada
  documents.
- **"Authenticated the client with the certificate rather than a secret" failed** → the module did not
  report signing an assertion with the expected certificate. This is the one that points at the
  module's own signing path.

## Running it locally

```powershell
$env:OMADAWEBPS_CANARY_TENANT_ID = '<tenant id>'
$env:OMADAWEBPS_CANARY_CLIENT_ID = '<application id>'
$env:OMADAWEBPS_CANARY_USERNAME  = '<canary upn>'
$env:OMADAWEBPS_CANARY_PASSWORD  = '<password>'

Invoke-Pester -Path ./Tests/E2E -TagFilter E2E -Output Detailed
```

That runs the `PasswordAutofill` scenario, which is the default. For one of the others, pass it
through the container the way the workflow does:

```powershell
$Container = New-PesterContainer -Path ./Tests/E2E/EntraSignInCanary.Tests.ps1 -Data @{
    ModulePath = './buildoutput/OmadaWeb.PS/OmadaWeb.PS.psm1'
    Scenario   = 'UserNameOnly'
}
Invoke-Pester -Container $Container -TagFilter E2E -Output Detailed
```

A local run of `UserNameOnly` or `NoUserName` is worth watching rather than only reading: the browser
window opens, stops where a person would take over, and stays there until the observation window ends
— which is the behaviour being asserted.

The service-principal canary reads its own variables and opens no window, so a run of it finishes in
seconds:

```powershell
$env:OMADAWEBPS_CANARY_TENANT_ID           = '<tenant id>'
$env:OMADAWEBPS_CANARY_SP_CLIENT_ID        = '<oauth client id>'
$env:OMADAWEBPS_CANARY_SP_CLIENT_SECRET    = '<client secret>'
$env:OMADAWEBPS_CANARY_SP_CERT_PFX_BASE64  = '<base64 pfx>'
$env:OMADAWEBPS_CANARY_SP_CERT_PASSWORD    = '<pfx password>'
$env:OMADAWEBPS_CANARY_SP_RESOURCE_URI     = 'api://<resource application id>'
$env:OMADAWEBPS_CANARY_SP_RESOURCE_CLIENT_ID = '<resource application id>'
$env:OMADAWEBPS_CANARY_SP_APP_ROLE         = 'OmadaWeb.Canary.Read'

$Container = New-PesterContainer -Path ./Tests/E2E/EntraServicePrincipalCanary.Tests.ps1 -Data @{
    ModulePath = './buildoutput/OmadaWeb.PS/OmadaWeb.PS.psm1'
    Scenario   = 'OAuthCertificateStore'
}
Invoke-Pester -Container $Container -TagFilter E2E -Output Detailed
```

Without those variables the tests report **skipped**, which is also what keeps them out of a normal
build. The build additionally excludes the `E2E` tag outright, so `./Build/build.ps1` never opens a
browser and never touches a tenant.

To prove the sign-in canary can actually detect a break, change one id in
`$Script:EntraSignInElementId` to something that does not exist and run it again: it should fail on
the first assertion and name that id in the diagnostic.

To prove the same of the service-principal canary, point `OMADAWEBPS_CANARY_SP_CERT_PFX_BASE64` at a
certificate Entra does not know — any self-signed one will do. It should fail naming an `AADSTS` code
rather than passing, which is also the check that the empty-bearer path cannot slip through: a failed
token request still reaches the stand-in, and the stand-in still answers `200`.
