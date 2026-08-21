# Security Policy

OmadaWeb.PS is used by identity administrators to authenticate against Omada environments, so it
handles session cookies, credentials and OAuth2 tokens. Security reports are taken seriously and are
handled privately.

## Supported versions

Only the most recent version published to the [PowerShell Gallery](https://www.powershellgallery.com/packages/OmadaWeb.PS)
receives security fixes. Fixes are shipped as a new release rather than as patches to older versions.

| Version | Supported |
|---|---|
| Latest release on the PowerShell Gallery | :white_check_mark: |
| Any earlier release | :x: |

Run `Update-Module -Name OmadaWeb.PS` to move to the supported version.

## Reporting a vulnerability

**Do not open a public GitHub issue for a security problem.**

Report privately through GitHub Security Advisories:

1. Go to <https://github.com/Fortigi/OmadaWeb.PS/security/advisories/new>
2. Describe the issue and submit the draft advisory.

The report is visible only to the maintainers until an advisory is published. If GitHub is not
available to you, email `devops@fortigi.nl` with `OmadaWeb.PS security` in the subject line.

### What to include

- The module version (`Get-Module OmadaWeb.PS -ListAvailable`) and PowerShell edition/version
  (`$PSVersionTable`).
- The `-AuthenticationType` in use and whether the report involves cached cookies, browser profiles
  or the runtime-downloaded binaries.
- Steps to reproduce, ideally as a minimal command sequence.
- The impact you believe the issue has.

Please redact real tokens, cookies and credentials from anything you send.

### Response expectations

| Stage | Target |
|---|---|
| Acknowledgement of your report | 3 business days |
| Initial assessment and severity classification | 10 business days |
| Fix or documented mitigation for high/critical findings | 30 calendar days after assessment |
| Public advisory | Published together with the fix release |

If a fix takes longer than these targets, you will be told why and given a revised date. Reporters
are credited in the advisory unless they ask not to be.

We ask that you give us a reasonable opportunity to ship a fix before disclosing publicly, and that
testing is limited to environments you own or are authorized to test.

## Scope

In scope:

- The PowerShell code in this repository.
- How the module stores and protects authentication material on disk (see
  [Local data footprint](README.md#local-data-footprint) in the README).
- How the module downloads, verifies and loads its runtime dependencies.

Out of scope:

- The Omada product itself. Report those to [Omada](https://www.omadaidentity.com/) directly.
- Vulnerabilities in third-party components (Selenium, Newtonsoft.Json, WebView2, msedgedriver).
  Report those to their maintainers; if the module ships an unsafe version or configuration of one,
  that part *is* in scope, so tell us as well.
- Findings that require an attacker to already have interactive access to the user's Windows account
  under which the module runs.

## Automated security tooling

| Control | Where it is configured |
|---|---|
| Private vulnerability reporting | Repository settings — *Settings > Advanced Security > Private vulnerability reporting* |
| Secret scanning and push protection | Repository settings — *Settings > Advanced Security* |
| Dependabot version and security updates | [.github/dependabot.yml](.github/dependabot.yml) |
| Integrity verification of runtime-downloaded binaries | [OmadaWeb.PS/DependencyLock.psd1](OmadaWeb.PS/DependencyLock.psd1), see below |
| Software Bill of Materials (CycloneDX) | Generated per release, see below |

## Runtime dependency verification

The Microsoft WebView2 assemblies ship inside the module, under
`lib\<edition>\<architecture>` — see [Why the WebView2 assemblies are bundled](#why-the-webview2-assemblies-are-bundled).
Selenium's `WebDriver.dll`, `Newtonsoft.Json.dll`, `System.Text.Json.dll` and the dependencies it
needs on .NET Framework, `System.Runtime.dll` and `msedgedriver.exe` are downloaded to
`%LOCALAPPDATA%\OmadaWeb.PS\Bin` the first time they are needed, and then loaded into the PowerShell
session with `Add-Type` / `Assembly.LoadFrom`, or executed. A module built or installed without its
bundle downloads the WebView2 assemblies the same way.

That makes those downloads the module's entire binary supply chain, so each one is verified before it
is expanded, copied into `Bin` or loaded:

- **Pinned and hash-verified.** Every downloadable artefact has a pinned version, an exact download
  URL and an expected SHA-256 in [`OmadaWeb.PS/DependencyLock.psd1`](OmadaWeb.PS/DependencyLock.psd1),
  which ships with the module. `Invoke-DownloadFile` checks the downloaded bytes against that hash
  and, on a mismatch, deletes the file and aborts with an error naming the artefact and both hashes.
- **Fail closed.** An artefact with no entry in the lock file is not downloaded at all, and a
  hash-pinned artefact cannot be fetched from any URL other than its pinned one. A missing or
  unreadable lock file stops every download rather than allowing an unverified one.
- **`msedgedriver.exe` is verified by signature.** Its version has to match the Microsoft Edge build
  installed on the machine, so it cannot be pinned or hashed ahead of time. Its Authenticode
  signature is checked instead — the signature must be valid *and* issued to
  `O=Microsoft Corporation` — before the executable is moved into place.

### Keeping the pins current

Pinning would be a liability if nobody noticed a pin going stale or turning vulnerable, so the pinned
packages are declared as `PackageReference` items in [`Build/Dependencies`](Build/Dependencies). That
puts them in this repository's dependency graph, which is what makes Dependabot alerts and
security-update pull requests possible for components that are never restored from a package
manifest.

The flow after a bump — whether Dependabot proposes it or a maintainer does — is:

1. the version changes in `Build/Dependencies`;
2. the pinned hash is refreshed on that branch — either by running
   [`.github/workflows/dependency-lock-sync.yml`](.github/workflows/dependency-lock-sync.yml) from
   the Actions tab against it, or locally with the command below. It is not automatic: workflows
   triggered by Dependabot get a read-only token, and the alternative that works around that would
   hand a write-scoped token to code from the branch being reviewed;
3. PR Validation runs `Build/Update-DependencyLock.ps1 -Check`, which fails while the lock file and
   the manifests disagree, or while a pinned hash no longer matches what the URL serves.

To do it by hand:

```powershell
./Build/Update-DependencyLock.ps1 -Refresh   # repin versions and hashes from Build/Dependencies
./Build/Update-DependencyLock.ps1 -Check     # verify without changing anything
```

Two pins are deliberately held back, both recorded with a `PinReason` in the lock file:
`Selenium.WebDriver` for Windows PowerShell 5.1 stays at 4.11.0, the last release that still ships a
`net4*` build, and `System.Text.Json` stays on the 8.x line, the last one that still targets
`net462`. Both still receive advisories — the frozen Selenium pin has its own manifest under
`Build/Dependencies/Legacy` for exactly that reason — but an advisory against either needs a human
decision rather than an automatic bump.

### Why the WebView2 assemblies are bundled

`-AuthenticationType WebView2` is the default, so every user hits the WebView2 assemblies. Fetching
them at runtime had two costs that pinning does not address:

- **It fails outright without egress to nuget.org**, which is the normal state of a locked-down
  corporate machine, and there was no supported way to pre-stage the files.
- **Verification and loading were separated in time and place.** The bytes were checked at download
  time and then loaded much later, with `Assembly.LoadFrom`, out of a user-writable directory that
  nothing re-checked. Anything running as that user could swap a DLL in between, and executing from a
  user-writable path is what WDAC and AppLocker policies commonly block.

So they are fetched and hash-verified during the build instead, by
[`Build/Get-BundledDependency.ps1`](Build/Get-BundledDependency.ps1), which reuses the module's own
`Invoke-DownloadFile` and the same pin in `DependencyLock.psd1` — one verification implementation, not
two. The result ships in the package as
`lib\<Core|Desktop>\<win-x64|win-x86>\`, alongside `ThirdPartyNotices.txt` reproduced from the
package that was bundled, and loads from the module's install directory, which is usually read-only.
The binaries are not committed to this repository; the build downloads them on the runner.

The runtime download path is unchanged and still there. A module without a complete bundle — built
from source, trimmed, or imported with `-UpdateDependencies` — downloads and verifies exactly as
before. Nothing is ever copied out of the bundle into `Bin`, and the bundle itself is never written
to.

Everything else stays on the download path, deliberately:

- `msedgedriver.exe` has to match the Microsoft Edge build on the user's machine, so it cannot be
  packaged at all. It stays on the download-and-Authenticode-verify path permanently.
- Selenium and its dependency closure — 13 of the 14 locked artefacts — are retired by the
  deprecation schedule in `OmadaWeb.PS/Private/Get-OmadaDeprecationSchedule.ps1` after 2027-03-01, so
  bundling them now would be shipping payload that is about to be deleted.

The cost is package size: roughly 30 KB before, about 3.4 MB after, for every user including those
who only use `-AuthenticationType Browser`. The build prints the measured size so this stays visible.

## Software Bill of Materials

The components described under [Runtime dependency verification](#runtime-dependency-verification)
never pass through a package manifest — most are downloaded at runtime, and the bundled WebView2
assemblies are fetched by the build — so they need to be enumerated separately to be auditable.

To that end, every release has a CycloneDX SBOM (`OmadaWeb.PS-<version>.cdx.json`)
attached as a release asset. It covers the module itself, the bundled WebView2 assemblies and every
runtime-downloaded component, including source URL, license, how the component reaches the user
(`omadaweb:acquisition`, `bundled` or `runtime-download`) and — for components resolved during the
release build — the resolved version and SHA-256 hash of each file.

The inventory the SBOM is generated from is [`Build/Dependencies.psd1`](Build/Dependencies.psd1), and
it can be regenerated locally:

```powershell
./Build/New-Sbom.ps1 -ModuleVersion '2026.8.13.1' -OutputPath ./OmadaWeb.PS.cdx.json
```
