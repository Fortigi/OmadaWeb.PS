param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaCookieCacheFilePath' -Tag 'Unit' {
    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            $Script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("OmadaWebCacheTests_{0}" -f ([System.Guid]::NewGuid().ToString('N')))
            $Script:CookieCachePath = Join-Path $Script:TestRoot -ChildPath 'Cookies'
            $Script:LegacyCookieCachePath = (New-Item -Path (Join-Path $Script:TestRoot -ChildPath 'LegacyTemp') -ItemType Directory -Force).FullName
        }
    }

    AfterEach {
        InModuleScope 'OmadaWeb.PS' {
            Remove-Item -Path $Script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Should return a path under the module cookie cache folder, not under %TEMP%' {
        InModuleScope 'OmadaWeb.PS' {
            $Path = Get-OmadaCookieCacheFilePath -SessionKey 'example.omada.cloud::webview2::'
            $Path | Should -Be (Join-Path $Script:CookieCachePath -ChildPath (Get-OmadaShortHash -Value 'example.omada.cloud::webview2::'))
            $Path | Should -Not -BeLike (Join-Path $Script:LegacyCookieCachePath '*')
        }
    }

    It 'Should create the cookie cache folder on demand' {
        InModuleScope 'OmadaWeb.PS' {
            Test-Path $Script:CookieCachePath -PathType Container | Should -BeFalse
            Get-OmadaCookieCacheFilePath -SessionKey 'example.omada.cloud::webview2::' | Out-Null
            Test-Path $Script:CookieCachePath -PathType Container | Should -BeTrue
        }
    }

    It 'Should return the same path for the same session key' {
        InModuleScope 'OmadaWeb.PS' {
            $First = Get-OmadaCookieCacheFilePath -SessionKey 'example.omada.cloud::webview2::'
            $Second = Get-OmadaCookieCacheFilePath -SessionKey 'example.omada.cloud::webview2::'
            $Second | Should -Be $First
        }
    }

    It 'Should return different paths for different session keys' {
        InModuleScope 'OmadaWeb.PS' {
            $A = Get-OmadaCookieCacheFilePath -SessionKey 'a.example.com::webview2::'
            $B = Get-OmadaCookieCacheFilePath -SessionKey 'b.example.com::webview2::'
            $A | Should -Not -Be $B
        }
    }

    Context 'Migration from the legacy %TEMP% location' {
        It 'Should move a cache left behind by an earlier module version, keeping its contents' {
            InModuleScope 'OmadaWeb.PS' {
                $SessionKey = 'legacy.omada.cloud::webview2::'
                $LegacyFilePath = Join-Path $Script:LegacyCookieCachePath -ChildPath (Get-OmadaShortHash -Value $SessionKey)
                ConvertTo-SecureString -String 'cached-cookie' -AsPlainText -Force | Export-Clixml -Path $LegacyFilePath -Force

                $Path = Get-OmadaCookieCacheFilePath -SessionKey $SessionKey

                Test-Path $Path -PathType Leaf | Should -BeTrue
                Test-Path $LegacyFilePath -PathType Leaf | Should -BeFalse -Because 'a usable session cookie must not be left behind in %TEMP%'
                [System.Net.NetworkCredential]::new('', (Import-Clixml -Path $Path)).Password | Should -Be 'cached-cookie'
            }
        }

        It 'Should not overwrite a cache that already exists in the new location' {
            InModuleScope 'OmadaWeb.PS' {
                $SessionKey = 'both.omada.cloud::webview2::'
                $FileName = Get-OmadaShortHash -Value $SessionKey
                $null = New-Item -Path $Script:CookieCachePath -ItemType Directory -Force
                Set-Content -Path (Join-Path $Script:CookieCachePath -ChildPath $FileName) -Value 'current' -NoNewline
                Set-Content -Path (Join-Path $Script:LegacyCookieCachePath -ChildPath $FileName) -Value 'stale' -NoNewline

                $Path = Get-OmadaCookieCacheFilePath -SessionKey $SessionKey

                Get-Content -Path $Path -Raw | Should -Be 'current'
            }
        }

        It 'Should not migrate a file that is not one of our cookie caches, even on a name collision' {
            InModuleScope 'OmadaWeb.PS' {
                # %TEMP% is shared with every other program on the machine, so the hashed file name
                # alone is not proof the file is ours. Moving it would take someone else's file, and
                # a failed move would delete it.
                $SessionKey = 'collision.omada.cloud::webview2::'
                $LegacyFilePath = Join-Path $Script:LegacyCookieCachePath -ChildPath (Get-OmadaShortHash -Value $SessionKey)
                Set-Content -Path $LegacyFilePath -Value 'someone elses file that happens to collide' -NoNewline

                $Path = Get-OmadaCookieCacheFilePath -SessionKey $SessionKey

                Test-Path $LegacyFilePath -PathType Leaf | Should -BeTrue -Because 'a file we did not write must not be moved or deleted'
                Get-Content -Path $LegacyFilePath -Raw | Should -Be 'someone elses file that happens to collide'
                Test-Path $Path -PathType Leaf | Should -BeFalse -Because 'nothing should have been migrated into the cache folder'
            }
        }

        It 'Should leave files belonging to other sessions in the legacy folder alone' {
            InModuleScope 'OmadaWeb.PS' {
                $OtherFilePath = Join-Path $Script:LegacyCookieCachePath -ChildPath (Get-OmadaShortHash -Value 'other.omada.cloud::webview2::')
                Set-Content -Path $OtherFilePath -Value 'other session' -NoNewline

                Get-OmadaCookieCacheFilePath -SessionKey 'mine.omada.cloud::webview2::' | Out-Null

                Test-Path $OtherFilePath -PathType Leaf | Should -BeTrue
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
