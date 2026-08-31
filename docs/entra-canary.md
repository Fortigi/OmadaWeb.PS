# The Entra sign-in canary

A scheduled GitHub Actions run that signs in to Microsoft Entra ID once a day, in a real browser,
with a real account, and fails when credential autofill stops recognizing Microsoft's sign-in
screens.

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

## What it covers, and what it deliberately does not

| | |
|---|---|
| **Covers** | The username screen, the password screen and "Stay signed in?" — the screens a password sign-in actually renders — driven by the shipping code path: `Invoke-WebView2MicrosoftLogin` over what `Get-EntraSignInProbeScript` reads and `Resolve-EntraSignInScreen` judges. |
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

`New-EntraCanaryConfiguration.ps1 -GitHubRepository <owner/repo>` writes all four through
`gh secret set` on standard input, so they never appear on a command line or on screen.

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
muted by its audience — the only failure mode worse than having no canary. So the job runs the test,
and on failure waits 120 seconds and runs it **once** more. The job fails only if both attempts fail.
A first attempt that the retry cleared is still reported as a warning annotation, so flakes stay
visible.

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
2. **Decide which failure it is.** The canary asserts several things separately, on purpose:
   - *"Still recognizes every Microsoft sign-in screen it was shown"* failed → a selector broke. This
     is the one the canary exists for.
   - *"Was not refused by Entra ID"* failed → tenant configuration, not Microsoft. An OAuth error code
     is reported: a disabled account, an expired password, a Conditional Access block, or consent
     that was revoked.
   - *"Actually travelled through Entra and back"* failed → the browser never reached Entra. Look at
     the runner and the listener, not at the selector table.
   - The **browser host check** failed instead, and no issue was filed → the runner could not open a
     window at all. Nothing about the sign-in page is implicated.
3. **Fix a selector break** by updating `$Script:EntraSignInElementId` in
   `OmadaWeb.PS/OmadaWeb.PS.psm1`. That table is read both by the script that reads the page and by
   the rules that judge it, so it is a one-line change — see
   [#32](https://github.com/Fortigi/OmadaWeb.PS/issues/32) and
   [#30](https://github.com/Fortigi/OmadaWeb.PS/issues/30).
4. **Re-run the workflow** from the Actions tab. A green run closes the issue by itself.

## Running it locally

```powershell
$env:OMADAWEBPS_CANARY_TENANT_ID = '<tenant id>'
$env:OMADAWEBPS_CANARY_CLIENT_ID = '<application id>'
$env:OMADAWEBPS_CANARY_USERNAME  = '<canary upn>'
$env:OMADAWEBPS_CANARY_PASSWORD  = '<password>'

Invoke-Pester -Path ./Tests/E2E -TagFilter E2E -Output Detailed
```

Without those variables the tests report **skipped**, which is also what keeps them out of a normal
build. The build additionally excludes the `E2E` tag outright, so `./Build/build.ps1` never opens a
browser.

To prove the canary can actually detect a break, change one id in `$Script:EntraSignInElementId` to
something that does not exist and run it again: it should fail on the first assertion and name that
id in the diagnostic.
