param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-GalleryModuleVersion' -Tag 'Unit' {
    It 'Should return the version of the most recently updated package' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-RestMethod {
                @(
                    [PSCustomObject]@{ updated = (Get-Date).AddDays(-5); Properties = [PSCustomObject]@{ version = '1.0.0' } }
                    [PSCustomObject]@{ updated = (Get-Date); Properties = [PSCustomObject]@{ version = '2.0.0' } }
                )
            }

            Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS' | Should -Be '2.0.0'
        }
    }

    It 'Should return $null when the gallery response is empty' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-RestMethod { $null }

            Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS' | Should -BeNullOrEmpty
        }
    }

    It 'Should return $null when the request fails' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-RestMethod { throw 'network error' }

            Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS' | Should -BeNullOrEmpty
        }
    }

    It 'Should request the correct PowerShell Gallery API endpoint' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-RestMethod { $null }

            Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS' | Out-Null

            Should -Invoke Invoke-RestMethod -ParameterFilter {
                $Uri -eq "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='OmadaWeb.PS'"
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
