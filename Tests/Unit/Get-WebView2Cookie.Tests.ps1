param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    $Script:Definition = InModuleScope 'OmadaWeb.PS' { (Get-Command Get-WebView2Cookie).Definition }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}

Describe 'Get-WebView2Cookie' -Tag 'Unit' {

    Context 'Counting the cookies that matched' {
        # The regression guard for issue #79, and it is a guard on the shape of the code rather than
        # on its behaviour, because this function cannot be called without a live CoreWebView2.
        #
        # Where-Object returns the single object itself when exactly one cookie matches, and a bare
        # object has no Count. Under StrictMode that is a terminating error raised inside an
        # asynchronous cookie callback, whose catch only writes "Cookie callback error" to the
        # console - so the authentication cookie is never exported, the sign-in window never closes,
        # and a sign-in that actually succeeded hangs until something else times it out.
        #
        # One matching cookie is the ordinary case for any host that sets only oisauthtoken. The
        # scheduled canary's loopback stand-in sets exactly that, which is how this was found.

        It 'Wraps the filtered cookies so a single match still has a Count' {
            $Script:Definition | Should -Match '\$Match\s*=\s*@\('
        }

        It 'Never reads Count off an unwrapped pipeline result' {
            # Belt and braces on the line above: if someone unwraps it again, the assertion that the
            # array subexpression is present would still pass if a second, unwrapped assignment were
            # introduced.
            $Script:Definition | Should -Not -Match '\$Match\s*=\s*\$Cookies\s*\|'
        }
    }

    Context 'The idiom itself, under the StrictMode the module runs with' {
        It 'Gives a single filtered item a Count of 1 when wrapped, and none when not' {
            # Not testing PowerShell for its own sake: this is the exact difference the fix turns on,
            # and stating it here is what makes the shape assertions above mean something to a reader
            # who has not met this failure.
            & {
                Set-StrictMode -Version Latest

                $Single = @("only-one") | Where-Object { $true }
                @($Single).Count | Should -Be 1
                { $Single.Count } | Should -Throw
            }
        }
    }
}
