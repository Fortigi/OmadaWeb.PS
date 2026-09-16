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

    It 'Should not leave a leaked temp file behind on the happy path' {
        # This drives the real happy path (only the network/extraction/signature/move steps are
        # mocked) so the count of files in the redirected temp folder before and after is a direct,
        # behavioural proof that the removed GetTempFileName call never ran - not merely that its
        # text is gone from the source.
        InModuleScope 'OmadaWeb.PS' -Parameters @{ TestDrive = $TestDrive } {
            $BinFolder = Join-Path $TestDrive 'edge-happy-path'
            New-Item -ItemType Directory -Path $BinFolder -Force | Out-Null
            $Script:EdgeDriverPath = Join-Path $BinFolder 'msedgedriver.exe'

            $DownloadedTempFile = Join-Path $TestDrive 'edge-happy-download.tmp'
            Set-Content -Path $DownloadedTempFile -Value 'fake zip bytes' -NoNewline

            $ExtractedFolder = Join-Path $TestDrive 'edge-happy-extracted'
            New-Item -ItemType Directory -Path $ExtractedFolder -Force | Out-Null
            $ExtractedDriverFile = Join-Path $ExtractedFolder 'msedgedriver.exe'
            Set-Content -Path $ExtractedDriverFile -Value 'fake driver' -NoNewline

            Mock Get-CimInstance { [PSCustomObject]@{ SystemType = 'x64-based PC' } }
            Mock Invoke-DownloadFile { $DownloadedTempFile }
            Mock Expand-DownloadFile { Get-Item -LiteralPath $ExtractedFolder }
            Mock Get-LockedArtifact { [PSCustomObject]@{ SubjectPattern = '*O=Microsoft Corporation*' } }
            Mock Confirm-AuthenticodeTrust { }
            Mock Move-Item { } -ParameterFilter { $Destination -eq (Split-Path $Script:EdgeDriverPath) }

            # Redirect TEMP/TMP for the duration of the call: if GetTempFileName ever ran again, it
            # would create its file here, where it can actually be counted.
            $TempFolder = Join-Path $TestDrive 'redirected-temp'
            New-Item -ItemType Directory -Path $TempFolder -Force | Out-Null
            $OriginalTemp = $Env:TEMP
            $OriginalTmp = $Env:TMP
            $Env:TEMP = $TempFolder
            $Env:TMP = $TempFolder
            try {
                # @(...) forces an array even when the folder holds 0 or exactly 1 item - under
                # StrictMode, .Count on a single non-collection object (or $null) throws
                # PropertyNotFoundException instead of just being wrong.
                $FileCountBefore = @(Get-ChildItem -Path $TempFolder -Force).Count

                Install-EdgeDriver -InstalledEdgeFileInfo ([PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ ProductVersion = '128.0.2739.33' } })

                $FileCountAfter = @(Get-ChildItem -Path $TempFolder -Force).Count
            }
            finally {
                $Env:TEMP = $OriginalTemp
                $Env:TMP = $OriginalTmp
            }

            $FileCountAfter | Should -Be $FileCountBefore
        }
    }

    It 'Should not mask the original error with an undefined-variable error when Get-CimInstance fails before the download URL is built' {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ TestDrive = $TestDrive } {
            $BinFolder = Join-Path $TestDrive 'edge-cim-fails'
            New-Item -ItemType Directory -Path $BinFolder -Force | Out-Null
            $Script:EdgeDriverPath = Join-Path $BinFolder 'msedgedriver.exe'
            Set-Content -Path $Script:EdgeDriverPath -Value 'existing driver' -NoNewline

            # Throws before $EdgeWebdriverDownloadUrl is ever assigned in the try - the scenario the
            # uninitialized-variable bug needed.
            Mock Get-CimInstance { throw 'simulated CIM failure' }

            $CaughtError = $null
            try {
                Install-EdgeDriver -InstalledEdgeFileInfo ([PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ ProductVersion = '128.0.2739.33' } }) -ErrorAction Stop
            }
            catch {
                $CaughtError = $_
            }

            $CaughtError | Should -Not -BeNullOrEmpty
            # A StrictMode "variable is not set" error would replace both of these with its own text
            # and error id, before the friendly message is ever built.
            $CaughtError.Exception.Message | Should -Match ([regex]::Escape($BinFolder))
            $CaughtError.Exception.Message | Should -Match 'simulated CIM failure'
            $CaughtError.Exception.Message | Should -Match ([regex]::Escape('(not resolved)'))
            $CaughtError.FullyQualifiedErrorId | Should -Not -Match 'VariableIsUndefined|VariableNotFound|PropertyNotFoundStrict'
        }
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

    It 'Should name the real driver folder when moving the driver into place fails and an existing driver is present' {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ TestDrive = $TestDrive } {
            $BinFolder = Join-Path $TestDrive 'edge-move-fails-existing'
            New-Item -ItemType Directory -Path $BinFolder -Force | Out-Null
            $Script:EdgeDriverPath = Join-Path $BinFolder 'msedgedriver.exe'
            # An existing driver from a previous install - the condition Move-Item's catch checks for.
            Set-Content -Path $Script:EdgeDriverPath -Value 'existing driver' -NoNewline

            $ExtractedFolder = Join-Path $TestDrive 'edge-move-fails-extracted'
            New-Item -ItemType Directory -Path $ExtractedFolder -Force | Out-Null
            Set-Content -Path (Join-Path $ExtractedFolder 'msedgedriver.exe') -Value 'fake driver' -NoNewline

            $DownloadedTempFile = Join-Path $TestDrive 'edge-move-fails-download.tmp'
            Set-Content -Path $DownloadedTempFile -Value 'fake zip bytes' -NoNewline

            Mock Get-CimInstance { [PSCustomObject]@{ SystemType = 'x64-based PC' } }
            Mock Invoke-DownloadFile { $DownloadedTempFile }
            Mock Expand-DownloadFile { Get-Item -LiteralPath $ExtractedFolder }
            Mock Get-LockedArtifact { [PSCustomObject]@{ SubjectPattern = '*O=Microsoft Corporation*' } }
            Mock Confirm-AuthenticodeTrust { }
            Mock Move-Item { throw 'simulated move failure' }

            $CaughtError = $null
            try {
                Install-EdgeDriver -InstalledEdgeFileInfo ([PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ ProductVersion = '128.0.2739.33' } }) -ErrorAction Stop
            }
            catch {
                $CaughtError = $_
            }

            $CaughtError | Should -Not -BeNullOrEmpty
            $CaughtError.Exception.Message | Should -Match ([regex]::Escape($BinFolder))
        }
    }

    It 'Should surface the original error when moving the driver fails and no existing driver is present' {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ TestDrive = $TestDrive } {
            $BinFolder = Join-Path $TestDrive 'edge-move-fails-none'
            New-Item -ItemType Directory -Path $BinFolder -Force | Out-Null
            $Script:EdgeDriverPath = Join-Path $BinFolder 'msedgedriver.exe'
            # Deliberately no existing driver at $Script:EdgeDriverPath, so the catch's Test-Path
            # check is false and $PSCmdlet.ThrowTerminatingError re-raises the original error as-is.

            $ExtractedFolder = Join-Path $TestDrive 'edge-move-fails-none-extracted'
            New-Item -ItemType Directory -Path $ExtractedFolder -Force | Out-Null
            Set-Content -Path (Join-Path $ExtractedFolder 'msedgedriver.exe') -Value 'fake driver' -NoNewline

            $DownloadedTempFile = Join-Path $TestDrive 'edge-move-fails-none-download.tmp'
            Set-Content -Path $DownloadedTempFile -Value 'fake zip bytes' -NoNewline

            Mock Get-CimInstance { [PSCustomObject]@{ SystemType = 'x64-based PC' } }
            Mock Invoke-DownloadFile { $DownloadedTempFile }
            Mock Expand-DownloadFile { Get-Item -LiteralPath $ExtractedFolder }
            Mock Get-LockedArtifact { [PSCustomObject]@{ SubjectPattern = '*O=Microsoft Corporation*' } }
            Mock Confirm-AuthenticodeTrust { }
            Mock Move-Item { throw 'simulated move failure' }

            $CaughtError = $null
            try {
                Install-EdgeDriver -InstalledEdgeFileInfo ([PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ ProductVersion = '128.0.2739.33' } }) -ErrorAction Stop
            }
            catch {
                $CaughtError = $_
            }

            $CaughtError | Should -Not -BeNullOrEmpty
            # ThrowTerminatingError re-raises the original caught error verbatim - no friendly
            # wrapper text - so the original mock exception message survives unchanged.
            $CaughtError.Exception.Message | Should -Match 'simulated move failure'
        }
    }
}
