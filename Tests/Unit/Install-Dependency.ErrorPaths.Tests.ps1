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
