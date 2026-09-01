param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'ConvertTo-ModuleVersionInfo' -Tag 'Unit' {
    It 'Should split a prerelease into its numeric part and its tag' {
        InModuleScope 'OmadaWeb.PS' {
            $VersionInfo = ConvertTo-ModuleVersionInfo -Version '2026.9.1-nightly74'

            $VersionInfo.Version | Should -Be ([System.Version]'2026.9.1')
            $VersionInfo.PrereleaseTag | Should -Be 'nightly74'
            $VersionInfo.IsPrerelease | Should -BeTrue
            $VersionInfo.Original | Should -Be '2026.9.1-nightly74'
        }
    }

    It 'Should parse a four component version, which SemanticVersion cannot' {
        InModuleScope 'OmadaWeb.PS' {
            $VersionInfo = ConvertTo-ModuleVersionInfo -Version '2026.7.9.9'

            $VersionInfo.Version | Should -Be ([System.Version]'2026.7.9.9')
            $VersionInfo.IsPrerelease | Should -BeFalse
        }
    }

    It 'Should ignore build metadata, which carries no precedence' {
        InModuleScope 'OmadaWeb.PS' {
            $VersionInfo = ConvertTo-ModuleVersionInfo -Version '2026.9.1-nightly74+abc123'

            $VersionInfo.PrereleaseTag | Should -Be 'nightly74'
        }
    }

    It 'Should return $null for a value that is not a version' {
        InModuleScope 'OmadaWeb.PS' {
            ConvertTo-ModuleVersionInfo -Version 'latest' | Should -BeNullOrEmpty
        }
    }

    It 'Should return $null for an empty value' {
        InModuleScope 'OmadaWeb.PS' {
            ConvertTo-ModuleVersionInfo -Version '' | Should -BeNullOrEmpty
        }
    }
}

Describe 'Compare-ModuleVersion' -Tag 'Unit' {
    It 'Should report the reference as older when it is a lower stable version' {
        InModuleScope 'OmadaWeb.PS' {
            Compare-ModuleVersion -ReferenceVersion '1.0.0' -DifferenceVersion '2.0.0' | Should -Be -1
        }
    }

    It 'Should report the reference as newer when it is a higher stable version' {
        InModuleScope 'OmadaWeb.PS' {
            Compare-ModuleVersion -ReferenceVersion '2.0.0' -DifferenceVersion '1.0.0' | Should -Be 1
        }
    }

    It 'Should report equality for two identical stable versions' {
        InModuleScope 'OmadaWeb.PS' {
            Compare-ModuleVersion -ReferenceVersion '2026.9.1' -DifferenceVersion '2026.9.1' | Should -Be 0
        }
    }

    It 'Should sort a prerelease below the stable release of the same version' {
        InModuleScope 'OmadaWeb.PS' {
            Compare-ModuleVersion -ReferenceVersion '2026.9.1-nightly74' -DifferenceVersion '2026.9.1' | Should -Be -1
            Compare-ModuleVersion -ReferenceVersion '2026.9.1' -DifferenceVersion '2026.9.1-nightly74' | Should -Be 1
        }
    }

    It 'Should report equality for two identical prereleases' {
        InModuleScope 'OmadaWeb.PS' {
            Compare-ModuleVersion -ReferenceVersion '2026.9.1-nightly74' -DifferenceVersion '2026.9.1-nightly74' | Should -Be 0
        }
    }

    It 'Should order nightly tags by their build number rather than as text' {
        InModuleScope 'OmadaWeb.PS' {
            Compare-ModuleVersion -ReferenceVersion '2026.9.1-nightly9' -DifferenceVersion '2026.9.1-nightly74' | Should -Be -1
            Compare-ModuleVersion -ReferenceVersion '2026.9.1-nightly74' -DifferenceVersion '2026.9.1-nightly9' | Should -Be 1
        }
    }

    It 'Should compare a four component build against a three component release' {
        InModuleScope 'OmadaWeb.PS' {
            Compare-ModuleVersion -ReferenceVersion '2026.7.9.9' -DifferenceVersion '2026.9.1' | Should -Be -1
            Compare-ModuleVersion -ReferenceVersion '2026.9.1.1' -DifferenceVersion '2026.9.1' | Should -Be 1
        }
    }

    It 'Should return $null instead of throwing when a value cannot be parsed' {
        InModuleScope 'OmadaWeb.PS' {
            { Compare-ModuleVersion -ReferenceVersion 'not-a-version' -DifferenceVersion '1.0.0' } | Should -Not -Throw
            Compare-ModuleVersion -ReferenceVersion 'not-a-version' -DifferenceVersion '1.0.0' | Should -BeNullOrEmpty
            Compare-ModuleVersion -ReferenceVersion '1.0.0' -DifferenceVersion 'unknown' | Should -BeNullOrEmpty
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
