param(
    # Accepted for consistency with the other test files (psakeBuild.ps1 passes it to every
    # container); these tests exercise the build script and its inventory, not the built module.
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    $Script:RepositoryRoot = Split-Path $(Split-Path $PSScriptRoot)
    $Script:SbomScript = Join-Path $Script:RepositoryRoot -ChildPath 'Build\New-Sbom.ps1'
    $Script:DependencyManifest = Join-Path $Script:RepositoryRoot -ChildPath 'Build\Dependencies.psd1'
    $Script:InstallScriptFolder = Join-Path $Script:RepositoryRoot -ChildPath 'OmadaWeb.PS\Private'

    $Script:WorkFolder = Join-Path ([System.IO.Path]::GetTempPath()) ("OmadaWebSbomTests_{0}" -f ([System.Guid]::NewGuid().ToString('N')))
    $null = New-Item -Path $Script:WorkFolder -ItemType Directory -Force

    function New-TestSbom {
        param([string]$BinPath, [string]$PackagePath, [string]$Name = 'test.cdx.json')

        $OutputPath = Join-Path $Script:WorkFolder -ChildPath $Name
        $Parameter = @{
            ModuleVersion = '9.9.9.9'
            OutputPath    = $OutputPath
            BinPath       = $BinPath
            SerialNumber  = 'urn:uuid:00000000-0000-0000-0000-000000000000'
            Timestamp     = '2026-01-01T00:00:00Z'
        }
        if (-not [string]::IsNullOrWhiteSpace($PackagePath)) {
            $Parameter["PackagePath"] = $PackagePath
        }
        & $Script:SbomScript @Parameter | Out-Null
        return (Get-Content -Path $OutputPath -Raw | ConvertFrom-Json)
    }
}

Describe 'Build/Dependencies.psd1' -Tag 'Unit' {
    It 'Should declare every key New-Sbom.ps1 reads, for every component' {
        $Inventory = Import-PowerShellDataFile -Path $Script:DependencyManifest
        $Inventory.Components.Count | Should -BeGreaterThan 0
        foreach ($Component in $Inventory.Components) {
            foreach ($Key in @('Name', 'Type', 'Acquisition', 'Publisher', 'Purl', 'Version', 'VersionStrategy', 'Source', 'Website', 'LicenseId', 'LicenseName', 'LicenseUrl', 'Files', 'InstalledBy', 'Description')) {
                $Component.Keys | Should -Contain $Key -Because "component '$($Component.Name)' must declare '$Key'"
            }
            $Component.Files.Count | Should -BeGreaterThan 0 -Because "component '$($Component.Name)' must list the files it installs"
            ([string]::IsNullOrWhiteSpace($Component.LicenseId) -and [string]::IsNullOrWhiteSpace($Component.LicenseName)) |
                Should -BeFalse -Because "component '$($Component.Name)' must carry a license id or name"
        }
    }

    It 'Should say how every component reaches the user, using a value the SBOM generator knows' {
        # "bundled" is what makes the difference visible to a consumer reading the SBOM: those files
        # are inside the package and were verified at build time, the rest are fetched on first use.
        $Inventory = Import-PowerShellDataFile -Path $Script:DependencyManifest
        foreach ($Component in $Inventory.Components) {
            $Component.Acquisition | Should -BeIn @('bundled', 'runtime-download', 'user-provided') -Because "component '$($Component.Name)' must declare how it is acquired"
        }

        $WebView2 = $Inventory.Components | Where-Object { $_.Name -eq 'Microsoft.Web.WebView2' }
        $WebView2.Acquisition | Should -Be 'bundled'
    }

    It 'Should reference an Install-* function that exists in the module' {
        $Inventory = Import-PowerShellDataFile -Path $Script:DependencyManifest
        foreach ($Component in $Inventory.Components | Where-Object { -not [string]::IsNullOrWhiteSpace($_.InstalledBy) }) {
            $ScriptPath = Join-Path $Script:InstallScriptFolder -ChildPath ("{0}.ps1" -f $Component.InstalledBy)
            Test-Path $ScriptPath -PathType Leaf | Should -BeTrue -Because "component '$($Component.Name)' claims to be installed by '$($Component.InstalledBy)'"
        }
    }

    It 'Should cover every DLL and EXE the module installs into its Bin folder' {
        # Guards against an Install-*.ps1 script starting to fetch something new without the
        # inventory - and therefore the SBOM - being updated to match.
        $Inventory = Import-PowerShellDataFile -Path $Script:DependencyManifest
        $DeclaredFiles = $Inventory.Components.Files
        $InstalledFileNames = Get-ChildItem -Path $Script:InstallScriptFolder -Filter 'Install-*.ps1' |
            Select-String -Pattern '"(?<File>[A-Za-z0-9_.]+\.(dll|exe))"' -AllMatches |
            ForEach-Object { $_.Matches } |
            ForEach-Object { $_.Groups['File'].Value } |
            Sort-Object -Unique

        $InstalledFileNames.Count | Should -BeGreaterThan 0
        foreach ($FileName in $InstalledFileNames) {
            $DeclaredFiles | Should -Contain $FileName -Because "'$FileName' is installed by an Install-*.ps1 script but is not in Build/Dependencies.psd1"
        }
    }
}

