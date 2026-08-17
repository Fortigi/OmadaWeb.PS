param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'ConvertFrom-JavaScriptResult' -Tag 'Unit' {

    Context 'Decoding what ExecuteScriptAsync returns' {
        It "Decodes <Name> to the original value" -TestCases @(
            @{ Name = 'a plain label'; Result = '"No"'; Expected = 'No' }
            @{ Name = 'a label containing a quote'; Result = '"Don\"t show this again"'; Expected = 'Don"t show this again' }
            @{ Name = 'a label containing a backslash'; Result = '"DOMAIN\\user"'; Expected = 'DOMAIN\user' }
            @{ Name = 'a label containing a line break'; Result = '"line1\nline2"'; Expected = "line1`nline2" }
            @{ Name = 'an empty label'; Result = '""'; Expected = '' }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Result = $Result; Expected = $Expected } {
                (ConvertFrom-JavaScriptResult $Result) | Should -BeExactly $Expected
            }
        }

        It "Returns null for <Name>" -TestCases @(
            @{ Name = 'the JavaScript null literal'; Result = 'null' }
            @{ Name = 'an empty result'; Result = '' }
            @{ Name = 'a whitespace-only result'; Result = '   ' }
            @{ Name = 'a null result'; Result = $null }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Result = $Result } {
                (ConvertFrom-JavaScriptResult $Result) | Should -BeNullOrEmpty
            }
        }

        It 'Returns null instead of throwing on a result that is not JSON' {
            InModuleScope 'OmadaWeb.PS' {
                (ConvertFrom-JavaScriptResult 'not json at all') | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Round-trip with the encoder' {
        It 'Survives a label that quote stripping would corrupt' {
            InModuleScope 'OmadaWeb.PS' {
                # This is what the button label looks like coming back out of the browser.
                $Label = 'Say "No" \ stay signed out'
                $Encoded = ConvertTo-JavaScriptLiteral $Label

                (ConvertFrom-JavaScriptResult $Encoded) | Should -BeExactly $Label
                # The replaced implementation stripped every quote instead of decoding.
                ($Encoded -replace '"', '') | Should -Not -BeExactly $Label
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
