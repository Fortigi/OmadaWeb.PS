param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

# Evaluated during discovery so the Describe below can be skipped: the bundle is produced by the
# BundleDependencies build task and is deliberately never committed, so it only exists next to a
# built module. A source tree is recognised by the Private\ folder sitting beside the .psm1.
$Script:ModuleFolder = Split-Path $ModulePath
$Script:IsBuiltModule = -not (Test-Path (Join-Path $Script:ModuleFolder 'Private') -PathType Container)

Describe 'Bundled WebView2 assemblies' -Tag 'Unit' -Skip:(-not $Script:IsBuiltModule) {
    BeforeAll {
        $Script:ModuleFolder = Split-Path $ModulePath
        $Script:LibraryRoot = Join-Path $Script:ModuleFolder 'lib'
        $Script:NoticePath = Join-Path $Script:ModuleFolder 'ThirdPartyNotices.txt'
        $Script:RepositoryRoot = Split-Path $(Split-Path $PSScriptRoot)
        $Script:PinnedVersion = (Import-PowerShellDataFile -Path (Join-Path $Script:ModuleFolder 'DependencyLock.psd1')).Artifacts |
            Where-Object { $_.Id -eq 'Microsoft.Web.WebView2' } |
            ForEach-Object { $_.Version }

        function Get-Sha256 {
            param([string]$Path)
            return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
        }
    }

    It 'Should ship the three assemblies for every edition and architecture' {
        # All three files live together per folder because Microsoft.Web.WebView2.Core.dll P/Invokes
        # WebView2Loader.dll from its own directory.
        foreach ($Edition in @('Core', 'Desktop')) {
            foreach ($Architecture in @('win-x64', 'win-x86')) {
                $Folder = Join-Path $Script:LibraryRoot $Edition | Join-Path -ChildPath $Architecture
                foreach ($FileName in @('Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.WinForms.dll', 'WebView2Loader.dll')) {
                    $Path = Join-Path $Folder $FileName
                    Test-Path $Path -PathType Leaf | Should -BeTrue -Because "the module must be able to load '$FileName' for $Edition/$Architecture without a download"
                    (Get-Item $Path).Length | Should -BeGreaterThan 0
                }
            }
        }
    }

    It 'Should bundle the version pinned in the dependency lock' {
        $Script:PinnedVersion | Should -Not -BeNullOrEmpty
        foreach ($Assembly in (Get-ChildItem -Path $Script:LibraryRoot -Filter '*.dll' -Recurse -File)) {
            $Assembly.VersionInfo.ProductVersion | Should -Be $Script:PinnedVersion -Because "'$($Assembly.Name)' must be the pinned build, not whatever nuget.org calls latest"
        }
    }

    It 'Should take the native loader from the matching architecture' {
        # One WebView2Loader.dll per architecture, all under a folder called 'native' in the package:
        # picking by folder name alone would silently ship the same one twice.
        $Loader64 = Get-Sha256 -Path (Join-Path $Script:LibraryRoot 'Desktop\win-x64\WebView2Loader.dll')
        $Loader86 = Get-Sha256 -Path (Join-Path $Script:LibraryRoot 'Desktop\win-x86\WebView2Loader.dll')
        $Loader64 | Should -Not -Be $Loader86

        (Get-Sha256 -Path (Join-Path $Script:LibraryRoot 'Core\win-x64\WebView2Loader.dll')) | Should -Be $Loader64
        (Get-Sha256 -Path (Join-Path $Script:LibraryRoot 'Core\win-x86\WebView2Loader.dll')) | Should -Be $Loader86
    }

    It 'Should take the managed assemblies from the matching target framework' {
        # net462 for Windows PowerShell, netcoreapp3.0 for PowerShell 7. The WinForms assembly is
        # what distinguishes the two builds in the package.
        $Desktop = Get-Sha256 -Path (Join-Path $Script:LibraryRoot 'Desktop\win-x64\Microsoft.Web.WebView2.WinForms.dll')
        $Core = Get-Sha256 -Path (Join-Path $Script:LibraryRoot 'Core\win-x64\Microsoft.Web.WebView2.WinForms.dll')
        $Desktop | Should -Not -Be $Core
    }

    It 'Should not bundle the WPF assembly' {
        # Nothing in the module hosts WebView2 in WPF, and Install-WebView2 refuses -IncludeWpf while
        # bundled rather than writing into the module directory.
        @(Get-ChildItem -Path $Script:LibraryRoot -Filter 'Microsoft.Web.WebView2.Wpf.dll' -Recurse -File).Count | Should -Be 0
    }

    It 'Should reproduce the redistribution notice next to the assemblies' {
        Test-Path $Script:NoticePath -PathType Leaf | Should -BeTrue
        $Notice = Get-Content -Path $Script:NoticePath -Raw
        $Notice | Should -BeLike '*Microsoft Corporation*'
        $Notice | Should -BeLike ('*Microsoft.Web.WebView2 {0}*' -f $Script:PinnedVersion)
    }

    It 'Should declare everything it ships in the manifest and the nuspec' {
        $Manifest = Import-PowerShellDataFile -Path (Join-Path $Script:ModuleFolder 'OmadaWeb.PS.psd1')
        $Manifest.FileList | Should -Contain 'ThirdPartyNotices.txt'
        $Manifest.FileList | Should -Contain 'lib\Desktop\win-x64\Microsoft.Web.WebView2.Core.dll'
        $Manifest.FileList | Should -Contain 'lib\Core\win-x86\WebView2Loader.dll'

        $Nuspec = Get-Content -Path (Join-Path $Script:RepositoryRoot 'OmadaWeb.PS.nuspec') -Raw
        $Nuspec | Should -BeLike '*buildoutput\OmadaWeb.PS\lib\**'
        $Nuspec | Should -BeLike '*ThirdPartyNotices.txt*'
    }
}
