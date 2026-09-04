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

    It 'Should release the unmanaged decryption buffer on both the success and the failure path' {
        # SecureStringToBSTR allocates unmanaged memory holding the decrypted document, which is
        # neither garbage collected nor zeroed on release. Decrypting a protected file only to leave
        # the plaintext in the process heap would defeat the point of protecting it. Asserted on the
        # source rather than by probing memory, because there is no supported way to observe a freed
        # BSTR - but a future edit that drops the finally fails here.
        InModuleScope 'OmadaWeb.PS' {
            $Source = (Get-Command Import-OmadaCookieFile).Definition

            $Source | Should -Match 'ZeroFreeBSTR'
            $Source | Should -Match 'PtrToStringBSTR'
            # PtrToStringAuto would read to the first null rather than using the BSTR length prefix.
            $Source | Should -Not -Match 'PtrToStringAuto'
            # The free has to be in a finally, or a file that fails to decrypt leaks the buffer.
            $Source | Should -Match '(?s)finally\s*\{[^}]*ZeroFreeBSTR'
        }
    }

    Context 'A file left unprotected by an earlier version' {
        # Not migrated, on purpose. Omada session cookies are short lived, so one written by an older
        # version has almost certainly expired; reading it would buy at most a few minutes of not
        # signing in, in exchange for a code path whose only job is to consume the very format this
        # change set out to stop producing.

        It 'Should be ignored rather than read' {
            InModuleScope 'OmadaWeb.PS' {
                [PSCustomObject]@{ OmadaWebAuthCookie = $Script:TestCookie } | Export-Clixml -Path $Script:TestCookiePath -Force

                Import-OmadaCookieFile -Path $Script:TestCookiePath | Should -BeNullOrEmpty
            }
        }

        It 'Should not warn about it, because signing in again is the whole cost' {
            InModuleScope 'OmadaWeb.PS' {
                [PSCustomObject]@{ OmadaWebAuthCookie = $Script:TestCookie } | Export-Clixml -Path $Script:TestCookiePath -Force

                $Warnings = @()
                Import-OmadaCookieFile -Path $Script:TestCookiePath -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

                @($Warnings).Count | Should -Be 0
            }
        }

        It 'Should be replaced by a protected file once the caller authenticates again' {
            # The unprotected file does not linger: the next successful sign-in writes over it
            # through the same path, so the plaintext is gone without a migration step.
            InModuleScope 'OmadaWeb.PS' {
                [PSCustomObject]@{ OmadaWebAuthCookie = $Script:TestCookie } | Export-Clixml -Path $Script:TestCookiePath -Force
                (Get-Content -Path $Script:TestCookiePath -Raw) | Should -Match 'SUPER-SECRET-TOKEN-VALUE'

                Export-OmadaCookieFile -Path $Script:TestCookiePath -AuthCookie $Script:TestCookie | Should -BeTrue

                (Get-Content -Path $Script:TestCookiePath -Raw) | Should -Not -Match 'SUPER-SECRET-TOKEN-VALUE'
                Test-OmadaCookieCacheFile -Path $Script:TestCookiePath | Should -BeTrue
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
