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
| Software Bill of Materials (CycloneDX) | Generated per release, see below |

## Software Bill of Materials

The module ships no binaries of its own: Selenium's `WebDriver.dll`, `Newtonsoft.Json.dll`,
`System.Text.Json.dll`, `System.Runtime.dll`, the Microsoft WebView2 assemblies and `msedgedriver.exe`
are downloaded to `%LOCALAPPDATA%\OmadaWeb.PS\Bin` on first use. Those components live outside any
package manifest, so Dependabot cannot see them.

To make them auditable, every release has a CycloneDX SBOM (`OmadaWeb.PS-<version>.cdx.json`)
attached as a release asset. It covers the module itself and every runtime-downloaded component,
including source URL, license and — for components resolved during the release build — the resolved
version and SHA-256 hash.

The inventory the SBOM is generated from is [`Build/Dependencies.psd1`](Build/Dependencies.psd1), and
it can be regenerated locally:

```powershell
./Build/New-Sbom.ps1 -ModuleVersion '2026.8.13.1' -OutputPath ./OmadaWeb.PS.cdx.json
```
