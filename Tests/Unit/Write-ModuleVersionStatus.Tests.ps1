param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Write-ModuleVersionStatus' -Tag 'Unit' {
    It 'Should still warn that the installation is outdated when the newest gallery package is a prerelease' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Get-GalleryModuleVersion {
                if ($IncludePrerelease) { '2026.9.1-nightly74' } else { '2026.9.1' }
            }

            $Warnings = @()
            Write-ModuleVersionStatus -ModuleName 'OmadaWeb.PS' -InstalledModule @{
                Version     = '2026.8.1'
                FullVersion = '2026.8.1'
                Prerelease  = $null
            } -WarningVariable Warnings -WarningAction SilentlyContinue

            $Warnings.Count | Should -Be 1
            $Warnings[0].Message | Should -BeLike '*is outdated*2026.9.1*'
        }
    }

    It 'Should keep a prerelease on the gallery invisible to a stable installation' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Get-GalleryModuleVersion {
                if ($IncludePrerelease) { '2026.9.2-nightly74' } else { '2026.9.1' }
            }

            $Warnings = @()
            Write-ModuleVersionStatus -ModuleName 'OmadaWeb.PS' -InstalledModule @{
                Version     = '2026.9.1'
                FullVersion = '2026.9.1'
                Prerelease  = $null
            } -WarningVariable Warnings -WarningAction SilentlyContinue

            $Warnings.Count | Should -Be 0
            Should -Invoke Get-GalleryModuleVersion -ParameterFilter { -not $IncludePrerelease }
        }
    }

    It 'Should compare a prerelease installation against prereleases as well' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Get-GalleryModuleVersion {
                if ($IncludePrerelease) { '2026.9.1-nightly74' } else { '2026.8.1' }
            }

            $Warnings = @()
            Write-ModuleVersionStatus -ModuleName 'OmadaWeb.PS' -InstalledModule @{
                Version     = '2026.9.1'
                FullVersion = '2026.9.1-nightly9'
                Prerelease  = 'nightly9'
            } -WarningVariable Warnings -WarningAction SilentlyContinue

            $Warnings.Count | Should -Be 1
            $Warnings[0].Message | Should -BeLike '*2026.9.1-nightly9*is outdated*2026.9.1-nightly74*'
            Should -Invoke Get-GalleryModuleVersion -ParameterFilter { $IncludePrerelease }
        }
    }

    It 'Should warn when the installed version is newer than the gallery version' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Get-GalleryModuleVersion { '2026.8.1' }

            $Warnings = @()
            Write-ModuleVersionStatus -ModuleName 'OmadaWeb.PS' -InstalledModule @{
                Version     = '2026.9.1'
                FullVersion = '2026.9.1'
                Prerelease  = $null
            } -WarningVariable Warnings -WarningAction SilentlyContinue

            $Warnings.Count | Should -Be 1
            $Warnings[0].Message | Should -BeLike '*is newer than the gallery version*'
        }
    }

    It 'Should say why it skipped when the gallery version could not be determined' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Get-GalleryModuleVersion { $null }

            $Warnings = @()
            $VerboseMessages = @()
            Write-ModuleVersionStatus -ModuleName 'OmadaWeb.PS' -InstalledModule @{
                Version     = '2026.9.1'
                FullVersion = '2026.9.1'
                Prerelease  = $null
            } -WarningVariable Warnings -WarningAction SilentlyContinue -Verbose 4>&1 | ForEach-Object { $VerboseMessages += $_ }

            $Warnings.Count | Should -Be 0
            ($VerboseMessages -join "`n") | Should -BeLike '*PowerShell Gallery*'
        }
    }

    It 'Should skip without warning when a version cannot be compared' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Get-GalleryModuleVersion { 'latest' }

            $Warnings = @()
            { Write-ModuleVersionStatus -ModuleName 'OmadaWeb.PS' -InstalledModule @{
                    Version     = '2026.9.1'
                    FullVersion = '2026.9.1'
                    Prerelease  = $null
                } -WarningVariable Warnings -WarningAction SilentlyContinue } | Should -Not -Throw

            $Warnings.Count | Should -Be 0
        }
    }

    It 'Should fall back to the numeric version when no full version was supplied' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Get-GalleryModuleVersion { '2026.9.1' }

            $Warnings = @()
            Write-ModuleVersionStatus -ModuleName 'OmadaWeb.PS' -InstalledModule @{
                Version = '2026.8.1'
            } -WarningVariable Warnings -WarningAction SilentlyContinue

            $Warnings.Count | Should -Be 1
            $Warnings[0].Message | Should -BeLike '*2026.8.1*is outdated*'
        }
    }
}

Describe 'Get-InstalledModuleInfo' -Tag 'Unit' {
    It 'Should report the prerelease tag and the full version of a nightly installation' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Get-PSCallStack {
                [PSCustomObject]@{
                    Command    = 'OmadaWeb.PS.psm1'
                    ScriptName = 'C:\Modules\OmadaWeb.PS\2026.9.1\OmadaWeb.PS.psm1'
                }
            }
            Mock Get-Module {
                [PSCustomObject]@{
                    Name                     = 'OmadaWeb.PS'
                    Version                  = [System.Version]'2026.9.1'
                    Path                     = 'C:\Modules\OmadaWeb.PS\2026.9.1\OmadaWeb.PS.psd1'
                    RepositorySourceLocation = 'https://www.powershellgallery.com/api/v2'
                    PrivateData              = @{
                        PSData = @{
                            Prerelease = 'nightly74'
                            Tags       = @('Omada')
                        }
                    }
                }
            }

            $ModuleInfo = Get-InstalledModuleInfo -ModuleName 'OmadaWeb.PS'

            $ModuleInfo['Version'] | Should -Be ([System.Version]'2026.9.1')
            $ModuleInfo['Prerelease'] | Should -Be 'nightly74'
            $ModuleInfo['FullVersion'] | Should -Be '2026.9.1-nightly74'
            $ModuleInfo['RepositorySource'] | Should -Be 'https://www.powershellgallery.com/api/v2'
        }
    }

    It 'Should not fail on a stable installation, whose PSData has no Prerelease key' {
        InModuleScope 'OmadaWeb.PS' {
            Set-StrictMode -Version Latest
            Mock Get-PSCallStack {
                [PSCustomObject]@{
                    Command    = 'OmadaWeb.PS.psm1'
                    ScriptName = 'C:\Modules\OmadaWeb.PS\2026.9.1\OmadaWeb.PS.psm1'
                }
            }
            Mock Get-Module {
                [PSCustomObject]@{
                    Name                     = 'OmadaWeb.PS'
                    Version                  = [System.Version]'2026.9.1'
                    Path                     = 'C:\Modules\OmadaWeb.PS\2026.9.1\OmadaWeb.PS.psd1'
                    RepositorySourceLocation = 'https://www.powershellgallery.com/api/v2'
                    PrivateData              = @{
                        PSData = @{
                            Tags       = @('Omada')
                            ProjectUri = 'https://github.com/Fortigi/OmadaWeb.PS'
                        }
                    }
                }
            }

            $ModuleInfo = Get-InstalledModuleInfo -ModuleName 'OmadaWeb.PS'

            $ModuleInfo['Prerelease'] | Should -BeNullOrEmpty
            $ModuleInfo['FullVersion'] | Should -Be '2026.9.1'
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
