param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Install-Selenium, Install-NewtonSoftJson, Install-SystemTextJson and Install-SystemRunTime error paths' -Tag 'Unit' {
    It 'Should report the real WebDriver folder for <FunctionName> without a StrictMode error' -ForEach @(
        @{ FunctionName = 'Install-Selenium'; DllFileName = 'WebDriver.dll' }
        @{ FunctionName = 'Install-NewtonSoftJson'; DllFileName = 'Newtonsoft.Json.dll' }
        @{ FunctionName = 'Install-SystemTextJson'; DllFileName = 'System.Text.Json.dll' }
        @{ FunctionName = 'Install-SystemRunTime'; DllFileName = 'System.Runtime.dll' }
    ) {
        $BinFolder = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $BinFolder -Force | Out-Null
        Set-Content -Path (Join-Path $BinFolder $DllFileName) -Value 'existing' -NoNewline

        $CapturedWarning = InModuleScope 'OmadaWeb.PS' -Parameters @{ BinFolder = $BinFolder; FunctionName = $FunctionName } {
            $Script:WebDriverPath = Join-Path $BinFolder 'WebDriver.dll'
            $LocalWarning = $null
            try {
                & $FunctionName -WarningVariable LocalWarning -WarningAction SilentlyContinue 3>$null
            }
            catch {
                # The pre-existing early-return guard uses a bare 'break' outside a loop, which the
                # call operator surfaces as a script-terminating exception; that control-flow quirk
                # is not part of this fix and is swallowed here so the warning text can be asserted.
            }

            return $LocalWarning
        }

        # If the message still referenced the undefined $WebDriverBasePath, building it under
        # StrictMode would throw before Write-Warning ever ran, and $CapturedWarning would be empty.
        $CapturedWarning | Should -Not -BeNullOrEmpty
        $CapturedWarning | Should -Match ([regex]::Escape($BinFolder))
    }
}

