param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeDiscovery {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    # Driven off the shipped schedule rather than a hard-coded list, so every entry added later
    # (phase 2 adds the WebView2 and -UseWebView2 rows, see issue #51) is covered on both sides of
    # both of its dates the moment it is added.
    $Schedule = & (Get-Module OmadaWeb.PS) { Get-OmadaDeprecationSchedule }
    $ScheduleEntries = foreach ($Key in $Schedule.Keys) {
        @{
            Feature      = $Key
            WarnFrom     = $Schedule[$Key].WarnFrom
            RemovedAfter = $Schedule[$Key].RemovedAfter
        }
    }
}

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaDeprecationSchedule' -Tag 'Unit' {
    It 'Should describe every entry with the full set of fields the warning helper reads' {
        InModuleScope 'OmadaWeb.PS' {
            $Schedule = Get-OmadaDeprecationSchedule
            $Schedule.Keys.Count | Should -BeGreaterThan 0

            foreach ($Key in $Schedule.Keys) {
                $Entry = $Schedule[$Key]
                $Entry.DisplayName | Should -Not -BeNullOrEmpty
                $Entry.Replacement | Should -Not -BeNullOrEmpty
                $Entry.Reference | Should -Not -BeNullOrEmpty
                $Entry.WarnFrom | Should -BeOfType [datetime]
                $Entry.RemovedAfter | Should -BeOfType [datetime]
                $Entry.WarnFrom | Should -BeLessOrEqual $Entry.RemovedAfter
            }
        }
    }

    It 'Should hold both dates in UTC so the comparison cannot flip a day in another timezone' {
        InModuleScope 'OmadaWeb.PS' {
            $Schedule = Get-OmadaDeprecationSchedule
            foreach ($Key in $Schedule.Keys) {
                $Schedule[$Key].WarnFrom.Kind | Should -Be ([System.DateTimeKind]::Utc)
                $Schedule[$Key].RemovedAfter.Kind | Should -Be ([System.DateTimeKind]::Utc)
            }
        }
    }

    It 'Should support the Selenium browser engine until 1 March 2027, warning from the announcement onwards' {
        InModuleScope 'OmadaWeb.PS' {
            $Entry = (Get-OmadaDeprecationSchedule)['SeleniumBrowserEngine']
            $Entry.RemovedAfter | Should -Be ([datetime]::new(2027, 3, 1, 0, 0, 0, [System.DateTimeKind]::Utc))
            $Entry.WarnFrom | Should -Be ([datetime]::new(2026, 8, 19, 0, 0, 0, [System.DateTimeKind]::Utc))
        }
    }
}

