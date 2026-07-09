param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaShortHash' -Tag 'Unit' {
    It 'Should return the same hash for the same input' {
        InModuleScope 'OmadaWeb.PS' {
            (Get-OmadaShortHash -Value 'example.omada.cloud::webview2::') | Should -Be (Get-OmadaShortHash -Value 'example.omada.cloud::webview2::')
        }
    }

    It 'Should return different hashes for different inputs' {
        InModuleScope 'OmadaWeb.PS' {
            (Get-OmadaShortHash -Value 'a') | Should -Not -Be (Get-OmadaShortHash -Value 'b')
        }
    }

    It 'Should return a 32-character hex string with no dashes' {
        InModuleScope 'OmadaWeb.PS' {
            $Hash = Get-OmadaShortHash -Value 'example.omada.cloud::webview2::'
            $Hash.Length | Should -Be 32
            $Hash | Should -Not -BeLike '*-*'
            $Hash | Should -Match '^[0-9a-f]{32}$'
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
