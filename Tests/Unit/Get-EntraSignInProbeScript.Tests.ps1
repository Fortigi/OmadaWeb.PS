param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-EntraSignInProbeScript' -Tag 'Unit' {

    Context 'The shape the call site expects' {
        It 'Is a self-invoking expression, because it is passed to ExecuteScriptAsync unchanged' {
            InModuleScope 'OmadaWeb.PS' {
                (Get-EntraSignInProbeScript).TrimEnd() | Should -BeLike '*})();'
            }
        }

        It 'Leaves no placeholder unreplaced' {
            InModuleScope 'OmadaWeb.PS' {
                Get-EntraSignInProbeScript | Should -Not -BeLike '*__*__*'
            }
        }

        It 'Reports every member the rules read from it' {
            InModuleScope 'OmadaWeb.PS' {
                $ProbeScript = Get-EntraSignInProbeScript

                foreach ($Member in 'ids', 'visibleIds', 'errorCode', 'errorCodeText', 'proofs', 'proofOptionCount', 'accountTiles', 'hasOtherTile', 'displaySign', 'hasVisiblePasswordInput', 'hasVisibleEmailInput') {
                    $ProbeScript | Should -BeLike ("*{0}:*" -f $Member) -Because "Resolve-EntraSignInScreen reads $Member off the snapshot"
                }
            }
        }
    }

    Context 'Built once' {
        It 'Hands out the same script rather than building it again' {
            # It is built from the selector table and from nothing else, and the sign-in reads the
            # page again and again on the WebView2 UI thread while a user works through it.
            InModuleScope 'OmadaWeb.PS' {
                $Script:EntraSignInProbeScript = $null

                $First = Get-EntraSignInProbeScript
                $Second = Get-EntraSignInProbeScript

                $Script:EntraSignInProbeScript | Should -Not -BeNullOrEmpty -Because 'the cache is populated before the first call returns'
                [object]::ReferenceEquals($First, $Second) | Should -BeTrue
            }
        }

        It 'Rebuilds from the selector table when that table changes' {
            InModuleScope 'OmadaWeb.PS' {
                # Import-Module -Force re-runs the module file, which clears the cache. Without that
                # an edited selector table would keep serving the script made from the old one.
                $Script:EntraSignInProbeScript = $null
                Get-EntraSignInProbeScript | Should -BeLike '*i0116*'
            }
        }
    }

    Context 'One selector table, not two' {
        It 'Looks for every element id the rules are written against' {
            # The script and the rules would drift apart the moment either kept its own copy of the
            # selectors, so both read $Script:EntraSignInElementId and this proves the script does.
            InModuleScope 'OmadaWeb.PS' {
                $ProbeScript = Get-EntraSignInProbeScript

                foreach ($ElementId in $Script:EntraSignInElementId.Values) {
                    $ProbeScript | Should -BeLike ("*{0}*" -f $ElementId) -Because "$ElementId is in the selector table"
                }
            }
        }
    }

    Context 'Language independence' {
        It 'Never compares anything on the page against the English word <Word>' {
            # This is the regression guard for the defect at the heart of issue #18: the previous
            # implementation identified the 'Stay signed in?' screen by comparing its buttons to
            # 'Yes' and 'No', and looked for sign-in failures by searching the page for 'incorrect'
            # and 'wrong password'. On any tenant not served in English those comparisons match
            # nothing, and credential autofill silently did nothing at all.
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Word = $Word } {
                Get-EntraSignInProbeScript | Should -Not -BeLike ("*{0}*" -f $Word)
            }
        } -TestCases @(
            @{ Word = 'Next' }
            @{ Word = 'Sign in' }
            @{ Word = "'Yes'" }
            @{ Word = 'incorrect' }
            @{ Word = 'wrong password' }
            @{ Word = 'not recognized' }
            @{ Word = 'ComputedAccessibleLabel' }
        )
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
