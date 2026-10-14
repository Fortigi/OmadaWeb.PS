param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'New-OmadaWebCacheItem' -Tag 'Unit' {
    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            $Script:TestRoot = (New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("OmadaWebCacheItemTests_{0}" -f ([System.Guid]::NewGuid().ToString('N')))) -ItemType Directory -Force).FullName
        }
    }

    AfterEach {
        InModuleScope 'OmadaWeb.PS' {
            Remove-Item -LiteralPath $Script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'ItemType File' {
        It 'Should report a single existing file, including one under a bracketed folder (issue #105)' {
            # [System.IO.Directory]::CreateDirectory rather than New-Item -Path, so the setup itself
            # does not hit the wildcard trap "[" and "]" are for a -Path (as opposed to -LiteralPath)
            # cmdlet call.
            InModuleScope 'OmadaWeb.PS' {
                $BracketedFolder = Join-Path $Script:TestRoot -ChildPath 'bin[1]'
                [System.IO.Directory]::CreateDirectory($BracketedFolder) | Out-Null
                $FilePath = Join-Path $BracketedFolder -ChildPath 'WebDriver.dll'
                Set-Content -LiteralPath $FilePath -Value 'binary' -NoNewline

                $Item = New-OmadaWebCacheItem -Scope 'Binaries' -Artefact 'Downloaded runtime binaries' -Path $FilePath -ItemType 'File' -Protection 'NTFS permissions on the user profile only'

                $Item.Exists | Should -BeTrue
                $Item.ItemCount | Should -Be 1
                $Item.TargetPath | Should -Be @($FilePath)
                $Item.SizeBytes | Should -Be 6
            }
        }

        It 'Should report Exists false for a file that is not there' {
            InModuleScope 'OmadaWeb.PS' {
                $MissingPath = Join-Path $Script:TestRoot -ChildPath 'missing.dll'

                $Item = New-OmadaWebCacheItem -Scope 'Binaries' -Artefact 'Downloaded runtime binaries' -Path $MissingPath -ItemType 'File' -Protection 'NTFS permissions on the user profile only'

                $Item.Exists | Should -BeFalse
                $Item.ItemCount | Should -Be 0
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
