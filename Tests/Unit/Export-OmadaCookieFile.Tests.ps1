param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

# Issue #21. The default cookie cache was DPAPI-protected while -CookiePath wrote the raw
# oisauthtoken as plain Clixml, so the opt-in "keep my cookie somewhere stable" parameter was also
# the one that left a usable bearer token in a readable file. These tests hold both halves of the
# fix: the file is unreadable as text, and it still round-trips.

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Export-OmadaCookieFile / Import-OmadaCookieFile' -Tag 'Unit' {
    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            $Script:TestRoot = (New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("OmadaCookieFileTests_{0}" -f ([System.Guid]::NewGuid().ToString('N')))) -ItemType Directory -Force).FullName
            $Script:TestCookiePath = Join-Path $Script:TestRoot -ChildPath 'cookie.xml'
            $Script:TestCookie = [PSCustomObject]@{
                Name   = 'oisauthtoken'
                Value  = 'SUPER-SECRET-TOKEN-VALUE'
                domain = 'tenant.omada.cloud'
            }
        }
    }

    AfterEach {
        InModuleScope 'OmadaWeb.PS' {
            Remove-Item -Path $Script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Should round-trip the cookie through a written file' {
        InModuleScope 'OmadaWeb.PS' {
            Export-OmadaCookieFile -Path $Script:TestCookiePath -AuthCookie $Script:TestCookie | Should -BeTrue

            $Loaded = Import-OmadaCookieFile -Path $Script:TestCookiePath
            $Loaded.Name | Should -Be 'oisauthtoken'
            $Loaded.Value | Should -Be 'SUPER-SECRET-TOKEN-VALUE'
            $Loaded.domain | Should -Be 'tenant.omada.cloud'
        }
    }

    It 'Should not leave the token readable in the file' {
        # The whole point of the issue. Asserted against the raw bytes rather than against the
        # implementation, so any future change that stops protecting the file fails here.
        InModuleScope 'OmadaWeb.PS' {
            Export-OmadaCookieFile -Path $Script:TestCookiePath -AuthCookie $Script:TestCookie | Out-Null

            $Raw = Get-Content -Path $Script:TestCookiePath -Raw
            $Raw | Should -Not -Match 'SUPER-SECRET-TOKEN-VALUE'
            $Raw | Should -Not -Match 'oisauthtoken'
        }
    }

    It 'Should write the same protected shape the cookie cache detector recognises' {
        InModuleScope 'OmadaWeb.PS' {
            Export-OmadaCookieFile -Path $Script:TestCookiePath -AuthCookie $Script:TestCookie | Out-Null

            Test-OmadaCookieCacheFile -Path $Script:TestCookiePath | Should -BeTrue
        }
    }

    It 'Should overwrite an existing file rather than failing' {
        InModuleScope 'OmadaWeb.PS' {
            Export-OmadaCookieFile -Path $Script:TestCookiePath -AuthCookie $Script:TestCookie | Out-Null
            Export-OmadaCookieFile -Path $Script:TestCookiePath -AuthCookie ([PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'SECOND'; domain = 'tenant.omada.cloud' }) | Should -BeTrue

            (Import-OmadaCookieFile -Path $Script:TestCookiePath).Value | Should -Be 'SECOND'
        }
    }

    It 'Should report failure rather than throwing when the file cannot be written' {
        # A cookie that cannot be cached costs a login, not a failed request, so every caller treats
        # $false as "carry on".
        InModuleScope 'OmadaWeb.PS' {
            $Unwritable = Join-Path $Script:TestRoot -ChildPath 'no\such\folder\cookie.xml'
            { Export-OmadaCookieFile -Path $Unwritable -AuthCookie $Script:TestCookie } | Should -Not -Throw
            Export-OmadaCookieFile -Path $Unwritable -AuthCookie $Script:TestCookie 3>$null | Should -BeFalse
        }
    }

    Context 'A file left unprotected by an earlier version' {
        It 'Should still be readable, so an upgrade does not strand the user' {
            InModuleScope 'OmadaWeb.PS' {
                [PSCustomObject]@{ OmadaWebAuthCookie = $Script:TestCookie } | Export-Clixml -Path $Script:TestCookiePath -Force

                $Loaded = Import-OmadaCookieFile -Path $Script:TestCookiePath 3>$null
                $Loaded.Value | Should -Be 'SUPER-SECRET-TOKEN-VALUE'
            }
        }

        It 'Should be re-written protected on the spot, ending the exposure' {
            InModuleScope 'OmadaWeb.PS' {
                [PSCustomObject]@{ OmadaWebAuthCookie = $Script:TestCookie } | Export-Clixml -Path $Script:TestCookiePath -Force
                (Get-Content -Path $Script:TestCookiePath -Raw) | Should -Match 'SUPER-SECRET-TOKEN-VALUE'

                Import-OmadaCookieFile -Path $Script:TestCookiePath 3>$null | Out-Null

                (Get-Content -Path $Script:TestCookiePath -Raw) | Should -Not -Match 'SUPER-SECRET-TOKEN-VALUE'
                Test-OmadaCookieCacheFile -Path $Script:TestCookiePath | Should -BeTrue
            }
        }

        It 'Should warn, because the token was readable until this moment' {
            InModuleScope 'OmadaWeb.PS' {
                [PSCustomObject]@{ OmadaWebAuthCookie = $Script:TestCookie } | Export-Clixml -Path $Script:TestCookiePath -Force

                $Warnings = @()
                Import-OmadaCookieFile -Path $Script:TestCookiePath -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

                @($Warnings).Count | Should -BeGreaterThan 0
                ($Warnings -join ' ') | Should -Match 'unprotected'
            }
        }

        It 'Should read as protected on the next call, with no second warning' {
            InModuleScope 'OmadaWeb.PS' {
                [PSCustomObject]@{ OmadaWebAuthCookie = $Script:TestCookie } | Export-Clixml -Path $Script:TestCookiePath -Force
                Import-OmadaCookieFile -Path $Script:TestCookiePath 3>$null | Out-Null

                $Warnings = @()
                $Loaded = Import-OmadaCookieFile -Path $Script:TestCookiePath -WarningVariable Warnings -WarningAction SilentlyContinue

                $Loaded.Value | Should -Be 'SUPER-SECRET-TOKEN-VALUE'
                @($Warnings).Count | Should -Be 0
            }
        }
    }

    Context 'Unreadable input' {
        It 'Should return null for a file that is not there' {
            InModuleScope 'OmadaWeb.PS' {
                Import-OmadaCookieFile -Path (Join-Path $Script:TestRoot -ChildPath 'missing.xml') | Should -BeNullOrEmpty
            }
        }

        It 'Should return null for a protected file this user cannot decrypt' {
            # Indistinguishable from a corrupt one, and both mean the same thing: authenticate.
            InModuleScope 'OmadaWeb.PS' {
                Set-Content -Path $Script:TestCookiePath -Value '<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04"><SS>not-a-real-dpapi-blob</SS></Objs>'

                Import-OmadaCookieFile -Path $Script:TestCookiePath | Should -BeNullOrEmpty
            }
        }

        It 'Should return null for a file that is not Clixml at all' {
            InModuleScope 'OmadaWeb.PS' {
                Set-Content -Path $Script:TestCookiePath -Value 'this is not xml'

                Import-OmadaCookieFile -Path $Script:TestCookiePath 3>$null | Should -BeNullOrEmpty
            }
        }
    }
}
