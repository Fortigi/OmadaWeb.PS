param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Install-EdgeDriver' -Tag 'Unit' {
    It 'Should require -InstalledEdgeFileInfo, so the caller can never let it prompt and hang' {
        InModuleScope 'OmadaWeb.PS' {
            (Get-Command Install-EdgeDriver).Parameters['InstalledEdgeFileInfo'].Attributes.Mandatory |
                Should -Contain $true
        }
    }

    It 'Should never call GetTempFileName, so no empty temp file is left behind on every run' {
        # A leaked temp file is invisible from the outside once GetTempFileName ever ran (it is
        # immediately overwritten by the real download), so the regression is proven by the call
        # no longer being present in source rather than by an artefact left on disk.
        $SourcePath = Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\Private\Install-EdgeDriver.ps1'
        Get-Content -Path $SourcePath -Raw | Should -Not -Match 'GetTempFileName'
    }

    It 'Should name the real driver folder when the download fails, without throwing a StrictMode error' {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ TestDrive = $TestDrive } {
            $BinFolder = Join-Path $TestDrive 'edge-download-fails'
            New-Item -ItemType Directory -Path $BinFolder -Force | Out-Null
            $Script:EdgeDriverPath = Join-Path $BinFolder 'msedgedriver.exe'
            Set-Content -Path $Script:EdgeDriverPath -Value 'existing driver' -NoNewline

            Mock Get-CimInstance { [PSCustomObject]@{ SystemType = 'x64-based PC' } }
            Mock Invoke-DownloadFile { throw 'simulated network failure' }

            $CaughtError = $null
            try {
                Install-EdgeDriver -InstalledEdgeFileInfo ([PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ ProductVersion = '128.0.2739.33' } }) -ErrorAction Stop
            }
            catch {
                $CaughtError = $_
            }

            $CaughtError | Should -Not -BeNullOrEmpty
            # A StrictMode failure on an unset variable would raise a different error before the
            # message below is ever built, so matching this text proves both things at once.
            $CaughtError.Exception.Message | Should -Match ([regex]::Escape($BinFolder))
        }
    }

    It 'Should remove the extracted folder when Confirm-AuthenticodeTrust refuses the driver' {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ TestDrive = $TestDrive } {
            $BinFolder = Join-Path $TestDrive 'edge-untrusted'
            New-Item -ItemType Directory -Path $BinFolder -Force | Out-Null
            $Script:EdgeDriverPath = Join-Path $BinFolder 'msedgedriver.exe'

            $ExtractedFolder = Join-Path $TestDrive 'edge-extracted'
            New-Item -ItemType Directory -Path $ExtractedFolder -Force | Out-Null
            Set-Content -Path (Join-Path $ExtractedFolder 'msedgedriver.exe') -Value 'fake driver' -NoNewline

            # Expand-DownloadFile's own ValidateScript requires a real, existing leaf file, even
            # though the mock below never reads it.
            $DownloadedTempFile = Join-Path $TestDrive 'edge-temp-download.tmp'
            Set-Content -Path $DownloadedTempFile -Value 'fake zip bytes' -NoNewline

            Mock Get-CimInstance { [PSCustomObject]@{ SystemType = 'x64-based PC' } }
            Mock Invoke-DownloadFile { $DownloadedTempFile }
            Mock Expand-DownloadFile { Get-Item -LiteralPath $ExtractedFolder }
            Mock Get-LockedArtifact { [PSCustomObject]@{ SubjectPattern = '*O=Microsoft Corporation*' } }
            Mock Confirm-AuthenticodeTrust { throw 'untrusted signer' }

            {
                Install-EdgeDriver -InstalledEdgeFileInfo ([PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ ProductVersion = '128.0.2739.33' } }) -ErrorAction Stop
            } | Should -Throw

            Test-Path -LiteralPath $ExtractedFolder | Should -BeFalse
        }
    }
}
