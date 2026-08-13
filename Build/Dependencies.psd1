<#
    Inventory of everything OmadaWeb.PS loads at runtime.

    The module ships no binaries of its own - every component below is downloaded to
    %LOCALAPPDATA%\OmadaWeb.PS\Bin the first time it is needed (see OmadaWeb.PS/Private/Install-*.ps1).
    Because they never pass through a package manifest, Dependabot cannot see them, so this file is
    the single place that records what is loaded, where it comes from and under which license.

    Build/New-Sbom.ps1 turns this inventory into the CycloneDX SBOM attached to each release. When a
    component's binaries are present on the build agent, the generator stamps the resolved version and
    SHA-256 hash of each file onto the component, so a release SBOM records what was actually loaded
    rather than only what was declared here.

    Keep this in sync when an Install-*.ps1 script starts fetching something new or changes a pin.

    Keys per component:
      Name             - component name, matching the upstream package name where there is one
      Type             - CycloneDX component type ("library", "application", ...)
      Publisher        - the party that publishes the component
      Purl             - package URL identifying the component, without a version qualifier
      Version          - pinned version, or "" when it is resolved at runtime
      VersionStrategy  - how the version is resolved when it is not pinned
      Source           - the URL the module downloads it from
      Website          - upstream project home page
      LicenseId        - SPDX license identifier, or "" when the license is not an SPDX one
      LicenseName      - license name, used when LicenseId is empty
      LicenseUrl       - URL of the license text
      Files            - file names installed into %LOCALAPPDATA%\OmadaWeb.PS\Bin
      InstalledBy      - the module function that downloads it
      Description      - why the module needs it
