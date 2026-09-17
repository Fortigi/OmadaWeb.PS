param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-WebEdgeDriverFramework' -Tag 'Unit' {
    It 'Should pass the resolved InstalledEdgeFileInfo through to Install-EdgeDriver' {
        InModuleScope 'OmadaWeb.PS' {
            $FakeEdgeInfo = [PSCustomObject]@{ VersionInfo = [PSCustomObject]@{ ProductVersion = '128.0.2739.33' } }

            Mock Get-Item { $FakeEdgeInfo } -ParameterFilter { $Path -eq $Script:InstalledEdgeFilePath }
            # A blanket "already there" default keeps every branch this test does not care about
            # (Selenium, Newtonsoft.Json, System.Text.Json, System.Runtime) from running for real,
            # while the more specific filter below is what actually drives Install-EdgeDriver.
            Mock Test-Path { $true }
            Mock Test-Path { $false } -ParameterFilter { $Path -eq $Script:EdgeDriverPath }
            Mock Install-EdgeDriver { $false }

            try {
                Invoke-WebEdgeDriverFramework
            }
            catch {
                # Only the call into Install-EdgeDriver is under test here; whatever this function
                # does afterwards (JSON library resolution, the final summary) is exercised by other
                # tests and is free to fail in this minimally-mocked setup without invalidating this.
            }

            Should -Invoke Install-EdgeDriver -Times 1 -Exactly -ParameterFilter { $null -ne $InstalledEdgeFileInfo }
        }
    }
}
