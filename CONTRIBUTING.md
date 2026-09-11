# Contributing to OmadaWeb.PS

Thanks for helping improve the module. This page covers the few things that are specific to this
repository: the one rule we ask every change to follow, where the tests live, and how a pull
request gets validated.

## Every bug fix ships with its regression test

**A pull request that fixes a bug must also add the test that would have caught it.**

Not a test that exercises the area in general — the test that fails on the code as it was, and
passes on the code as it is. Write it first if you can; if you write it afterwards, revert your
fix once and watch the test go red, so you know it is actually testing the fix.

Why this rule and not a coverage target: the bugs this module has shipped were not in the
untested-on-paper corners, they were in seams that looked obvious — a cookie written under one
filename and read under another, a `ConvertTo-Json` without `-Depth` silently truncating a request
body, a manifest field mangled on its way through a hashtable, a version cast that threw on a
prerelease tag. Each of those was a small function nobody thought needed a test. A regression test
is the cheapest way to make a fix permanent, and far cheaper to write while the failure is still
reproducible in front of you than six months later.

The same applies, in spirit, to a feature: land it with tests for the behaviour you are promising.

If a fix genuinely cannot be tested — it only reproduces against a live tenant, or inside a real
browser window — say so in the pull request and explain why, rather than leaving the reviewer to
wonder. Often the answer is a seam: `Invoke-OmadaRequest`'s 401 retry is testable precisely because
the browser is one mockable call (`Get-DataFromWebView2`) rather than something woven through the
request path.

## Where the tests live

| Location | What it holds | When to add here |
|---|---|---|
| `Tests/Unit/*.Tests.ps1` | Pester unit tests for a single function, usually via `InModuleScope 'OmadaWeb.PS'`. | Anything that is logic. Most tests belong here. |
| `Tests/Integration/*.Tests.ps1` | Tests that drive the real request path against a local `HttpListener`. | Behaviour that only appears once a real HTTP response comes back — status handling, retries, session state. |
| Tests tagged `E2E` | Sign-in against a real tenant in a real browser. | Only for the sign-in flow itself. Excluded from the build; they run on the scheduled Entra canary (`docs/entra-canary.md`). |

Three things worth knowing before you write one:

- **Tests run against the built module**, not the source tree: the build passes `-ModulePath` to
  each file pointing at `buildoutput`. Keep the `param([string]$ModulePath = ...)` header the
  existing files use, so the file works both ways.
- **Every test run enables `Set-StrictMode -Version Latest`** inside the module, and that reaches
  into `InModuleScope` blocks. Reading a variable or property that does not exist is an error, not
  `$null`.
- **Nothing may reach the network or a real tenant.** An integration test brings its own
  `HttpListener`; a unit test mocks the browser call.

## Running the tests

```powershell
# Analyzer + build + help check + tests. This is what CI runs on a pull request.
./Build/build.ps1 -Task TestBuildOnly -BuildVersion '0.0.0'

# A single file, against the source module
Invoke-Pester -Path ./Tests/Unit/OmadaCookieCache.Tests.ps1 -Output Detailed
```

PSScriptAnalyzer gates the build. The repository's PowerShell conventions are Stroustrup braces,
no aliases, full cmdlet names in correct casing, spaces around operators, and aligned hashtable
values.

If you change comment-based help or a `-HelpMessage` in `Set-DynamicParameter.ps1`, run
`Build/Update-ReadmeHelp.ps1` before committing — the README's command sections are generated, and
`Build/Test-CommentBasedHelp.ps1` fails the build when an exported command is missing help.

## Branches

| Kind | Format |
|---|---|
| Feature | `feature/<description>` |
| Bug fix | `bugfix/<description>` |
| Hotfix | `hotfix/<description>` |
| Docs | `docs/<description>` |
| Release | `release/v<major>.<minor>.<patch>.<build>[-nightly]` |

`<description>` is lowercase, words separated by hyphens or underscores. Branch from `main`.

## Pull requests

1. Open the pull request against `main`. Describe what broke or was missing, what changed, and how
   you verified it — including the judgement calls a reviewer could reasonably have made
   differently.
2. **Validation does not start on its own.** Comment `/validate` on the pull request. Post it as
   the most recent comment; a newer `/validate` supersedes an earlier run rather than racing it.
3. Resolve every review thread, automated ones included, before asking for a merge.

Please do not add AI-attribution trailers (`Co-Authored-By: Claude` and similar) to commits or
pull request descriptions.
