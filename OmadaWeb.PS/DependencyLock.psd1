<#
    Pinned versions and expected SHA-256 hashes of everything OmadaWeb.PS downloads at runtime.

    The module ships no binaries. Selenium, Newtonsoft.Json, System.Text.Json and its dependency
    closure, System.Runtime, the WebView2 assemblies and msedgedriver.exe are all downloaded to
    %LOCALAPPDATA%\OmadaWeb.PS\Bin the first time they are needed, and then loaded into the
    PowerShell session with Add-Type / Assembly.LoadFrom or executed. Without this file there is
    nothing to check those bytes against, so a compromised feed would run arbitrary code in every
    consumer's session.

    Invoke-DownloadFile refuses to fetch anything that is not listed here, and verifies every
    download before the file is expanded, copied into Bin or loaded. A mismatch aborts.

    THIS FILE IS MAINTAINED BY THE BUILD. Run Build/Update-DependencyLock.ps1 -Refresh to update it
    after a version change; Build/Update-DependencyLock.ps1 -Check runs in PR validation and fails
    the build when a hash here no longer matches what the URL serves, or when a version here has
    drifted from Build/Dependencies/Dependencies.csproj.

    Keys per artefact:
      Id             - the identifier callers pass to Invoke-DownloadFile -ArtifactId
      PackageId      - NuGet package id, and the key linking the entry to the Dependabot manifest
      Manifest       - the Build/Dependencies project this entry takes its version from
      Version        - pinned version
      Url            - the exact URL the module downloads from
      Sha256         - expected SHA-256 of the downloaded bytes, lower-case hex
      Verification   - "Sha256" (hash-pinned) or "Authenticode" (signature-verified, see below)
      Group          - artefacts installed together as one dependency closure
      TargetFramework- lib/ folder preference; "Net4OrNetStandard" picks the highest lib\net4*
                       folder and falls back to lib\netstandard2.0
      InstalledBy    - the module function that downloads it
      PinReason      - why this entry is held at a version the manifest does not track
      Description    - why the module needs it

    Verification = "Authenticode" exists for one artefact only. msedgedriver.exe has to match the
    Microsoft Edge build installed on the user's machine, so its version - and therefore its hash -
    cannot be known when this file ships. It is verified by Authenticode signature instead, against
    SubjectPattern, before it is moved into Bin.
