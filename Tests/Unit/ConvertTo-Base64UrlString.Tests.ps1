param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'ConvertTo-Base64UrlString' -Tag 'Unit' {
    Context 'Alphabet' {
        It 'Should replace the base64 characters that are not safe in a URL' {
            InModuleScope 'OmadaWeb.PS' {
                # These three bytes are 0xFB 0xFF 0xBF, which base64 renders as "+/+/" - the only two
                # characters where the two alphabets differ. Anything that fails to translate them
                # produces a token the identity provider rejects for a bad signature.
                $Encoded = ConvertTo-Base64UrlString -Byte ([byte[]]@(0xFB, 0xFF, 0xBF))

                [Convert]::ToBase64String([byte[]]@(0xFB, 0xFF, 0xBF)) | Should -Be '+/+/'
                $Encoded | Should -Be '-_-_'
            }
        }

        It 'Should strip the padding' {
            InModuleScope 'OmadaWeb.PS' {
                # One byte encodes to two base64 characters and two '=' of padding.
                ConvertTo-Base64UrlString -Byte ([byte[]]@(0x41)) | Should -Be 'QQ'
            }
        }

        It 'Should return an empty string for an empty input' {
            InModuleScope 'OmadaWeb.PS' {
                ConvertTo-Base64UrlString -Byte ([byte[]]@()) | Should -Be ''
            }
        }
    }

    Context 'Round trip' {
        It 'Should survive being decoded again' {
            InModuleScope 'OmadaWeb.PS' {
                $Original = [System.Text.Encoding]::UTF8.GetBytes('{"alg":"RS256","typ":"JWT"}')

                $Encoded = ConvertTo-Base64UrlString -Byte $Original

                $Padded = $Encoded.Replace('-', '+').Replace('_', '/')
                switch ($Padded.Length % 4) {
                    2 {
                        $Padded += '=='
                    }
                    3 {
                        $Padded += '='
                    }
                }

                [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Padded)) | Should -Be '{"alg":"RS256","typ":"JWT"}'
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
