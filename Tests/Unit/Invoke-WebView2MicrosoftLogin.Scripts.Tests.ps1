param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-WebView2MicrosoftLogin JavaScript snippets' -Tag 'Unit' {

    BeforeAll {
        # The snippets are here-strings inside the function body. Reading them back from the loaded
        # command keeps this test working against both the source module and the built one.
        $Definition = InModuleScope 'OmadaWeb.PS' { (Get-Command Invoke-WebView2MicrosoftLogin).Definition }

        $Script:Snippets = @{}

        foreach ($Match in [regex]::Matches($Definition, '\$(?<Name>\w+Script)\s*=\s*@"\r?\n(?<Body>.*?)\r?\n"@', 'Singleline')) {
            $Script:Snippets[$Match.Groups['Name'].Value] = $Match.Groups['Body'].Value
        }
    }

    Context 'Snippets that the call sites invoke with arguments' {
        # These are appended with an argument list, for example
        # "$clickElementScript($(ConvertTo-JavaScriptLiteral $SubmitButtonId))". They must therefore
        # stay bare function expressions. A snippet that self-invokes turns the argument list into a
        # second, separate expression statement, and ExecuteScriptAsync then returns the value of
        # that trailing expression instead of the function result.
        It 'Leaves <Name> a bare function expression' -TestCases @(
            @{ Name = 'setElementValueScript' }
            @{ Name = 'clickElementScript' }
            @{ Name = 'isElementVisibleScript' }
            @{ Name = 'getElementByDataTestIdScript' }
            @{ Name = 'getElementPropertyScript' }
        ) {
            $Snippet = $Script:Snippets[$Name]

            $Snippet | Should -Not -BeNullOrEmpty -Because "the snippet $Name must exist in the function"
            $Snippet.TrimEnd() | Should -BeLike '*})'
            $Snippet.TrimEnd() | Should -Not -BeLike '*})()*'
        }
    }

    Context 'Snippets that the call sites execute as they are' {
        # These take no arguments and are passed to ExecuteScriptAsync unchanged, so they have to
        # invoke themselves.
        It 'Keeps <Name> self-invoking' -TestCases @(
            @{ Name = 'getAllIdsScript' }
            @{ Name = 'getMfaElementPropertyScript' }
            @{ Name = 'clickUseAnotherAccountScript' }
            @{ Name = 'checkForErrorScript' }
        ) {
            $Snippet = $Script:Snippets[$Name]

            $Snippet | Should -Not -BeNullOrEmpty -Because "the snippet $Name must exist in the function"
            $Snippet.TrimEnd() | Should -BeLike '*})();'
        }
    }

    Context 'Composed property lookup' {
        It 'Builds a single call expression for the stay-signed-in button labels' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Snippet = $Script:Snippets['getElementPropertyScript'] } {
                $ComposedScript = "$Snippet($(ConvertTo-JavaScriptLiteral 'idBtn_Back'), $(ConvertTo-JavaScriptLiteral 'textContent'))"

                # One statement: the function expression immediately applied to its two arguments.
                $ComposedScript | Should -BeLike '*})("idBtn_Back", "textContent")'
                $ComposedScript | Should -Not -BeLike '*})();*'
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
