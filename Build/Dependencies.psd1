<#
    Inventory of everything OmadaWeb.PS loads at runtime.

    The module ships no binaries of its own - every component below is downloaded to
    %LOCALAPPDATA%\OmadaWeb.PS\Bin the first time it is needed (see OmadaWeb.PS/Private/Install-*.ps1).
    This file records what is loaded, where it comes from and under which license.

    Two other files sit next to it and must agree with it:

      OmadaWeb.PS/DependencyLock.psd1      - the pinned version and expected SHA-256 the module
                                             verifies each download against. LockId below names the
                                             artefact each component mirrors, and
                                             Tests/Unit/DependencyLock.Tests.ps1 asserts the versions
                                             match.
      Build/Dependencies/*.csproj          - the same versions as PackageReference items, which is
                                             what puts these components in GitHub's dependency graph
                                             so Dependabot can raise advisories against them.

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
      VersionStrategy  - how the version is resolved
      LockId           - the artefact in OmadaWeb.PS/DependencyLock.psd1 this mirrors, or "" when
                         the component is not downloaded by the module
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
            Version         = "4.47.0"
            VersionStrategy = "Pinned in OmadaWeb.PS/DependencyLock.psd1 and verified by SHA-256 before loading. Windows PowerShell 5.1 (Desktop) installs the separate 'Selenium.Desktop' pin, 4.11.0, because Selenium's .NET bindings went netstandard2.0-only from 4.12.0."
            LockId          = "Selenium.Core"
            Source          = "https://www.nuget.org/packages/Selenium.WebDriver"
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
            VersionStrategy = "Matched to the ProductVersion of the Microsoft Edge installation found on the machine, downloaded from https://msedgedriver.microsoft.com/<edge version>/edgedriver_<arch>.zip. It cannot be pinned or hashed ahead of time, so its Authenticode signature is verified against 'O=Microsoft Corporation' before it is used."
            LockId          = "msedgedriver"
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
            Version         = "1.0.4129.50"
            VersionStrategy = "Pinned in OmadaWeb.PS/DependencyLock.psd1 and verified by SHA-256 before loading. Test-WebView2RuntimeVersion compares the installed assemblies against that pin, so a newer WebView2 arrives with a module update."
            LockId          = "Microsoft.Web.WebView2"
            Source          = "https://www.nuget.org/packages/Microsoft.Web.WebView2"
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
            Version         = "13.0.4"
            VersionStrategy = "Pinned in OmadaWeb.PS/DependencyLock.psd1 and verified by SHA-256 before loading."
            LockId          = "Newtonsoft.Json"
            Source          = "https://www.nuget.org/packages/Newtonsoft.Json"
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
            VersionStrategy = "Pinned in OmadaWeb.PS/DependencyLock.psd1 and verified by SHA-256 before loading. Held on the 8.x line because System.Text.Json 9 and later drop the net462 target Windows PowerShell 5.1 needs."
            LockId          = "System.Text.Json"
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
            Name            = "Microsoft.Bcl.AsyncInterfaces"
            Type            = "library"
            Publisher       = "Microsoft"
            Purl            = "pkg:nuget/Microsoft.Bcl.AsyncInterfaces"
            Version         = "8.0.0"
            VersionStrategy = "Pinned in OmadaWeb.PS/DependencyLock.psd1 as part of the System.Text.Json 8.0.5 closure, and verified by SHA-256 before loading."
            LockId          = "Microsoft.Bcl.AsyncInterfaces"
            Source          = "https://www.nuget.org/packages/Microsoft.Bcl.AsyncInterfaces"
            Website         = "https://dot.net/"
            LicenseId       = "MIT"
            LicenseName     = ""
            LicenseUrl      = "https://licenses.nuget.org/MIT"
            Files           = @("Microsoft.Bcl.AsyncInterfaces.dll")
            InstalledBy     = "Install-SystemTextJson"
            Description     = "Transitive dependency of System.Text.Json on .NET Framework, loaded alongside it by Start-EdgeDriver."
        }
        @{
            Name            = "System.Text.Encodings.Web"
            Type            = "library"
            Publisher       = "Microsoft"
            Purl            = "pkg:nuget/System.Text.Encodings.Web"
            Version         = "8.0.0"
            VersionStrategy = "Pinned in OmadaWeb.PS/DependencyLock.psd1 as part of the System.Text.Json 8.0.5 closure, and verified by SHA-256 before loading."
            LockId          = "System.Text.Encodings.Web"
            Source          = "https://www.nuget.org/packages/System.Text.Encodings.Web"
            Website         = "https://dot.net/"
            LicenseId       = "MIT"
            LicenseName     = ""
            LicenseUrl      = "https://licenses.nuget.org/MIT"
            Files           = @("System.Text.Encodings.Web.dll")
            InstalledBy     = "Install-SystemTextJson"
            Description     = "Transitive dependency of System.Text.Json on .NET Framework, loaded alongside it by Start-EdgeDriver."
        }
        @{
            Name            = "System.Threading.Tasks.Extensions"
            Type            = "library"
            Publisher       = "Microsoft"
            Purl            = "pkg:nuget/System.Threading.Tasks.Extensions"
            Version         = "4.5.4"
            VersionStrategy = "Pinned in OmadaWeb.PS/DependencyLock.psd1 as part of the System.Text.Json 8.0.5 closure, and verified by SHA-256 before loading."
            LockId          = "System.Threading.Tasks.Extensions"
            Source          = "https://www.nuget.org/packages/System.Threading.Tasks.Extensions"
            Website         = "https://dot.net/"
            LicenseId       = "MIT"
            LicenseName     = ""
            LicenseUrl      = "https://licenses.nuget.org/MIT"
            Files           = @("System.Threading.Tasks.Extensions.dll")
            InstalledBy     = "Install-SystemTextJson"
            Description     = "Transitive dependency of System.Text.Json on .NET Framework, loaded alongside it by Start-EdgeDriver."
        }
        @{
            Name            = "System.Runtime.CompilerServices.Unsafe"
            Type            = "library"
            Publisher       = "Microsoft"
            Purl            = "pkg:nuget/System.Runtime.CompilerServices.Unsafe"
            Version         = "4.5.3"
            VersionStrategy = "Pinned in OmadaWeb.PS/DependencyLock.psd1 as part of the System.Text.Json 8.0.5 closure, and verified by SHA-256 before loading."
            LockId          = "System.Runtime.CompilerServices.Unsafe"
            Source          = "https://www.nuget.org/packages/System.Runtime.CompilerServices.Unsafe"
            Website         = "https://dot.net/"
            LicenseId       = "MIT"
            LicenseName     = ""
            LicenseUrl      = "https://licenses.nuget.org/MIT"
            Files           = @("System.Runtime.CompilerServices.Unsafe.dll")
            InstalledBy     = "Install-SystemTextJson"
            Description     = "Transitive dependency of System.Text.Json on .NET Framework, loaded alongside it by Start-EdgeDriver."
        }
        @{
            Name            = "System.Buffers"
            Type            = "library"
            Publisher       = "Microsoft"
            Purl            = "pkg:nuget/System.Buffers"
            Version         = "4.5.1"
            VersionStrategy = "Pinned in OmadaWeb.PS/DependencyLock.psd1 as part of the System.Text.Json 8.0.5 closure, and verified by SHA-256 before loading."
            LockId          = "System.Buffers"
            Source          = "https://www.nuget.org/packages/System.Buffers"
            Website         = "https://dot.net/"
            LicenseId       = "MIT"
            LicenseName     = ""
            LicenseUrl      = "https://licenses.nuget.org/MIT"
            Files           = @("System.Buffers.dll")
            InstalledBy     = "Install-SystemTextJson"
            Description     = "Transitive dependency of System.Text.Json on .NET Framework, loaded alongside it by Start-EdgeDriver."
        }
        @{
            Name            = "System.Memory"
            Type            = "library"
            Publisher       = "Microsoft"
            Purl            = "pkg:nuget/System.Memory"
            Version         = "4.5.5"
            VersionStrategy = "Pinned in OmadaWeb.PS/DependencyLock.psd1 as part of the System.Text.Json 8.0.5 closure, and verified by SHA-256 before loading."
            LockId          = "System.Memory"
            Source          = "https://www.nuget.org/packages/System.Memory"
            Website         = "https://dot.net/"
            LicenseId       = "MIT"
            LicenseName     = ""
            LicenseUrl      = "https://licenses.nuget.org/MIT"
            Files           = @("System.Memory.dll")
            InstalledBy     = "Install-SystemTextJson"
            Description     = "Transitive dependency of System.Text.Json on .NET Framework, loaded alongside it by Start-EdgeDriver."
        }
        @{
            Name            = "System.ValueTuple"
            Type            = "library"
            Publisher       = "Microsoft"
            Purl            = "pkg:nuget/System.ValueTuple"
            Version         = "4.5.0"
            VersionStrategy = "Pinned in OmadaWeb.PS/DependencyLock.psd1 as part of the System.Text.Json 8.0.5 closure, and verified by SHA-256 before loading."
            LockId          = "System.ValueTuple"
            Source          = "https://www.nuget.org/packages/System.ValueTuple"
            Website         = "https://dot.net/"
            LicenseId       = "MIT"
            LicenseName     = ""
            LicenseUrl      = "https://licenses.nuget.org/MIT"
            Files           = @("System.ValueTuple.dll")
            InstalledBy     = "Install-SystemTextJson"
            Description     = "Transitive dependency of System.Text.Json on .NET Framework, loaded alongside it by Start-EdgeDriver."
        }
        @{
            Name            = "System.Runtime"
            Type            = "library"
            Publisher       = "Microsoft"
            Purl            = "pkg:nuget/System.Runtime"
            Version         = "4.3.1"
            VersionStrategy = "Pinned in OmadaWeb.PS/DependencyLock.psd1 and verified by SHA-256 before loading."
            LockId          = "System.Runtime"
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
            LockId          = ""
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
