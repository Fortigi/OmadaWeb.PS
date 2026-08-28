param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Set-OmadaCurrentBaseUrl' -Tag 'Unit' {
    BeforeEach {
        $Script:SavedBaseUrl = $Global:OmadaWebPSCurrentBaseUrl
    }

    AfterEach {
        $Global:OmadaWebPSCurrentBaseUrl = $Script:SavedBaseUrl
    }

    It 'Should set the global to the supplied base URL' {
        InModuleScope 'OmadaWeb.PS' {
            Set-OmadaCurrentBaseUrl -BaseUrl 'https://example.omada.cloud' | Out-Null

            $Global:OmadaWebPSCurrentBaseUrl | Should -Be 'https://example.omada.cloud'
        }
    }

    It 'Should return the previous value so the caller can tell whether the base URL changed' {
        InModuleScope 'OmadaWeb.PS' {
            # Invoke-OmadaRequest compares the returned value against the new one to decide whether
            # to re-probe the environment for suspension, so the read must happen before the write.
            Set-OmadaCurrentBaseUrl -BaseUrl 'https://first.omada.cloud' | Out-Null

            $Previous = Set-OmadaCurrentBaseUrl -BaseUrl 'https://second.omada.cloud'

            $Previous | Should -Be 'https://first.omada.cloud'
            $Global:OmadaWebPSCurrentBaseUrl | Should -Be 'https://second.omada.cloud'
        }
    }

    It 'Should accept null without converting it to an empty string' {
        InModuleScope 'OmadaWeb.PS' {
            # $null is the initialized-but-unset state. A [string] constraint on the parameter would
            # turn it into '', which is a different value to every -ne comparison against it.
            Set-OmadaCurrentBaseUrl -BaseUrl 'https://example.omada.cloud' | Out-Null

            Set-OmadaCurrentBaseUrl -BaseUrl $null | Out-Null

            $Global:OmadaWebPSCurrentBaseUrl | Should -BeNullOrEmpty
            $Global:OmadaWebPSCurrentBaseUrl | Should -Not -BeOfType [string]
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
