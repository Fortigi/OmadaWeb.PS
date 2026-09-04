param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-GalleryModuleVersion' -Tag 'Unit' {
    It 'Should return the highest version in the feed' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-RestMethod {
                @(
                    [PSCustomObject]@{
                        Properties = [PSCustomObject]@{
                            version   = '1.0.0'
                            Published = [PSCustomObject]@{ '#text' = (Get-Date).AddDays(-5) }
                        }
                    }
                    [PSCustomObject]@{
                        Properties = [PSCustomObject]@{
                            version   = '2.0.0'
                            Published = [PSCustomObject]@{ '#text' = (Get-Date) }
                        }
                    }
                )
            }

            Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS' | Should -Be '2.0.0'
        }
    }

    It 'Should return the highest version rather than the most recently published one' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-RestMethod {
                @(
                    [PSCustomObject]@{
                        Properties = [PSCustomObject]@{
                            version   = '2.0.0'
                            Published = [PSCustomObject]@{ '#text' = (Get-Date).AddDays(-5) }
                        }
                    }
                    [PSCustomObject]@{
                        Properties = [PSCustomObject]@{
                            version   = '1.0.0'
                            Published = [PSCustomObject]@{ '#text' = (Get-Date) }
                        }
                    }
                )
            }

            Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS' | Should -Be '2.0.0'
        }
    }

    It 'Should return the highest stable version when the feed contains a newer prerelease' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-RestMethod {
                @(
                    [PSCustomObject]@{ Properties = [PSCustomObject]@{ version = '2026.9.1' } }
                    [PSCustomObject]@{ Properties = [PSCustomObject]@{ version = '2026.9.2-nightly74' } }
                )
            }

            Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS' | Should -Be '2026.9.1'
        }
    }

    It 'Should return the newer prerelease when prereleases are requested' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-RestMethod {
                @(
                    [PSCustomObject]@{ Properties = [PSCustomObject]@{ version = '2026.9.1' } }
                    [PSCustomObject]@{ Properties = [PSCustomObject]@{ version = '2026.9.2-nightly74' } }
                )
            }

            Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS' -IncludePrerelease | Should -Be '2026.9.2-nightly74'
        }
    }

    It 'Should prefer a stable release over an older prerelease when prereleases are requested' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-RestMethod {
                @(
                    [PSCustomObject]@{ Properties = [PSCustomObject]@{ version = '2026.9.1-nightly74' } }
                    [PSCustomObject]@{ Properties = [PSCustomObject]@{ version = '2026.9.1' } }
                )
            }

            Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS' -IncludePrerelease | Should -Be '2026.9.1'
        }
    }

    It 'Should return $null when the feed holds nothing but prereleases and stable was asked for' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-RestMethod {
                @(
                    [PSCustomObject]@{ Properties = [PSCustomObject]@{ version = '2026.9.1-nightly74' } }
                )
            }

            Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS' | Should -BeNullOrEmpty
        }
    }

    It 'Should ignore a feed entry whose version cannot be parsed' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-RestMethod {
                @(
                    [PSCustomObject]@{ Properties = [PSCustomObject]@{ version = 'unknown' } }
                    [PSCustomObject]@{ Properties = [PSCustomObject]@{ version = '2026.9.1' } }
                )
            }

            Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS' | Should -Be '2026.9.1'
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