Describe 'Write-OmadaDeprecationWarning' -Tag 'Unit' {
    Context 'Message state per schedule entry' -ForEach $ScheduleEntries {
        It 'Should stay silent before WarnFrom for <Feature>' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Feature = $Feature; WarnFrom = $WarnFrom } {
                $Script:DeprecationWarningsShown = @{}
                Write-OmadaDeprecationWarning -Feature $Feature -UtcNow $WarnFrom.AddSeconds(-1) -WarningVariable Captured -WarningAction SilentlyContinue
                $Captured | Should -BeNullOrEmpty
            }
        }

        It 'Should announce the coming removal from WarnFrom onwards for <Feature>' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Feature = $Feature; WarnFrom = $WarnFrom; RemovedAfter = $RemovedAfter } {
                foreach ($Moment in @($WarnFrom, $WarnFrom.AddHours(12))) {
                    $Script:DeprecationWarningsShown = @{}
                    Write-OmadaDeprecationWarning -Feature $Feature -UtcNow $Moment -WarningVariable Captured -WarningAction SilentlyContinue
                    @($Captured).Count | Should -Be 1 -Because ("{0:yyyy-MM-dd HH:mm:ss} is on or after the announcement day" -f $Moment)
                    $Captured[0].Message | Should -BeLike ('*will be removed after {0:yyyy-MM-dd}*' -f $RemovedAfter)
                }
            }
        }

        It 'Should still announce the coming removal throughout the whole RemovedAfter day for <Feature>' {
            # RemovedAfter is the last supported *date*, not the first unsupported instant: the
            # feature goes in the first release published after it, which is not necessarily that
            # day. Both ends of the day are pinned - midnight alone would not have caught the
            # message flipping to "has been removed" at midday.
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Feature = $Feature; RemovedAfter = $RemovedAfter } {
                foreach ($Moment in @($RemovedAfter, $RemovedAfter.AddHours(12), $RemovedAfter.AddDays(1).AddTicks(-1))) {
                    $Script:DeprecationWarningsShown = @{}
                    Write-OmadaDeprecationWarning -Feature $Feature -UtcNow $Moment -WarningVariable Captured -WarningAction SilentlyContinue
                    @($Captured).Count | Should -Be 1 -Because ("{0:yyyy-MM-dd HH:mm:ss} is still within the supported day" -f $Moment)
                    $Captured[0].Message | Should -BeLike '*will be removed after*'
                }
            }
        }

        It 'Should report the removal as already shipped from the day after RemovedAfter for <Feature>' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Feature = $Feature; RemovedAfter = $RemovedAfter } {
                $Script:DeprecationWarningsShown = @{}
                Write-OmadaDeprecationWarning -Feature $Feature -UtcNow $RemovedAfter.AddDays(1) -WarningVariable Captured -WarningAction SilentlyContinue
                @($Captured).Count | Should -Be 1
                $Captured[0].Message | Should -BeLike '*has been removed in newer releases*'
                $Captured[0].Message | Should -BeLike '*This version still supports it*'
            }
        }

        It 'Should name the replacement and the announcement in the warning for <Feature>' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Feature = $Feature; WarnFrom = $WarnFrom } {
                $Entry = (Get-OmadaDeprecationSchedule)[$Feature]
                $Script:DeprecationWarningsShown = @{}
                Write-OmadaDeprecationWarning -Feature $Feature -UtcNow $WarnFrom -WarningVariable Captured -WarningAction SilentlyContinue
                $Captured[0].Message | Should -BeLike ('{0}*' -f $Entry.DisplayName)
                $Captured[0].Message | Should -BeLike ('*{0}*' -f $Entry.Replacement)
                $Captured[0].Message | Should -BeLike ('*{0}*' -f $Entry.Reference)
            }
        }
    }

    Context 'Suppression, clock injection and unknown features' {
        It 'Should warn once per session, not once per call' {
            InModuleScope 'OmadaWeb.PS' {
                $Entry = (Get-OmadaDeprecationSchedule)['SeleniumBrowserEngine']
                $Script:DeprecationWarningsShown = @{}
                Write-OmadaDeprecationWarning -Feature 'SeleniumBrowserEngine' -UtcNow $Entry.WarnFrom -WarningVariable First -WarningAction SilentlyContinue
                Write-OmadaDeprecationWarning -Feature 'SeleniumBrowserEngine' -UtcNow $Entry.WarnFrom -WarningVariable Second -WarningAction SilentlyContinue
                @($First).Count | Should -Be 1
                $Second | Should -BeNullOrEmpty
            }
        }

        It 'Should not consume the once-per-session slot while the deprecation is still unannounced' {
            InModuleScope 'OmadaWeb.PS' {
                $Entry = (Get-OmadaDeprecationSchedule)['SeleniumBrowserEngine']
                $Script:DeprecationWarningsShown = @{}
                Write-OmadaDeprecationWarning -Feature 'SeleniumBrowserEngine' -UtcNow $Entry.WarnFrom.AddDays(-1) -WarningVariable Early -WarningAction SilentlyContinue
                Write-OmadaDeprecationWarning -Feature 'SeleniumBrowserEngine' -UtcNow $Entry.WarnFrom -WarningVariable Later -WarningAction SilentlyContinue
                $Early | Should -BeNullOrEmpty
                @($Later).Count | Should -Be 1
            }
        }

        It 'Should fall back to the script-scoped clock override when no UtcNow argument is passed' {
            # This is the path used when the call is several frames down (Invoke-BrowserAuthentication
            # cannot forward a date it does not have).
            InModuleScope 'OmadaWeb.PS' {
                $Entry = (Get-OmadaDeprecationSchedule)['SeleniumBrowserEngine']
                try {
                    $Script:DeprecationWarningsShown = @{}
                    $Script:DeprecationUtcNow = $Entry.WarnFrom.AddDays(-1)
                    Write-OmadaDeprecationWarning -Feature 'SeleniumBrowserEngine' -WarningVariable Early -WarningAction SilentlyContinue

                    $Script:DeprecationUtcNow = $Entry.RemovedAfter.AddDays(1)
                    Write-OmadaDeprecationWarning -Feature 'SeleniumBrowserEngine' -WarningVariable Late -WarningAction SilentlyContinue

                    $Early | Should -BeNullOrEmpty
                    @($Late).Count | Should -Be 1
                    $Late[0].Message | Should -BeLike '*has been removed in newer releases*'
                }
                finally {
                    $Script:DeprecationUtcNow = $null
                }
            }
        }

        It 'Should compare in UTC, so a local-time clock lands on the same side of the boundary' {
            # On a machine already running in UTC this is a tautology; on any other offset it is the
            # test that fails if the ToUniversalTime conversion in the helper is dropped.
            InModuleScope 'OmadaWeb.PS' {
                $Entry = (Get-OmadaDeprecationSchedule)['SeleniumBrowserEngine']
                $WarnFromLocal = $Entry.WarnFrom.ToLocalTime()
                $WarnFromLocal.Kind | Should -Be ([System.DateTimeKind]::Local)

                $Script:DeprecationWarningsShown = @{}
                Write-OmadaDeprecationWarning -Feature 'SeleniumBrowserEngine' -UtcNow $WarnFromLocal.AddMinutes(-1) -WarningVariable Before -WarningAction SilentlyContinue

                $Script:DeprecationWarningsShown = @{}
                Write-OmadaDeprecationWarning -Feature 'SeleniumBrowserEngine' -UtcNow $WarnFromLocal -WarningVariable OnBoundary -WarningAction SilentlyContinue

                $Before | Should -BeNullOrEmpty
                @($OnBoundary).Count | Should -Be 1
            }
        }

        It 'Should throw for a feature that is not in the schedule instead of silently warning about nothing' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:DeprecationWarningsShown = @{}
                { Write-OmadaDeprecationWarning -Feature 'NoSuchFeature' -UtcNow ([datetime]::UtcNow) } | Should -Throw -ExpectedMessage '*NoSuchFeature*'
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