Describe 'Install-NewtonSoftJson and Install-Selenium reuse-current-version warnings' -Tag 'Unit' {
    It 'Should name the real folder when copying Newtonsoft.Json.dll fails after it was already written' {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ TestDrive = $TestDrive } {
            $OriginalWebDriverPath = $Script:WebDriverPath
            $OriginalNewtonsoftJsonPath = $Script:NewtonsoftJsonPath
            try {
                # No DLL is pre-created: the early-return guard (Install-NewtonSoftJson.ps1:8) checks
                # the exact same path the catch does, so pre-creating it would leave via that guard's
                # 'break' before the download/copy logic - and Get-ChildItem - ever ran, which is
                # exactly what defeated the previous attempt at this test. The "already exists" state
                # the catch checks for can only come from the copy itself having produced the file.
                $BinFolder = Join-Path $TestDrive 'newtonsoft-copy-fails'
                New-Item -ItemType Directory -Path $BinFolder -Force | Out-Null
                $Script:WebDriverPath = Join-Path $BinFolder 'WebDriver.dll'
                $Script:NewtonsoftJsonPath = Join-Path $BinFolder 'Newtonsoft.Json.dll'

                # A real library folder with a real dummy DLL in it, so the real (unmocked)
                # Get-ChildItem genuinely finds something to pipe into Copy-Item.
                $LibraryFolder = Join-Path $TestDrive 'newtonsoft-library'
                New-Item -ItemType Directory -Path $LibraryFolder -Force | Out-Null
                Set-Content -Path (Join-Path $LibraryFolder 'Newtonsoft.Json.dll') -Value 'fake dll bytes' -NoNewline

                # Expand-DownloadFile's own ValidateScript still runs even though it is mocked below,
                # so this has to be a real, existing file.
                $DownloadedTempFile = Join-Path $TestDrive 'newtonsoft-download.tmp'
                Set-Content -Path $DownloadedTempFile -Value 'fake zip bytes' -NoNewline

                Mock Get-LockedArtifact { [pscustomobject]@{ PackageId = 'Newtonsoft.Json'; Version = '1.0.0'; TargetFramework = 'Net4OrNetStandard' } }
                Mock Invoke-DownloadFile { $DownloadedTempFile }
                Mock Expand-DownloadFile { Get-Item -LiteralPath $LibraryFolder }
                Mock Get-NuGetLibraryFolder { Get-Item -LiteralPath $LibraryFolder }
                # Copy-Item is the only step under test that is mocked - Get-ChildItem runs for real.
                # It leaves the destination DLL behind (the shape a copy that then got interrupted -
                # "being used by another process" - would leave) and then fails, which is exactly
                # what the catch's own Test-Path is checking for.
                Mock Copy-Item {
                    New-Item -ItemType File -Force -Path (Join-Path (Split-Path $Script:WebDriverPath) 'Newtonsoft.Json.dll') | Out-Null
                    throw 'The process cannot access the file because it is being used by another process.'
                }

                $CapturedWarnings = $null
                $ReturnValue = Install-NewtonSoftJson -WarningVariable CapturedWarnings -WarningAction SilentlyContinue

                $ReturnValue | Should -Be $false
                $CapturedWarnings | Should -HaveCount 1
                $CapturedWarnings[0] | Should -Match 'Reuse current version'
                $CapturedWarnings[0] | Should -Match ([regex]::Escape($BinFolder))
                Should -Invoke Copy-Item -Times 1 -Exactly
            }
            finally {
                $Script:WebDriverPath = $OriginalWebDriverPath
                $Script:NewtonsoftJsonPath = $OriginalNewtonsoftJsonPath
            }
        }
    }

    It 'Should name the real folder when copying WebDriver.dll fails after it was already written' {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ TestDrive = $TestDrive } {
            $OriginalWebDriverPath = $Script:WebDriverPath
            try {
                # Same reasoning as the Newtonsoft.Json test above: no DLL is pre-created, since
                # Install-Selenium.ps1:9's early-return guard checks the identical path.
                $BinFolder = Join-Path $TestDrive 'selenium-copy-fails'
                New-Item -ItemType Directory -Path $BinFolder -Force | Out-Null
                $Script:WebDriverPath = Join-Path $BinFolder 'WebDriver.dll'

                $LibraryFolder = Join-Path $TestDrive 'selenium-library'
                New-Item -ItemType Directory -Path $LibraryFolder -Force | Out-Null
                Set-Content -Path (Join-Path $LibraryFolder 'Selenium.WebDriver.dll') -Value 'fake dll bytes' -NoNewline

                $DownloadedTempFile = Join-Path $TestDrive 'selenium-download.tmp'
                Set-Content -Path $DownloadedTempFile -Value 'fake zip bytes' -NoNewline

                Mock Get-LockedArtifact { [pscustomobject]@{ PackageId = 'Selenium.WebDriver'; Version = '1.0.0'; TargetFramework = 'Net4OrNetStandard' } }
                Mock Invoke-DownloadFile { $DownloadedTempFile }
                Mock Expand-DownloadFile { Get-Item -LiteralPath $LibraryFolder }
                Mock Get-NuGetLibraryFolder { Get-Item -LiteralPath $LibraryFolder }
                # Selenium copies straight to $Script:WebDriverPath (no separate folder join), unlike
                # Newtonsoft.Json's Copy-Item -Destination (Split-Path ...) above.
                Mock Copy-Item {
                    New-Item -ItemType File -Force -Path $Script:WebDriverPath | Out-Null
                    throw 'The process cannot access the file because it is being used by another process.'
                }

                $CapturedWarnings = $null
                $ReturnValue = Install-Selenium -WarningVariable CapturedWarnings -WarningAction SilentlyContinue

                $ReturnValue | Should -Be $false
                $CapturedWarnings | Should -HaveCount 1
                $CapturedWarnings[0] | Should -Match 'Reuse current version'
                $CapturedWarnings[0] | Should -Match ([regex]::Escape($BinFolder))
                Should -Invoke Copy-Item -Times 1 -Exactly
            }
            finally {
                $Script:WebDriverPath = $OriginalWebDriverPath
            }
        }
    }
}
