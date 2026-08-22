param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Install-WebView2' -Tag 'Unit' {
    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            # The module decides between the bundled assemblies and the downloaded ones at import
            # time, so these tests set that decision themselves and put it back afterwards.
            $Script:SavedWebView2Bundled = $Script:WebView2Bundled
            $Script:SavedWebView2CorePath = $Script:WebView2CorePath
            $Script:SavedWebView2WinFormsPath = $Script:WebView2WinFormsPath
            $Script:SavedWebView2LoaderPath = $Script:WebView2LoaderPath
            $Script:SavedWebView2UpdateChecked = $Script:WebView2UpdateChecked
        }
    }

    AfterEach {
        InModuleScope 'OmadaWeb.PS' {
            $Script:WebView2Bundled = $Script:SavedWebView2Bundled
            $Script:WebView2CorePath = $Script:SavedWebView2CorePath
            $Script:WebView2WinFormsPath = $Script:SavedWebView2WinFormsPath
            $Script:WebView2LoaderPath = $Script:SavedWebView2LoaderPath
            $Script:WebView2UpdateChecked = $Script:SavedWebView2UpdateChecked
        }
    }

    Context 'When the WebView2 assemblies are bundled with the module' {
        It 'Should use the bundled assemblies without downloading anything' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:WebView2Bundled = $true
                Mock Invoke-DownloadFile { throw 'Nothing may be downloaded when the assemblies are bundled' }
                Mock Test-WebView2RuntimeVersion { throw 'The bundled version is the pinned version, so there is nothing to check' }

                Install-WebView2 | Should -BeTrue

                Should -Invoke Invoke-DownloadFile -Times 0
                # An update check would only compare the bundle against the pin it was built from,
                # and on a machine without egress it would be a pointless failure.
                Should -Invoke Test-WebView2RuntimeVersion -Times 0
            }
        }

        It 'Should not download even with -Force, because the bundle is read-only' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:WebView2Bundled = $true
                Mock Invoke-DownloadFile { throw 'Nothing may be downloaded when the assemblies are bundled' }

                Install-WebView2 -Force | Should -BeTrue

                Should -Invoke Invoke-DownloadFile -Times 0
            }
        }

        It 'Should refuse -IncludeWpf and say how to get the WPF assembly instead' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:WebView2Bundled = $true
                Mock Invoke-DownloadFile { throw 'Nothing may be downloaded when the assemblies are bundled' }

                # The WPF assembly is not bundled, and falling through to the download path would
                # write into the module's own directory.
                $Message = $null
                $Result = Install-WebView2 -IncludeWpf -ErrorAction SilentlyContinue -ErrorVariable Message

                $Result | Should -BeFalse
                "$Message" | Should -BeLike '*Microsoft.Web.WebView2.Wpf.dll*'
                "$Message" | Should -BeLike '*-UpdateDependencies*'
                Should -Invoke Invoke-DownloadFile -Times 0
            }
        }
    }

    Context 'When the module ships without a bundle' {
        It 'Should download and install into the Bin folder exactly as before' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:WebView2Bundled = $false
                $Script:WebView2UpdateChecked = $true

                $WorkFolder = Join-Path ([System.IO.Path]::GetTempPath()) ("OmadaWebInstallWebView2_{0}" -f ([System.Guid]::NewGuid().ToString('N')))
                $BinFolder = Join-Path $WorkFolder 'Bin'
                $null = New-Item -Path $BinFolder -ItemType Directory -Force

                $Script:WebView2CorePath = Join-Path $BinFolder 'Microsoft.Web.WebView2.Core.dll'
                $Script:WebView2WinFormsPath = Join-Path $BinFolder 'Microsoft.Web.WebView2.WinForms.dll'
                $Script:WebView2LoaderPath = Join-Path $BinFolder 'WebView2Loader.dll'

                # A stand-in for the extracted NuGet package, with the folder names the installer
                # selects on: one per edition, plus the per-architecture native loader.
                $PackageFolder = Join-Path $WorkFolder 'package'
                foreach ($Framework in @('net462', 'netcoreapp3.0')) {
                    $FrameworkFolder = Join-Path $PackageFolder ('lib\{0}' -f $Framework)
                    $null = New-Item -Path $FrameworkFolder -ItemType Directory -Force
                    Set-Content -Path (Join-Path $FrameworkFolder 'Microsoft.Web.WebView2.Core.dll') -Value $Framework
                    Set-Content -Path (Join-Path $FrameworkFolder 'Microsoft.Web.WebView2.WinForms.dll') -Value $Framework
                }
                foreach ($Runtime in @('win-x64', 'win-x86')) {
                    $NativeFolder = Join-Path $PackageFolder ('runtimes\{0}\native' -f $Runtime)
                    $null = New-Item -Path $NativeFolder -ItemType Directory -Force
                    Set-Content -Path (Join-Path $NativeFolder 'WebView2Loader.dll') -Value $Runtime
                }

                # Expand-DownloadFile validates that the path it is handed exists, so the stand-in
                # for the downloaded package has to be a real file even though nothing reads it.
                $PackageFile = Join-Path $WorkFolder 'package.nupkg'
                Set-Content -Path $PackageFile -Value 'not-a-real-package' -NoNewline

                Mock Test-WebView2RuntimeVersion { return $false }
                Mock Invoke-DownloadFile { return $PackageFile }
                # Expand-DownloadFile is mocked, so the fixture stands in for the extracted package.
                # The installer deletes it when it is done, which is part of what is being exercised.
                Mock Expand-DownloadFile { return $PackageFolder }

                try {
                    Install-WebView2 | Should -BeTrue

                    Should -Invoke Invoke-DownloadFile -Times 1 -ParameterFilter { $ArtifactId -eq 'Microsoft.Web.WebView2' }
                    Test-Path $Script:WebView2CorePath -PathType Leaf | Should -BeTrue
                    Test-Path $Script:WebView2WinFormsPath -PathType Leaf | Should -BeTrue
                    Test-Path $Script:WebView2LoaderPath -PathType Leaf | Should -BeTrue
                }
                finally {
                    Remove-Item -Path $WorkFolder -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
