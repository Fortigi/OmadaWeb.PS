param(
    # Accepted for consistency with the other test files (psakeBuild.ps1 passes it to every
    # container); these tests exercise a build helper, not the built module.
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    $Script:RepositoryRoot = Split-Path $(Split-Path $PSScriptRoot)
    $Script:HelperScript = Join-Path $Script:RepositoryRoot -ChildPath 'Build\ConvertTo-HashtableDeep.ps1'
    . $Script:HelperScript

    # The build feeds this helper the result of a JSON round-trip, so the tests do the same:
    # deserialized values arrive as PSCustomObject graphs and PSObject-wrapped scalars.
    function ConvertTo-DeserializedGraph {
        param($InputObject)

        return ($InputObject | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
    }
}

Describe 'ConvertTo-HashtableDeep' -Tag 'Unit' {
    Context 'Scalars' {
        It 'Should return a plain string unchanged' {
            ConvertTo-HashtableDeep 'Omada' | Should -BeOfType [string]
            ConvertTo-HashtableDeep 'Omada' | Should -Be 'Omada'
        }

        It 'Should return other scalar types unchanged' {
            ConvertTo-HashtableDeep 42 | Should -Be 42
            ConvertTo-HashtableDeep $true | Should -Be $true
        }

        It 'Should return null unchanged' {
            ConvertTo-HashtableDeep $null | Should -BeNullOrEmpty
        }
    }

    Context 'String arrays' {
        It 'Should keep every element of a string array a string' {
            $Result = ConvertTo-HashtableDeep (ConvertTo-DeserializedGraph @('Omada', 'Windows'))
            foreach ($Element in $Result) {
                $Element | Should -BeOfType [string]
            }
            $Result | Should -Be @('Omada', 'Windows')
        }

        It 'Should not turn string elements into hashtables' {
            $Result = ConvertTo-HashtableDeep (ConvertTo-DeserializedGraph @('Omada', 'Windows'))
            ($Result -join ',') | Should -Not -Match 'System\.Collections\.Hashtable'
        }
    }

    Context 'Objects' {
        It 'Should convert a PSCustomObject to a Hashtable' {
            $Result = ConvertTo-HashtableDeep (ConvertTo-DeserializedGraph ([PSCustomObject]@{ Name = 'Value' }))
            $Result | Should -BeOfType [System.Collections.Hashtable]
            $Result.Name | Should -Be 'Value'
        }

        It 'Should convert nested objects recursively' {
            $Nested = ConvertTo-DeserializedGraph @{ Outer = @{ Inner = @{ Leaf = 'deep' } } }
            $Result = ConvertTo-HashtableDeep $Nested
            $Result.Outer.Inner.Leaf | Should -Be 'deep'
        }
    }

    Context 'The manifest PrivateData round trip' {
        It 'Should preserve the Tags declared in the module manifest' {
            $ManifestPath = Join-Path $Script:RepositoryRoot -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psd1'
            $Manifest = Import-PowerShellDataFile -Path $ManifestPath
            $ExpectedTags = $Manifest.PrivateData.PSData.Tags

            $PrivateData = ConvertTo-HashtableDeep (ConvertTo-DeserializedGraph $Manifest.PrivateData)

            $PrivateData.PSData | Should -BeOfType [System.Collections.Hashtable]
            $PrivateData.PSData.Tags | Should -Be $ExpectedTags
            foreach ($Tag in $PrivateData.PSData.Tags) {
                $Tag | Should -BeOfType [string]
            }
        }

        It 'Should preserve the scalar PSData values' {
            $ManifestPath = Join-Path $Script:RepositoryRoot -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psd1'
            $Manifest = Import-PowerShellDataFile -Path $ManifestPath
            $PrivateData = ConvertTo-HashtableDeep (ConvertTo-DeserializedGraph $Manifest.PrivateData)

            $PrivateData.PSData.ProjectUri | Should -Be $Manifest.PrivateData.PSData.ProjectUri
            $PrivateData.PSData.LicenseUri | Should -Be $Manifest.PrivateData.PSData.LicenseUri
        }
    }
}
