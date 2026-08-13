param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Clear-OmadaWebCache' -Tag 'Unit' {
    BeforeEach {
        # Point every artefact path at a throwaway tree so the tests never touch the real
        # %LOCALAPPDATA%\OmadaWeb.PS folder of whoever runs them.
        InModuleScope 'OmadaWeb.PS' {
            $Script:TestRoot = (New-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("OmadaWebClearTests_{0}" -f ([System.Guid]::NewGuid().ToString('N')))) -ItemType Directory -Force).FullName
            $Script:ModuleAppDataPath = $Script:TestRoot
            $Script:CookieCachePath = Join-Path $Script:TestRoot -ChildPath 'Cookies'
            $Script:LegacyCookieCachePath = (New-Item -Path (Join-Path $Script:TestRoot -ChildPath 'LegacyTemp') -ItemType Directory -Force).FullName
            $Script:WebView2UserProfileBasePath = Join-Path $Script:TestRoot -ChildPath 'Edge User Data'
            $Script:SeleniumProfileBasePath = Join-Path $Script:TestRoot -ChildPath 'Profiles'
            $Script:OmadaSessions = @{ 'a.example.com::webview2::' = [pscustomobject]@{ Key = 'a.example.com::webview2::' } }

            # One artefact of every kind the module can leave behind.
            $null = New-Item -Path $Script:CookieCachePath -ItemType Directory -Force
            Set-Content -Path (Join-Path $Script:CookieCachePath -ChildPath 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa') -Value 'cookie' -NoNewline
            ConvertTo-SecureString -String 'legacy-cookie' -AsPlainText -Force |
                Export-Clixml -Path (Join-Path $Script:LegacyCookieCachePath -ChildPath 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb') -Force
            $null = New-Item -Path (Join-Path $Script:WebView2UserProfileBasePath -ChildPath 'OmadaWebView2Profile_0123456789abcdef') -ItemType Directory -Force
            Set-Content -Path (Join-Path $Script:WebView2UserProfileBasePath -ChildPath 'OmadaWebView2Profile_0123456789abcdef\Cookies') -Value '0123456789' -NoNewline
            $null = New-Item -Path (Join-Path $Script:SeleniumProfileBasePath -ChildPath 'Default_01234567') -ItemType Directory -Force
            Set-Content -Path (Join-Path $Script:SeleniumProfileBasePath -ChildPath 'Default_01234567\Preferences') -Value '{}' -NoNewline
            $null = New-Item -Path (Join-Path $Script:TestRoot -ChildPath 'Bin\Core') -ItemType Directory -Force
            Set-Content -Path (Join-Path $Script:TestRoot -ChildPath 'Bin\Core\WebDriver.dll') -Value 'binary' -NoNewline
        }
    }

    AfterEach {
        InModuleScope 'OmadaWeb.PS' {
            Remove-Item -Path $Script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Enumeration' {
        It 'Should report every artefact the module stores' {
            $Items = @(Clear-OmadaWebCache -ListOnly)
            $Items.Scope | Should -Contain 'Cookies'
            $Items.Scope | Should -Contain 'BrowserProfiles'
            $Items.Scope | Should -Contain 'Binaries'
            $Items.Scope | Should -Contain 'Sessions'
            @($Items | Where-Object { -not $_.Exists }) | Should -BeNullOrEmpty
        }

        It 'Should report the item count and size of each artefact' {
            $Profiles = @(Clear-OmadaWebCache -ListOnly -Scope BrowserProfiles) | Where-Object { $_.Artefact -like 'WebView2*' }
            $Profiles.ItemCount | Should -Be 1
            $Profiles.SizeBytes | Should -Be 10
        }

        It 'Should report the number of in-memory authentication sessions' {
            $Sessions = @(Clear-OmadaWebCache -ListOnly -Scope Sessions)
            $Sessions.Count | Should -Be 1
            $Sessions[0].ItemCount | Should -Be 1
            $Sessions[0].ItemType | Should -Be 'Memory'
        }

        It 'Should state how each artefact is protected' {
            foreach ($Item in @(Clear-OmadaWebCache -ListOnly)) {
                $Item.Protection | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should report a cookie cache left behind in the legacy %TEMP% location' {
            $Legacy = @(Clear-OmadaWebCache -ListOnly -Scope Cookies) | Where-Object { $_.Artefact -like '*legacy*' }
            $Legacy | Should -Not -BeNullOrEmpty
            $Legacy.Path | Should -BeLike (Join-Path ([System.IO.Path]::GetTempPath()) '*bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
        }

        It 'Should remove nothing when -ListOnly is used' {
            Clear-OmadaWebCache -ListOnly | Out-Null
            InModuleScope 'OmadaWeb.PS' {
                Test-Path (Join-Path $Script:TestRoot -ChildPath 'Bin\Core\WebDriver.dll') | Should -BeTrue
                Test-Path $Script:CookieCachePath | Should -BeTrue
                $Script:OmadaSessions.Count | Should -Be 1
            }
        }

        It 'Should limit the inventory to the requested scope' {
            $Items = @(Clear-OmadaWebCache -ListOnly -Scope Binaries)
            $Items.Count | Should -Be 1
            $Items[0].Scope | Should -Be 'Binaries'
        }
    }

    Context 'Removal' {
        It 'Should remove only the requested scope' {
            $Items = @(Clear-OmadaWebCache -Scope Binaries -Force -Confirm:$false)

            @($Items | Where-Object { $_.Removed }).Count | Should -Be 1
            InModuleScope 'OmadaWeb.PS' {
                Test-Path (Join-Path $Script:TestRoot -ChildPath 'Bin') | Should -BeFalse
                Test-Path $Script:CookieCachePath | Should -BeTrue
                Test-Path $Script:WebView2UserProfileBasePath | Should -BeTrue
                $Script:OmadaSessions.Count | Should -Be 1
            }
        }

        It 'Should remove every artefact when no scope is given' {
            Clear-OmadaWebCache -Force -Confirm:$false | Out-Null

            InModuleScope 'OmadaWeb.PS' {
                Test-Path $Script:CookieCachePath | Should -BeFalse
                Test-Path $Script:WebView2UserProfileBasePath | Should -BeFalse
                Test-Path $Script:SeleniumProfileBasePath | Should -BeFalse
                Test-Path (Join-Path $Script:TestRoot -ChildPath 'Bin') | Should -BeFalse
                $Script:OmadaSessions.Count | Should -Be 0
            }
        }

        It 'Should clear the in-memory session state' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:CurrentWebView2Session = [pscustomobject]@{ Key = 'a' }
                $Global:OmadaWebPSCurrentBaseUrl = 'https://example.omada.cloud'
            }

            Clear-OmadaWebCache -Scope Sessions -Force -Confirm:$false | Out-Null

            InModuleScope 'OmadaWeb.PS' {
                $Script:OmadaSessions.Count | Should -Be 0
                $Script:CurrentWebView2Session | Should -BeNullOrEmpty
            }
            $Global:OmadaWebPSCurrentBaseUrl | Should -BeNullOrEmpty
        }

        It 'Should remove a cookie cache left behind in the legacy %TEMP% location' {
            Clear-OmadaWebCache -Scope Cookies -Force -Confirm:$false | Out-Null

            InModuleScope 'OmadaWeb.PS' {
                Test-Path (Join-Path $Script:LegacyCookieCachePath -ChildPath 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb') | Should -BeFalse
            }
        }

        It 'Should leave unrelated files in the legacy %TEMP% location alone' {
            InModuleScope 'OmadaWeb.PS' {
                # Same 32 hex character shape as a cookie cache, but not written by this module.
                Set-Content -Path (Join-Path $Script:LegacyCookieCachePath -ChildPath 'cccccccccccccccccccccccccccccccc') -Value 'someone elses file' -NoNewline
                Set-Content -Path (Join-Path $Script:LegacyCookieCachePath -ChildPath 'unrelated.tmp') -Value 'someone elses file' -NoNewline
            }

            Clear-OmadaWebCache -Scope Cookies -Force -Confirm:$false | Out-Null

            InModuleScope 'OmadaWeb.PS' {
                Test-Path (Join-Path $Script:LegacyCookieCachePath -ChildPath 'cccccccccccccccccccccccccccccccc') | Should -BeTrue
                Test-Path (Join-Path $Script:LegacyCookieCachePath -ChildPath 'unrelated.tmp') | Should -BeTrue
            }
        }

        It 'Should remove nothing when -WhatIf is used' {
            $Items = @(Clear-OmadaWebCache -Force -WhatIf)

            @($Items | Where-Object { $_.Removed }) | Should -BeNullOrEmpty
            InModuleScope 'OmadaWeb.PS' {
                Test-Path $Script:CookieCachePath | Should -BeTrue
                Test-Path (Join-Path $Script:TestRoot -ChildPath 'Bin') | Should -BeTrue
                $Script:OmadaSessions.Count | Should -Be 1
            }
        }

        It 'Should report what it removed' {
            $Items = @(Clear-OmadaWebCache -Force -Confirm:$false)

            foreach ($Item in $Items) {
                $Item.Removed | Should -BeTrue -Because "'$($Item.Artefact)' existed before the call"
                $Item.Path | Should -Not -BeNullOrEmpty
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    $Global:OmadaWebPSCurrentBaseUrl = $null
}
