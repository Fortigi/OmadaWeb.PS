param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Stop-OmadaLogin' -Tag 'Unit' {

    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            $Script:LoginAbortReason = $null
            $Script:MicrosoftOnlineLogin = $true
            $Script:LoginFailed = $false
        }
    }

    It 'Records why the sign-in was stopped, so the driver can report it instead of retrying' {
        InModuleScope 'OmadaWeb.PS' {
            Stop-OmadaLogin -Message 'AADSTS50178: ... does not exist in tenant ...' -Code 'AADSTS50178' -Reason 'Account unknown in the tenant.' -Url 'https://omada.example.com/logon.aspx' -Engine 'WebView2' -WarningAction SilentlyContinue | Should -BeTrue

            $Script:LoginAbortReason | Should -Not -BeNullOrEmpty
            $Script:LoginAbortReason.Code | Should -Be 'AADSTS50178'
            $Script:LoginAbortReason.Reason | Should -Be 'Account unknown in the tenant.'
            $Script:LoginAbortReason.Engine | Should -Be 'WebView2'
            $Script:LoginAbortReason.Message | Should -BeLike '*does not exist in tenant*'
        }
    }

    It 'Stops the credential autofill along with the sign-in' {
        InModuleScope 'OmadaWeb.PS' {
            Stop-OmadaLogin -Message 'Access denied.' -WarningAction SilentlyContinue | Out-Null

            $Script:MicrosoftOnlineLogin | Should -BeFalse
            $Script:LoginFailed | Should -BeTrue
        }
    }

    It 'Reports once, however often the 150 ms timer calls it' {
        InModuleScope 'OmadaWeb.PS' {
            Stop-OmadaLogin -Message 'First.' -Code 'AADSTS50178' -WarningAction SilentlyContinue | Should -BeTrue

            Stop-OmadaLogin -Message 'Second.' -Code 'AADSTS90072' -WarningVariable Warnings -WarningAction SilentlyContinue | Should -BeFalse

            $Warnings | Should -BeNullOrEmpty
            $Script:LoginAbortReason.Message | Should -Be 'First.'
        }
    }

    It 'Names the code, the page and the message in the warning' {
        InModuleScope 'OmadaWeb.PS' {
            Stop-OmadaLogin -Message 'User account does not exist in tenant.' -Code 'AADSTS50178' -Reason 'Account unknown in the tenant.' -Url 'https://omada.example.com/logon.aspx' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

            $Warning = $Warnings -join "`n"

            $Warning | Should -BeLike '*AADSTS50178*'
            $Warning | Should -BeLike '*https://omada.example.com/logon.aspx*'
            $Warning | Should -BeLike '*does not exist in tenant*'
            $Warning | Should -BeLike '*Account unknown in the tenant.*'
        }
    }

    It 'Says that no further attempt will be made' {
        InModuleScope 'OmadaWeb.PS' {
            Stop-OmadaLogin -Message 'Access denied.' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

            ($Warnings -join "`n") | Should -BeLike '*no further attempts are made*'
        }
    }

    It 'Keeps the query string of the page URL out of the warning' {
        # A logon page URL carries the return URL and request identifiers, and this text is what
        # users paste into support tickets.
        InModuleScope 'OmadaWeb.PS' {
            Stop-OmadaLogin -Message 'Access denied.' -Url 'https://omada.example.com/logon.aspx?ReturnUrl=%2fOA%2fhome&state=secretstate' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

            ($Warnings -join "`n") | Should -Not -BeLike '*secretstate*'
            $Script:LoginAbortReason.Url | Should -Be 'https://omada.example.com/logon.aspx'
        }
    }

    It 'Redacts secret material a page quoted back at the browser' {
        InModuleScope 'OmadaWeb.PS' {
            Stop-OmadaLogin -Message 'Sign-in failed for oisauthtoken=abc123secret' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

            ($Warnings -join "`n") | Should -Not -BeLike '*abc123secret*'
            $Script:LoginAbortReason.Message | Should -Not -BeLike '*abc123secret*'
        }
    }

    It 'Reports an unusable page URL rather than failing on it' {
        InModuleScope 'OmadaWeb.PS' {
            Stop-OmadaLogin -Message 'Access denied.' -Url '' -WarningAction SilentlyContinue | Out-Null

            $Script:LoginAbortReason.Url | Should -Be 'unknown'
        }
    }

    Context 'A sign-in refused because the account belongs to another tenant' {

        BeforeAll {
            $Script:TenantError = "OpenIdConnectMessage.Error was not null, indicating an error. Error: 'invalid_request'. Error_Description (may be empty): 'AADSTS50178: User account '{EUII Hidden}' from identity provider 'https://sts.windows.net/be4c52b6-1a23-493e-a8ce-f36325d16462/' does not exist in tenant 'Example productie' and cannot access the application 'a1880835-5fff-4d48-b926-44471e6f3c6c'(example.com (Omada)) in that tenant. Trace ID: c5936087-19ec-4f9d-bbfa-9202d9218900 Correlation ID: 53b30bf1-f9c9-4ad1-8bba-5442011f3a7c Timestamp: 2026-09-10 09:08:39Z'."
        }

        It 'Names the tenants, the application and the correlation id' {
            # Everything in this list is something the reader has to paste into a portal to get any
            # further, and all of it was already in the message - just not where anyone could see it.
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                Stop-OmadaLogin -Message $TenantError -Code 'AADSTS50178' -Reason 'Account unknown in the tenant.' -Category 'WrongAccount' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

                $Warning = $Warnings -join "`n"

                $Warning | Should -BeLike '*be4c52b6-1a23-493e-a8ce-f36325d16462*'
                $Warning | Should -BeLike "*Example productie*"
                $Warning | Should -BeLike '*example.com (Omada)*'
                $Warning | Should -BeLike '*53b30bf1-f9c9-4ad1-8bba-5442011f3a7c*'
            }
        }

        It 'Says that this account will never work, and what does' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                Stop-OmadaLogin -Message $TenantError -Category 'WrongAccount' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

                $Warning = $Warnings -join "`n"

                $Warning | Should -BeLike '*no further attempts are made*'
                $Warning | Should -BeLike "*Sign in with an account of tenant 'Example productie'*"
                $Warning | Should -BeLike '*invited into it as a guest*'
            }
        }

        It 'Explains that Entra withheld the account name, instead of leaving a reader to hunt for it' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                Stop-OmadaLogin -Message $TenantError -Category 'WrongAccount' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

                ($Warnings -join "`n") | Should -BeLike '*withholds the account name*'
            }
        }

        It 'Records the category and the detail for the driver to act on' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                Stop-OmadaLogin -Message $TenantError -Category 'WrongAccount' -WarningAction SilentlyContinue | Out-Null

                $Script:LoginAbortReason.Category | Should -Be 'WrongAccount'
                $Script:LoginAbortReason.Detail.ResourceTenant | Should -Be 'Example productie'
            }
        }

        It 'Keeps the general advice for a refusal that is not about the account' {
            InModuleScope 'OmadaWeb.PS' {
                Stop-OmadaLogin -Message "Error: 'unauthorized_client'." -Category 'AppRegistration' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

                $Warning = $Warnings -join "`n"

                $Warning | Should -BeLike '*no further attempts are made*'
                $Warning | Should -Not -BeLike '*invited into it as a guest*'
            }
        }

        It 'Prints no detail lines when the message carries none' {
            InModuleScope 'OmadaWeb.PS' {
                Stop-OmadaLogin -Message 'Access denied.' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

                ($Warnings -join "`n") | Should -Not -BeLike '*Correlation*'
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
