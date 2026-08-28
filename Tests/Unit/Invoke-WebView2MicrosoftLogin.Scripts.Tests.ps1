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

        $Script:Definition = $Definition
        $Script:Snippets = @{}

        foreach ($Match in [regex]::Matches($Definition, '\$(?<Name>\w+Script)\s*=\s*@"\r?\n(?<Body>.*?)\r?\n"@', 'Singleline')) {
            $Script:Snippets[$Match.Groups['Name'].Value] = $Match.Groups['Body'].Value
        }
    }

    Context 'Snippets that the call sites invoke with arguments' {
        # These are appended with an argument list, for example
        # "$ClickElementScript($(ConvertTo-JavaScriptLiteral $SubmitId))". They must therefore
        # stay bare function expressions. A snippet that self-invokes turns the argument list into a
        # second, separate expression statement, and ExecuteScriptAsync then returns the value of
        # that trailing expression instead of the function result.
        It 'Leaves <Name> a bare function expression' -TestCases @(
            @{ Name = 'SetElementValueScript' }
            @{ Name = 'ClickElementScript' }
            @{ Name = 'ClickAccountTileScript' }
            @{ Name = 'ClickProofOptionScript' }
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
            @{ Name = 'ClickUseAnotherAccountScript' }
        ) {
            $Snippet = $Script:Snippets[$Name]

            $Snippet | Should -Not -BeNullOrEmpty -Because "the snippet $Name must exist in the function"
            $Snippet.TrimEnd() | Should -BeLike '*})();'
        }
    }

    Context 'Composed call expressions' {
        It 'Builds a single call expression for a click' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Snippet = $Script:Snippets['ClickElementScript'] } {
                $ComposedScript = "$Snippet($(ConvertTo-JavaScriptLiteral 'idBtn_Back'))"

                # One statement: the function expression immediately applied to its argument.
                $ComposedScript | Should -BeLike '*})("idBtn_Back")'
                $ComposedScript | Should -Not -BeLike '*})();*'
            }
        }
    }

    Context 'Agreement with the page probe' {
        It 'Clicks only an account tile it can see' {
            # Get-EntraSignInProbeScript reports only visible tiles, so the resolver can only ever
            # choose a visible one. Clicking the first element carrying that data-test-id regardless
            # would let a hidden namesake take the click - and that failure is invisible from here,
            # because the click reports success and so restarts the stall clock. The driver would sit
            # on the same page clicking nothing for as long as the window stayed open.
            $Snippet = $Script:Snippets['ClickAccountTileScript']

            $Snippet | Should -Not -BeNullOrEmpty
            $Snippet | Should -Match 'getComputedStyle'
            $Snippet | Should -Match "aria-hidden"
            $Snippet | Should -Match 'isVisible\(elements\[i\]\)'
        }
    }

    Context 'Language independence' {
        # The defect at the heart of issue #18: the 'Stay signed in?' screen used to be recognized by
        # reading the text of its two buttons and comparing it to 'Yes' and 'No', and sign-in
        # failures by sweeping the page for 'incorrect' and 'wrong password'. On a tenant served in
        # any other language those comparisons match nothing, and credential autofill silently did
        # nothing at all. The screen is now recognized by KmsiCheckboxField and failures by the
        # numeric error code, so nothing in this function may read rendered text again.
        It 'Does not compare rendered button text against a literal, as the old <Description> did' -TestCases @(
            @{ Description = "'Stay signed in?' button comparison"; Pattern = '-like\s+"\*(Yes|No)\*"' }
            @{ Description = 'button-label reader'; Pattern = 'BackButtonText' }
            @{ Description = 'textContent lookup'; Pattern = 'textContent|innerText' }
            # Quoted, so that describing the old behavior in a comment does not fail the test that
            # guards against it.
            @{ Description = 'English error-word sweep'; Pattern = "(?i)[`"']wrong password[`"']|[`"']not recognized[`"']|[`"']incorrect[`"']" }
            @{ Description = 'accessible-label comparison'; Pattern = 'ComputedAccessibleLabel' }
        ) {
            $Script:Definition | Should -Not -Match $Pattern
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
