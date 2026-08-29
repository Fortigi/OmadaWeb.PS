param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Select-EntraMfaMethod' -Tag 'Unit' {

    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            $Script:PreferredMfaMethodWarningIssued = $false
        }
    }

    Context 'Choosing without an override' {
        It 'Prefers the Authenticator approval over a code that has to be typed' {
            InModuleScope 'OmadaWeb.PS' {
                $Proof = @(
                    [pscustomobject]@{ authMethodId = 'OneWaySMS'; isDefault = $true }
                    [pscustomobject]@{ authMethodId = 'PhoneAppOTP'; isDefault = $false }
                    [pscustomobject]@{ authMethodId = 'PhoneAppNotification'; isDefault = $false }
                )

                $Chosen = Select-EntraMfaMethod -Proof $Proof

                $Chosen.AuthMethodId | Should -Be 'PhoneAppNotification'
                $Chosen.Index | Should -Be 2
            }
        }

        It 'Overrides the account default when a more secure method is offered' {
            # isDefault is the user's convenience setting, not a security ranking, so it does not win.
            InModuleScope 'OmadaWeb.PS' {
                $Proof = @(
                    [pscustomobject]@{ authMethodId = 'TwoWayVoiceMobile'; isDefault = $true }
                    [pscustomobject]@{ authMethodId = 'PhoneAppOTP'; isDefault = $false }
                )

                (Select-EntraMfaMethod -Proof $Proof).AuthMethodId | Should -Be 'PhoneAppOTP'
            }
        }

        It 'Still signs in with the only method an account has registered' {
            InModuleScope 'OmadaWeb.PS' {
                $Proof = @([pscustomobject]@{ authMethodId = 'TwoWayVoiceOffice'; isDefault = $true })

                (Select-EntraMfaMethod -Proof $Proof).AuthMethodId | Should -Be 'TwoWayVoiceOffice'
            }
        }

        It 'Ranks a method it has never seen behind every method it knows' {
            # An unknown identifier may well be something better, but automating a screen whose
            # behavior has never been seen here is the one thing that must not happen by default.
            InModuleScope 'OmadaWeb.PS' {
                $Proof = @(
                    [pscustomobject]@{ authMethodId = 'SomethingBrandNew'; isDefault = $true }
                    [pscustomobject]@{ authMethodId = 'TwoWayVoiceOffice'; isDefault = $false }
                )

                (Select-EntraMfaMethod -Proof $Proof).AuthMethodId | Should -Be 'TwoWayVoiceOffice'
            }
        }

        It 'Returns nothing when no offered method says which method it is' {
            # Clicking one of these would be choosing by position alone - the guessing this function
            # exists not to do - and the caller cannot tell a bad choice from a good one afterwards.
            InModuleScope 'OmadaWeb.PS' {
                $Proof = @(
                    [pscustomobject]@{ authMethodId = ''; isDefault = $true }
                    [pscustomobject]@{ authMethodId = $null; isDefault = $false }
                )

                Select-EntraMfaMethod -Proof $Proof | Should -BeNullOrEmpty
            }
        }

        It 'Ignores an unidentifiable entry rather than letting it win on position' {
            InModuleScope 'OmadaWeb.PS' {
                $Proof = @(
                    [pscustomobject]@{ authMethodId = ''; isDefault = $true }
                    [pscustomobject]@{ authMethodId = 'OneWaySMS'; isDefault = $false }
                )

                $Chosen = Select-EntraMfaMethod -Proof $Proof

                $Chosen.AuthMethodId | Should -Be 'OneWaySMS'
                $Chosen.Index | Should -Be 1
            }
        }

        It 'Returns nothing when the page offered no methods' {
            InModuleScope 'OmadaWeb.PS' {
                Select-EntraMfaMethod -Proof @() | Should -BeNullOrEmpty
                Select-EntraMfaMethod -Proof $null | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Choosing with -PreferredMfaMethod' {
        It 'Uses the method the caller asked for, even when a more secure one is offered' {
            InModuleScope 'OmadaWeb.PS' {
                $Proof = @(
                    [pscustomobject]@{ authMethodId = 'PhoneAppNotification'; isDefault = $true }
                    [pscustomobject]@{ authMethodId = 'OneWaySMS'; isDefault = $false }
                )

                $Chosen = Select-EntraMfaMethod -Proof $Proof -PreferredMethod 'OneWaySMS'

                $Chosen.AuthMethodId | Should -Be 'OneWaySMS'
                $Chosen.IsPreferred | Should -BeTrue
                $Chosen.Index | Should -Be 1
            }
        }

        It 'Falls back to the most secure offered method when the account does not offer the one asked for' {
            # Failing the whole sign-in over a preference would be a worse answer than signing in.
            InModuleScope 'OmadaWeb.PS' {
                $Proof = @(
                    [pscustomobject]@{ authMethodId = 'OneWaySMS'; isDefault = $true }
                    [pscustomobject]@{ authMethodId = 'PhoneAppNotification'; isDefault = $false }
                )

                $Chosen = Select-EntraMfaMethod -Proof $Proof -PreferredMethod 'PhoneAppOTP' -WarningAction SilentlyContinue

                $Chosen.AuthMethodId | Should -Be 'PhoneAppNotification'
                $Chosen.IsPreferred | Should -BeFalse
            }
        }

        It 'Says which methods the account does offer when the preference cannot be honoured' {
            InModuleScope 'OmadaWeb.PS' {
                $Proof = @([pscustomobject]@{ authMethodId = 'OneWaySMS'; isDefault = $true })

                Select-EntraMfaMethod -Proof $Proof -PreferredMethod 'PhoneAppOTP' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

                ($Warnings -join "`n") | Should -BeLike '*OneWaySMS*'
            }
        }

        It 'Reports an unhonoured preference once per sign-in, not once per timer tick' {
            InModuleScope 'OmadaWeb.PS' {
                $Proof = @([pscustomobject]@{ authMethodId = 'OneWaySMS'; isDefault = $true })

                Select-EntraMfaMethod -Proof $Proof -PreferredMethod 'PhoneAppOTP' -WarningVariable First -WarningAction SilentlyContinue | Out-Null
                Select-EntraMfaMethod -Proof $Proof -PreferredMethod 'PhoneAppOTP' -WarningVariable Second -WarningAction SilentlyContinue | Out-Null

                ($First | Measure-Object).Count | Should -Be 1
                ($Second | Measure-Object).Count | Should -Be 0
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
