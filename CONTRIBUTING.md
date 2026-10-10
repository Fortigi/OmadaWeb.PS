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

## Complexity and mutation gates

Two more gates judge the code rather than the tests' pass/fail result. Both need PowerShell 7.

| Gate | Tool | Bar |
|---|---|---|
| Complexity | [PSComplexity](https://github.com/Fortigi/PSComplexity) | Every function at or under 15 cyclomatic and 15 cognitive. Functions already over that are recorded in `complexity-baseline.json` and may not get worse. |
| Mutation | [PSMutant](https://github.com/Fortigi/PSMutant) | Small faults injected into the source (`-eq` → `-ne`, `$true` → `$false`, a dropped `-not`) must make a test fail. The score must stay at or above `thresholds.break` in `psmutant.config.json`. |

On a pull request both run on **the files the pull request changed only**, after the tests, on the
pwsh leg of `/validate`. Touching a file means it has to meet the bar as a whole - so improving the
tests of an older file you touch may be part of the change. Every week both run on the whole tree
(`.github/workflows/quality-weekly.yml`) and file a `bug` labelled `quality-gate` when either is
below the bar; the issue closes itself once the gate passes again.

```powershell
# What the pull request runs (PR_CHANGED_FILES unset: diffs against the merge base with origin/main)
./Build/build.ps1 -Task QualityChanged

# What the weekly run does
./Build/build.ps1 -Task Complexity
./Build/build.ps1 -Task Mutate
```

Three files are part of the gates and are reviewed like code:

- **`psmutant.config.json`** maps each source file to the test files that cover it. The map is
  generated - a source file is covered by every test file that names one of its functions - and a
  pull request fails while it is stale. After adding a function, a source file or a test file, run
  `./Build/Update-MutationConfig.ps1 -Update` and commit the result. Source files that no test
  names are listed under `_untested` and are not mutated at all.
- **`complexity-baseline.json`** only ratchets down. When you simplify a recorded function the gate
  fails until its entry is lowered: run
  `Test-PSComplexity -Path ./OmadaWeb.PS -Recurse -BaselineFile ./complexity-baseline.json -UpdateBaseline`
  and commit the result. It refuses to record a function that got worse.
- **`equivalents`** in `psmutant.config.json` is for a surviving mutant that provably cannot change
  behaviour. Declare it with its reason; the run fails if a declared mutant is ever killed or no
  longer exists.

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
