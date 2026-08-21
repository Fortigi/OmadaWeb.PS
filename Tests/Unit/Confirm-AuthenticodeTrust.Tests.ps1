param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Confirm-AuthenticodeTrust' -Tag 'Unit' {
    BeforeEach {
        $SignedFile = Join-Path $TestDrive 'msedgedriver.exe'
        Set-Content -Path $SignedFile -Value 'pretend this is an executable' -NoNewline

        InModuleScope 'OmadaWeb.PS' -Parameters @{ SignedFile = $SignedFile } {
            $Script:TestSignedFile = $SignedFile
        }
    }

    It 'Should accept a valid signature from the expected publisher' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Get-AuthenticodeSignature {
                [PSCustomObject]@{
                    Status            = 'Valid'
                    StatusMessage     = 'Signature verified.'
                    SignerCertificate = [PSCustomObject]@{ Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' }
                }
            }

            { Confirm-AuthenticodeTrust -Path $Script:TestSignedFile -ExpectedSubject '*O=Microsoft Corporation*' -ArtifactName 'msedgedriver.exe' -ErrorAction Stop } |
                Should -Not -Throw

            # An accepted file must survive.
            Test-Path $Script:TestSignedFile -PathType Leaf | Should -BeTrue
        }
    }

    It 'Should refuse and delete an unsigned file' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Get-AuthenticodeSignature {
                [PSCustomObject]@{
                    Status            = 'NotSigned'
                    StatusMessage     = 'The file is not digitally signed.'
                    SignerCertificate = $null
                }
            }

            { Confirm-AuthenticodeTrust -Path $Script:TestSignedFile -ExpectedSubject '*O=Microsoft Corporation*' -ArtifactName 'msedgedriver.exe' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Authenticode check FAILED*'

            Test-Path $Script:TestSignedFile -PathType Leaf | Should -BeFalse
        }
    }

    It 'Should refuse and delete a file whose signature no longer matches its contents' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Get-AuthenticodeSignature {
                [PSCustomObject]@{
                    Status            = 'HashMismatch'
                    StatusMessage     = 'The contents of file do not match the signature.'
                    SignerCertificate = [PSCustomObject]@{ Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation' }
                }
            }

            { Confirm-AuthenticodeTrust -Path $Script:TestSignedFile -ExpectedSubject '*O=Microsoft Corporation*' -ArtifactName 'msedgedriver.exe' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*HashMismatch*'

            Test-Path $Script:TestSignedFile -PathType Leaf | Should -BeFalse
        }
    }

    It 'Should refuse a valid signature issued to a different publisher' {
        InModuleScope 'OmadaWeb.PS' {
            # The dangerous case: the binary is properly signed, just not by Microsoft.
            Mock Get-AuthenticodeSignature {
                [PSCustomObject]@{
                    Status            = 'Valid'
                    StatusMessage     = 'Signature verified.'
                    SignerCertificate = [PSCustomObject]@{ Subject = 'CN=Evil Corp, O=Evil Corp, C=XX' }
                }
            }

            { Confirm-AuthenticodeTrust -Path $Script:TestSignedFile -ExpectedSubject '*O=Microsoft Corporation*' -ArtifactName 'msedgedriver.exe' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*unexpected publisher*'

            Test-Path $Script:TestSignedFile -PathType Leaf | Should -BeFalse
        }
    }

    It 'Should refuse when the signature cannot be checked at all' {
        InModuleScope 'OmadaWeb.PS' {
            # Being unable to verify must fail the same way as failing verification: this is the one
            # artefact with no hash to fall back on.
            Mock Get-AuthenticodeSignature { throw 'The term ''Get-AuthenticodeSignature'' is not recognized.' }

            { Confirm-AuthenticodeTrust -Path $Script:TestSignedFile -ExpectedSubject '*O=Microsoft Corporation*' -ArtifactName 'msedgedriver.exe' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Cannot verify the Authenticode signature*'

            Test-Path $Script:TestSignedFile -PathType Leaf | Should -BeFalse
        }
    }

    It 'Should refuse a file that is not there at all' {
        InModuleScope 'OmadaWeb.PS' {
            { Confirm-AuthenticodeTrust -Path (Join-Path $TestDrive 'missing.exe') -ExpectedSubject '*O=Microsoft Corporation*' -ArtifactName 'msedgedriver.exe' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*does not exist*'
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