#>
@{
    Components = @(
        @{
            Name            = "Selenium.WebDriver"
            Type            = "library"
            Publisher       = "Software Freedom Conservancy"
            Purl            = "pkg:nuget/Selenium.WebDriver"
            Version         = ""
            VersionStrategy = "PowerShell 7 (Core): the newest SeleniumHQ/selenium GitHub release whose asset matches '.*dotnet.(?!strongnamed).*\.0\.zip'. Windows PowerShell 5.1 (Desktop): pinned to tag 'selenium-4.11.0', the last release that still ships a net4* build."
            Source          = "https://github.com/SeleniumHQ/selenium/releases"
            Website         = "https://www.selenium.dev/"
            LicenseId       = "Apache-2.0"
            LicenseName     = ""
            LicenseUrl      = "https://github.com/SeleniumHQ/selenium/blob/trunk/LICENSE"
            Files           = @("WebDriver.dll")
            InstalledBy     = "Install-Selenium"
            Description     = "Drives Microsoft Edge for -AuthenticationType Browser."
        }
        @{
            Name            = "msedgedriver"
            Type            = "application"
            Publisher       = "Microsoft"
            Purl            = "pkg:generic/msedgedriver"
            Version         = ""
            VersionStrategy = "Matched to the ProductVersion of the Microsoft Edge installation found on the machine, downloaded from https://msedgedriver.microsoft.com/<edge version>/edgedriver_<arch>.zip."
            Source          = "https://msedgedriver.microsoft.com/"
            Website         = "https://developer.microsoft.com/microsoft-edge/tools/webdriver/"
            LicenseId       = ""
            LicenseName     = "Microsoft WebDriver License Terms"
            LicenseUrl      = "https://developer.microsoft.com/microsoft-edge/tools/webdriver/"
            Files           = @("msedgedriver.exe")
            InstalledBy     = "Install-EdgeDriver"
            Description     = "WebDriver implementation Selenium talks to for -AuthenticationType Browser."
        }
        @{
            Name            = "Microsoft.Web.WebView2"
            Type            = "library"
            Publisher       = "Microsoft"
            Purl            = "pkg:nuget/Microsoft.Web.WebView2"
            Version         = ""
            VersionStrategy = "The newest non-prerelease version listed by the nuget.org flat-container index, re-checked once per session by Test-WebView2RuntimeVersion."
            Source          = "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2"
            Website         = "https://developer.microsoft.com/microsoft-edge/webview2"
            LicenseId       = ""
            LicenseName     = "Microsoft Software License Terms - Microsoft Edge WebView2 SDK"
            LicenseUrl      = "https://www.nuget.org/packages/Microsoft.Web.WebView2/license"
            Files           = @("Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.WinForms.dll", "Microsoft.Web.WebView2.Wpf.dll", "WebView2Loader.dll")
            InstalledBy     = "Install-WebView2"
            Description     = "Hosts the embedded sign-in browser used by the default -AuthenticationType WebView2."
        }
        @{
            Name            = "Newtonsoft.Json"
            Type            = "library"
            Publisher       = "James Newton-King"
            Purl            = "pkg:nuget/Newtonsoft.Json"
            Version         = ""
            VersionStrategy = "The newest JamesNK/Newtonsoft.Json GitHub release in the 13.x line (tag filter '13**', asset 'Json130.*.zip')."
            Source          = "https://github.com/JamesNK/Newtonsoft.Json/releases"
            Website         = "https://www.newtonsoft.com/json"
            LicenseId       = "MIT"
            LicenseName     = ""
            LicenseUrl      = "https://github.com/JamesNK/Newtonsoft.Json/blob/master/LICENSE.md"
            Files           = @("Newtonsoft.Json.dll")
            InstalledBy     = "Install-NewtonSoftJson"
            Description     = "Dependency of the Selenium bindings on Windows PowerShell 5.1."
        }
        @{
            Name            = "System.Text.Json"
            Type            = "library"
            Publisher       = "Microsoft"
            Purl            = "pkg:nuget/System.Text.Json"
            Version         = "8.0.5"
            VersionStrategy = "Pinned in Install-SystemTextJson."
            Source          = "https://www.nuget.org/packages/System.Text.Json"
            Website         = "https://dot.net/"
            LicenseId       = "MIT"
            LicenseName     = ""
            LicenseUrl      = "https://licenses.nuget.org/MIT"
            Files           = @("System.Text.Json.dll")
            InstalledBy     = "Install-SystemTextJson"
            Description     = "Dependency of the netstandard2.0 Selenium bindings on Windows PowerShell 5.1."
        }
        @{
            Name            = "System.Runtime"
            Type            = "library"
            Publisher       = "Microsoft"
            Purl            = "pkg:nuget/System.Runtime"
            Version         = ""
            VersionStrategy = "The newest version on nuget.org carrying a .NETFramework4* target."
            Source          = "https://www.nuget.org/packages/System.Runtime"
            Website         = "https://dot.net/"
            LicenseId       = "MIT"
            LicenseName     = ""
            LicenseUrl      = "https://licenses.nuget.org/MIT"
            Files           = @("System.Runtime.dll")
            InstalledBy     = "Install-SystemRunTime"
            Description     = "Dependency of the netstandard2.0 Selenium bindings on Windows PowerShell 5.1."
        }
        @{
            Name            = "Microsoft Edge WebView2 Runtime (fixed version)"
            Type            = "application"
            Publisher       = "Microsoft"
            Purl            = "pkg:generic/microsoft-edge-webview2-runtime"
            Version         = ""
            VersionStrategy = "Not downloaded by the module. Only used when an administrator has manually placed a fixed-version runtime in %LOCALAPPDATA%\OmadaWeb.PS\Bin\WebView2RunTime\<win-x86|win-x64>; otherwise the machine-wide Evergreen runtime shipped with Microsoft Edge is used."
            Source          = "https://developer.microsoft.com/microsoft-edge/webview2/"
            Website         = "https://developer.microsoft.com/microsoft-edge/webview2/"
            LicenseId       = ""
            LicenseName     = "Microsoft Software License Terms - Microsoft Edge WebView2 Runtime"
            LicenseUrl      = "https://developer.microsoft.com/microsoft-edge/webview2/"
            Files           = @("msedgewebview2.exe")
            InstalledBy     = ""
            Description     = "Browser runtime WebView2 renders the sign-in page with."
        }
    )
}