#>
@{
    SchemaVersion = 1
    Artifacts     = @(
        @{
            Id              = "Selenium.Desktop"
            PackageId       = "Selenium.WebDriver"
            Manifest        = "Build/Dependencies/Legacy/Dependencies.Legacy.csproj"
            Version         = "4.11.0"
            Url             = "https://api.nuget.org/v3-flatcontainer/selenium.webdriver/4.11.0/selenium.webdriver.4.11.0.nupkg"
            Sha256          = "54b36d1d0bd6d460796a411db408297ce8abde57b05a384c4a1d8e9ab3150bbc"
            Verification    = "Sha256"
            Group           = ""
            TargetFramework = "Net4OrNetStandard"
            InstalledBy     = "Install-Selenium"
            PinReason       = "Selenium's .NET bindings went netstandard2.0-only from selenium-4.12.0, which Windows PowerShell 5.1 cannot load. This is the last release that still ships a net4* build, so it must not be bumped."
            Description     = "Drives Microsoft Edge for -AuthenticationType Browser on Windows PowerShell 5.1."
        }
        @{
            Id              = "Selenium.Core"
            PackageId       = "Selenium.WebDriver"
            Manifest        = "Build/Dependencies/Dependencies.csproj"
            Version         = "4.47.0"
            Url             = "https://api.nuget.org/v3-flatcontainer/selenium.webdriver/4.47.0/selenium.webdriver.4.47.0.nupkg"
            Sha256          = "1ed4e6161c5302b292a0c894d9dbb2344afb5a7cdbfce9c7aaa439ee952e06a8"
            Verification    = "Sha256"
            Group           = ""
            TargetFramework = "Net4OrNetStandard"
            InstalledBy     = "Install-Selenium"
            PinReason       = ""
            Description     = "Drives Microsoft Edge for -AuthenticationType Browser on PowerShell 7."
        }
        @{
            Id              = "Newtonsoft.Json"
            PackageId       = "Newtonsoft.Json"
            Manifest        = "Build/Dependencies/Dependencies.csproj"
            Version         = "13.0.4"
            Url             = "https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.4/newtonsoft.json.13.0.4.nupkg"
            Sha256          = "f09081d457405baf35a973fa0c50d6bf272ed683f2568c5a620a49da952f6529"
            Verification    = "Sha256"
            Group           = ""
            TargetFramework = "NetStandard"
            InstalledBy     = "Install-NewtonSoftJson"
            PinReason       = ""
            Description     = "Dependency of the Selenium bindings on Windows PowerShell 5.1."
        }
        @{
            Id              = "Microsoft.Web.WebView2"
            PackageId       = "Microsoft.Web.WebView2"
            Manifest        = "Build/Dependencies/Dependencies.csproj"
            Version         = "1.0.4129.50"
            Url             = "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/1.0.4129.50/microsoft.web.webview2.1.0.4129.50.nupkg"
            Sha256          = "d3934f482d484b89fb4825df720c710664e1143a1e90f7b3a60794ef33f473d2"
            Verification    = "Sha256"
            Group           = ""
            TargetFramework = ""
            InstalledBy     = "Install-WebView2"
            PinReason       = ""
            Description     = "Hosts the embedded sign-in browser used by the default -AuthenticationType WebView2."
        }
        @{
            Id              = "System.Text.Json"
            PackageId       = "System.Text.Json"
            Manifest        = "Build/Dependencies/Dependencies.csproj"
            Version         = "8.0.5"
            Url             = "https://api.nuget.org/v3-flatcontainer/system.text.json/8.0.5/system.text.json.8.0.5.nupkg"
            Sha256          = "c8ac68e78c39a1d593ea73ebb9456c697e77a0f45efa02b31af2e79f1b703faf"
            Verification    = "Sha256"
            Group           = "SystemTextJson"
            TargetFramework = "Net4OrNetStandard"
            InstalledBy     = "Install-SystemTextJson"
            PinReason       = "System.Text.Json 9 and later drop the net462 target Windows PowerShell 5.1 needs."
            Description     = "Dependency of the netstandard2.0 Selenium bindings on Windows PowerShell 5.1."
        }
        @{
            Id              = "Microsoft.Bcl.AsyncInterfaces"
            PackageId       = "Microsoft.Bcl.AsyncInterfaces"
            Manifest        = "Build/Dependencies/Dependencies.csproj"
            Version         = "8.0.0"
            Url             = "https://api.nuget.org/v3-flatcontainer/microsoft.bcl.asyncinterfaces/8.0.0/microsoft.bcl.asyncinterfaces.8.0.0.nupkg"
            Sha256          = "f5a5a68b03092ab2abf68843d4a4aea25dfbcbe8dd0f13c625cb779b6fc1927c"
            Verification    = "Sha256"
            Group           = "SystemTextJson"
            TargetFramework = "Net4OrNetStandard"
            InstalledBy     = "Install-SystemTextJson"
            PinReason       = "Member of the System.Text.Json dependency closure, held at the version that closure resolves. Assembly.LoadFrom applies no binding redirects, so it moves only when System.Text.Json moves; .github/dependabot.yml ignores version updates for it."
            Description     = "Transitive dependency of System.Text.Json on .NET Framework."
        }
        @{
            Id              = "System.Text.Encodings.Web"
            PackageId       = "System.Text.Encodings.Web"
            Manifest        = "Build/Dependencies/Dependencies.csproj"
            Version         = "8.0.0"
            Url             = "https://api.nuget.org/v3-flatcontainer/system.text.encodings.web/8.0.0/system.text.encodings.web.8.0.0.nupkg"
            Sha256          = "21442442457da68d4b0b442caab8a5ab03733ef9dcfb8795beafa10afabc7ef1"
            Verification    = "Sha256"
            Group           = "SystemTextJson"
            TargetFramework = "Net4OrNetStandard"
            InstalledBy     = "Install-SystemTextJson"
            PinReason       = "Member of the System.Text.Json dependency closure, held at the version that closure resolves. Assembly.LoadFrom applies no binding redirects, so it moves only when System.Text.Json moves; .github/dependabot.yml ignores version updates for it."
            Description     = "Transitive dependency of System.Text.Json on .NET Framework."
        }
        @{
            Id              = "System.Threading.Tasks.Extensions"
            PackageId       = "System.Threading.Tasks.Extensions"
            Manifest        = "Build/Dependencies/Dependencies.csproj"
            Version         = "4.5.4"
            Url             = "https://api.nuget.org/v3-flatcontainer/system.threading.tasks.extensions/4.5.4/system.threading.tasks.extensions.4.5.4.nupkg"
            Sha256          = "a304a963cc0796c5179f9c6b7d8022bbce3b2fa7c029eb6196f631f7b462d678"
            Verification    = "Sha256"
            Group           = "SystemTextJson"
            TargetFramework = "Net4OrNetStandard"
            InstalledBy     = "Install-SystemTextJson"
            PinReason       = "Member of the System.Text.Json dependency closure, held at the version that closure resolves. Assembly.LoadFrom applies no binding redirects, so it moves only when System.Text.Json moves; .github/dependabot.yml ignores version updates for it."
            Description     = "Transitive dependency of System.Text.Json on .NET Framework."
        }
        @{
            Id              = "System.Runtime.CompilerServices.Unsafe"
            PackageId       = "System.Runtime.CompilerServices.Unsafe"
            Manifest        = "Build/Dependencies/Dependencies.csproj"
            Version         = "4.5.3"
            Url             = "https://api.nuget.org/v3-flatcontainer/system.runtime.compilerservices.unsafe/4.5.3/system.runtime.compilerservices.unsafe.4.5.3.nupkg"
            Sha256          = "96764c52a44ee1161151e48ef07489f72047a851cb55b99e9f01d6908536d1a9"
            Verification    = "Sha256"
            Group           = "SystemTextJson"
            TargetFramework = "Net4OrNetStandard"
            InstalledBy     = "Install-SystemTextJson"
            PinReason       = "Member of the System.Text.Json dependency closure, held at the version that closure resolves. Assembly.LoadFrom applies no binding redirects, so it moves only when System.Text.Json moves; .github/dependabot.yml ignores version updates for it."
            Description     = "Transitive dependency of System.Text.Json on .NET Framework."
        }
        @{
            Id              = "System.Buffers"
            PackageId       = "System.Buffers"
            Manifest        = "Build/Dependencies/Dependencies.csproj"
            Version         = "4.5.1"
            Url             = "https://api.nuget.org/v3-flatcontainer/system.buffers/4.5.1/system.buffers.4.5.1.nupkg"
            Sha256          = "c30b3dd2c7e2f4cee4b823d692fd42118309b42ab1f5007f923d329a5b0d6b12"
            Verification    = "Sha256"
            Group           = "SystemTextJson"
            TargetFramework = "Net4OrNetStandard"
            InstalledBy     = "Install-SystemTextJson"
            PinReason       = "Member of the System.Text.Json dependency closure, held at the version that closure resolves. Assembly.LoadFrom applies no binding redirects, so it moves only when System.Text.Json moves; .github/dependabot.yml ignores version updates for it."
            Description     = "Transitive dependency of System.Text.Json on .NET Framework."
        }
        @{
            Id              = "System.Memory"
            PackageId       = "System.Memory"
            Manifest        = "Build/Dependencies/Dependencies.csproj"
            Version         = "4.5.5"
            Url             = "https://api.nuget.org/v3-flatcontainer/system.memory/4.5.5/system.memory.4.5.5.nupkg"
            Sha256          = "10f43da352a29fb2b3188e4edd4dcf5100194c8b526e4f61fe2e2b5623775a22"
            Verification    = "Sha256"
            Group           = "SystemTextJson"
            TargetFramework = "Net4OrNetStandard"
            InstalledBy     = "Install-SystemTextJson"
            PinReason       = "Member of the System.Text.Json dependency closure, held at the version that closure resolves. Assembly.LoadFrom applies no binding redirects, so it moves only when System.Text.Json moves; .github/dependabot.yml ignores version updates for it."
            Description     = "Transitive dependency of System.Text.Json on .NET Framework."
        }
        @{
            Id              = "System.ValueTuple"
            PackageId       = "System.ValueTuple"
            Manifest        = "Build/Dependencies/Dependencies.csproj"
            Version         = "4.5.0"
            Url             = "https://api.nuget.org/v3-flatcontainer/system.valuetuple/4.5.0/system.valuetuple.4.5.0.nupkg"
            Sha256          = "9e21fa9767d4e76bc0cee065c1d40cc34384a114bfec4d70e6c981168a926802"
            Verification    = "Sha256"
            Group           = "SystemTextJson"
            TargetFramework = "Net4OrNetStandard"
            InstalledBy     = "Install-SystemTextJson"
            PinReason       = "Member of the System.Text.Json dependency closure, held at the version that closure resolves. Assembly.LoadFrom applies no binding redirects, so it moves only when System.Text.Json moves; .github/dependabot.yml ignores version updates for it."
            Description     = "Transitive dependency of System.Text.Json on .NET Framework."
        }
        @{
            Id              = "System.Runtime"
            PackageId       = "System.Runtime"
            Manifest        = "Build/Dependencies/Dependencies.csproj"
            Version         = "4.3.1"
            Url             = "https://api.nuget.org/v3-flatcontainer/system.runtime/4.3.1/system.runtime.4.3.1.nupkg"
            Sha256          = "47d4faf00cd2d4f249eefe80473f6fa3cf2928bd5d5aa2ce00d838a64423900d"
            Verification    = "Sha256"
            Group           = "SystemRuntime"
            TargetFramework = "Net4OrNetStandard"
            InstalledBy     = "Install-SystemRunTime"
            PinReason       = ""
            Description     = "Dependency of the netstandard2.0 Selenium bindings on Windows PowerShell 5.1."
        }
        @{
            Id              = "msedgedriver"
            PackageId       = ""
            Manifest        = ""
            Version         = ""
            Url             = ""
            Sha256          = ""
            Verification    = "Authenticode"
            SubjectPattern  = "*O=Microsoft Corporation*"
            Group           = ""
            TargetFramework = ""
            InstalledBy     = "Install-EdgeDriver"
            PinReason       = "The version has to match the Microsoft Edge build installed on the machine, so it cannot be pinned or hashed ahead of time."
            Description     = "WebDriver implementation Selenium talks to for -AuthenticationType Browser."
        }
    )
}