Describe 'New-Sbom.ps1' -Tag 'Unit' {
    Context 'Without any binaries present' {
        BeforeAll {
            $Script:EmptyBin = Join-Path $Script:WorkFolder -ChildPath 'empty-bin'
            $null = New-Item -Path $Script:EmptyBin -ItemType Directory -Force
            $Script:Sbom = New-TestSbom -BinPath $Script:EmptyBin -Name 'empty.cdx.json'
        }

        It 'Should emit a CycloneDX 1.5 document describing the module itself' {
            $Script:Sbom.bomFormat | Should -Be 'CycloneDX'
            $Script:Sbom.specVersion | Should -Be '1.5'
            $Script:Sbom.metadata.component.name | Should -Be 'OmadaWeb.PS'
            $Script:Sbom.metadata.component.version | Should -Be '9.9.9.9'
        }

        It 'Should emit one component per inventory entry' {
            $Inventory = Import-PowerShellDataFile -Path $Script:DependencyManifest
            $Script:Sbom.components.Count | Should -Be $Inventory.Components.Count
        }

        It 'Should still list runtime-resolved components, carrying their version strategy' {
            # msedgedriver is the one component that cannot be pinned - its version has to match the
            # Edge build on the machine - so it is what "resolved at runtime" looks like now that
            # everything else carries a pin from OmadaWeb.PS/DependencyLock.psd1.
            $EdgeDriver = $Script:Sbom.components | Where-Object { $_.name -eq 'msedgedriver' }
            $EdgeDriver | Should -Not -BeNullOrEmpty
            $EdgeDriver.version | Should -BeNullOrEmpty
            ($EdgeDriver.properties | Where-Object { $_.name -eq 'omadaweb:versionStrategy' }).value | Should -Not -BeNullOrEmpty
        }

        It 'Should record the pinned version for components that are hash-verified' {
            $Selenium = $Script:Sbom.components | Where-Object { $_.name -eq 'Selenium.WebDriver' }
            $Selenium | Should -Not -BeNullOrEmpty
            $Selenium.version | Should -Not -BeNullOrEmpty -Because 'Selenium is pinned in the dependency lock so the SBOM can state which version is loaded'
            ($Selenium.properties | Where-Object { $_.name -eq 'omadaweb:versionSource' }).value | Should -Be 'declared-pin'
        }

        It 'Should use the declared pin when a component version is fixed in the module' {
            $Pinned = $Script:Sbom.components | Where-Object { $_.name -eq 'System.Text.Json' }
            $Pinned.version | Should -Be '8.0.5'
            $Pinned.purl | Should -Be 'pkg:nuget/System.Text.Json@8.0.5'
            ($Pinned.properties | Where-Object { $_.name -eq 'omadaweb:versionSource' }).value | Should -Be 'declared-pin'
        }

        It 'Should give every component a license, as an array' {
            foreach ($Component in $Script:Sbom.components) {
                $Component.licenses | Should -Not -BeNullOrEmpty -Because "component '$($Component.name)' must carry a license"
                # CycloneDX requires an array here, and a one-element array is easy to lose to
                # PowerShell's pipeline unrolling.
                ($Component.licenses -is [System.Array]) | Should -BeTrue -Because "component '$($Component.name)' must serialize 'licenses' as an array"
            }
        }

        It 'Should make the module depend on every component' {
            $RootDependency = $Script:Sbom.dependencies | Where-Object { $_.ref -eq $Script:Sbom.metadata.component.'bom-ref' }
            $RootDependency.dependsOn.Count | Should -Be $Script:Sbom.components.Count
        }

        It 'Should write UTF-8 without a byte order mark' {
            $Bytes = [System.IO.File]::ReadAllBytes((Join-Path $Script:WorkFolder -ChildPath 'empty.cdx.json'))
            ($Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) | Should -BeFalse
        }
    }

    Context 'With binaries present on disk' {
        BeforeAll {
            $Script:FilledBin = Join-Path $Script:WorkFolder -ChildPath 'filled-bin'
            $null = New-Item -Path (Join-Path $Script:FilledBin -ChildPath 'Core\win-x64') -ItemType Directory -Force
            Set-Content -Path (Join-Path $Script:FilledBin -ChildPath 'Core\WebDriver.dll') -Value 'stub' -NoNewline
            Set-Content -Path (Join-Path $Script:FilledBin -ChildPath 'Core\win-x64\WebView2Loader.dll') -Value 'stub' -NoNewline
            $Script:Sbom = New-TestSbom -BinPath $Script:FilledBin -Name 'filled.cdx.json'
        }

        It 'Should hash a single-file component that is present' {
            $Selenium = $Script:Sbom.components | Where-Object { $_.name -eq 'Selenium.WebDriver' }
            $Selenium.hashes[0].alg | Should -Be 'SHA-256'
            $Selenium.hashes[0].content | Should -Match '^[0-9a-f]{64}$'
        }

        It 'Should record each present file of a multi-file component as a property' {
            $WebView2 = $Script:Sbom.components | Where-Object { $_.name -eq 'Microsoft.Web.WebView2' }
            $InstalledFileProperties = @($WebView2.properties | Where-Object { $_.name -like 'omadaweb:installedFile:*' })
            $InstalledFileProperties.Count | Should -Be 1
            $InstalledFileProperties[0].name | Should -Be 'omadaweb:installedFile:WebView2Loader.dll'
            $InstalledFileProperties[0].value | Should -Match 'sha256=[0-9a-f]{64}'
        }

        It 'Should not hash components whose files are absent' {
            $Absent = $Script:Sbom.components | Where-Object { $_.name -eq 'msedgedriver' }
            $Absent.hashes | Should -BeNullOrEmpty
        }

        It 'Should state how each component reaches the user' {
            $WebView2 = $Script:Sbom.components | Where-Object { $_.name -eq 'Microsoft.Web.WebView2' }
            ($WebView2.properties | Where-Object { $_.name -eq 'omadaweb:acquisition' }).value | Should -Be 'bundled'

            $Selenium = $Script:Sbom.components | Where-Object { $_.name -eq 'Selenium.WebDriver' }
            ($Selenium.properties | Where-Object { $_.name -eq 'omadaweb:acquisition' }).value | Should -Be 'runtime-download'
        }
    }

    Context 'With a built package holding the bundled assemblies' {
        BeforeAll {
            # The release SBOM has to describe the bytes that shipped, so the package is searched
            # ahead of the Bin folder a warm-up step may also have filled.
            $Script:Package = Join-Path $Script:WorkFolder -ChildPath 'package'
            $null = New-Item -Path (Join-Path $Script:Package -ChildPath 'lib\Desktop\win-x64') -ItemType Directory -Force
            Set-Content -Path (Join-Path $Script:Package -ChildPath 'lib\Desktop\win-x64\Microsoft.Web.WebView2.Core.dll') -Value 'bundled-core' -NoNewline
            Set-Content -Path (Join-Path $Script:Package -ChildPath 'lib\Desktop\win-x64\WebView2Loader.dll') -Value 'bundled-loader' -NoNewline

            $Script:StaleBin = Join-Path $Script:WorkFolder -ChildPath 'stale-bin'
            $null = New-Item -Path (Join-Path $Script:StaleBin -ChildPath 'Core\win-x64') -ItemType Directory -Force
            Set-Content -Path (Join-Path $Script:StaleBin -ChildPath 'Core\win-x64\WebView2Loader.dll') -Value 'downloaded-loader' -NoNewline

            $Script:Sbom = New-TestSbom -BinPath $Script:StaleBin -PackagePath $Script:Package -Name 'bundled.cdx.json'
        }

        It 'Should hash the bundled files rather than a copy left in the Bin folder' {
            $WebView2 = $Script:Sbom.components | Where-Object { $_.name -eq 'Microsoft.Web.WebView2' }
            $Loader = @($WebView2.properties | Where-Object { $_.name -eq 'omadaweb:installedFile:WebView2Loader.dll' })
            $Loader.Count | Should -Be 1

            # SHA-256 of "bundled-loader"; the copy under Bin hashes to something else entirely.
            $Expected = (Get-FileHash -Path (Join-Path $Script:Package -ChildPath 'lib\Desktop\win-x64\WebView2Loader.dll') -Algorithm SHA256).Hash.ToLowerInvariant()
            $Loader[0].value | Should -BeLike ('*sha256={0}*' -f $Expected)
        }

        It 'Should record every bundled file of the component' {
            $WebView2 = $Script:Sbom.components | Where-Object { $_.name -eq 'Microsoft.Web.WebView2' }
            $Files = @($WebView2.properties | Where-Object { $_.name -like 'omadaweb:installedFile:*' })
            $Files.Count | Should -Be 2
            ($Files | ForEach-Object { $_.name }) | Should -Contain 'omadaweb:installedFile:Microsoft.Web.WebView2.Core.dll'
        }
    }
}

AfterAll {
    if (Test-Path $Script:WorkFolder -PathType Container) {
        Remove-Item -Path $Script:WorkFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}
