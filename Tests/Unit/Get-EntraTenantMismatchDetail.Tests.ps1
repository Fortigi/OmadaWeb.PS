param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-EntraTenantMismatchDetail' -Tag 'Unit' {

    BeforeAll {
        # The message this function was written for, with the tenant, application and account of the
        # report it came from replaced. The shape is untouched, including the brackets inside the
        # application's display name - which is what makes the application name hard to read out.
        $Script:TenantError = "OpenIdConnectMessage.Error was not null, indicating an error. Error: 'invalid_request'. Error_Description (may be empty): 'AADSTS50178: User account '{EUII Hidden}' from identity provider 'https://sts.windows.net/be4c52b6-1a23-493e-a8ce-f36325d16462/' does not exist in tenant 'Example productie' and cannot access the application 'a1880835-5fff-4d48-b926-44471e6f3c6c'(example.com (Omada)) in that tenant. The account needs to be added as an external user in the tenant first. Sign out and sign in again with a different Azure Active Directory user account. Trace ID: c5936087-19ec-4f9d-bbfa-9202d9218900 Correlation ID: 53b30bf1-f9c9-4ad1-8bba-5442011f3a7c Timestamp: 2026-09-10 09:08:39Z'."
    }

    Context 'A message that carries nothing to report' {
        It 'Reports no detail for an empty message' {
            InModuleScope 'OmadaWeb.PS' {
                $Detail = Get-EntraTenantMismatchDetail -Message ''

                $Detail.HasDetail | Should -BeFalse
                $Detail.AccountTenantId | Should -BeNullOrEmpty
            }
        }

        It 'Reports no detail for an unrelated banner' {
            InModuleScope 'OmadaWeb.PS' {
                (Get-EntraTenantMismatchDetail -Message 'The user name or password is incorrect.').HasDetail | Should -BeFalse
            }
        }

        It 'Returns a boolean rather than nothing, so a caller can branch on it' {
            # A pipeline that filters to nothing yields $null, and $null is not $false under the
            # StrictMode the suite runs with.
            InModuleScope 'OmadaWeb.PS' {
                (Get-EntraTenantMismatchDetail -Message 'Nothing here.').HasDetail | Should -BeOfType [bool]
            }
        }
    }

    Context 'The cross-tenant refusal' {
        It 'Names the tenant the account belongs to' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                (Get-EntraTenantMismatchDetail -Message $TenantError).AccountTenantId | Should -Be 'be4c52b6-1a23-493e-a8ce-f36325d16462'
            }
        }

        It 'Names the tenant the application lives in' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                (Get-EntraTenantMismatchDetail -Message $TenantError).ResourceTenant | Should -Be 'Example productie'
            }
        }

        It 'Names the application by id' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                (Get-EntraTenantMismatchDetail -Message $TenantError).ApplicationId | Should -Be 'a1880835-5fff-4d48-b926-44471e6f3c6c'
            }
        }

        It 'Keeps the brackets that are part of the application display name' {
            # 'example.com (Omada)' closes with two brackets in a row. Stopping at the first one
            # loses the half of the name that says which application this is.
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                (Get-EntraTenantMismatchDetail -Message $TenantError).ApplicationName | Should -Be 'example.com (Omada)'
            }
        }

        It 'Carries the correlation id, which is how the attempt is found in the sign-in logs' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                $Detail = Get-EntraTenantMismatchDetail -Message $TenantError

                $Detail.CorrelationId | Should -Be '53b30bf1-f9c9-4ad1-8bba-5442011f3a7c'
                $Detail.TraceId | Should -Be 'c5936087-19ec-4f9d-bbfa-9202d9218900'
                $Detail.Timestamp | Should -Be '2026-09-10 09:08:39Z'
            }
        }

        It 'Records that Entra withheld the account name' {
            # The one thing the reader will look for and not find. Saying so is the difference
            # between an answer and a hunt.
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                (Get-EntraTenantMismatchDetail -Message $TenantError).AccountNameWithheld | Should -BeTrue
            }
        }

        It 'Reads the message however the markup wrapped it' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                $Wrapped = $TenantError -replace ' ', "`r`n    "

                (Get-EntraTenantMismatchDetail -Message $Wrapped).ResourceTenant | Should -Be 'Example productie'
            }
        }
    }

    Context 'The shapes the same error also arrives in' {
        It 'Takes the tenant id out of a v2.0 issuer rather than its version segment' {
            InModuleScope 'OmadaWeb.PS' {
                $Message = "AADSTS50020: User account from identity provider 'https://login.microsoftonline.com/be4c52b6-1a23-493e-a8ce-f36325d16462/v2.0' does not exist in tenant 'Example' and cannot access the application 'a1880835-5fff-4d48-b926-44471e6f3c6c'(example.com (Omada)) in that tenant."

                (Get-EntraTenantMismatchDetail -Message $Message).AccountTenantId | Should -Be 'be4c52b6-1a23-493e-a8ce-f36325d16462'
            }
        }

        It 'Reports an application that is named without a display name' {
            InModuleScope 'OmadaWeb.PS' {
                $Message = "AADSTS50178: User account does not exist in tenant 'Example' and cannot access the application 'a1880835-5fff-4d48-b926-44471e6f3c6c' in that tenant."
                $Detail = Get-EntraTenantMismatchDetail -Message $Message

                $Detail.ApplicationId | Should -Be 'a1880835-5fff-4d48-b926-44471e6f3c6c'
                $Detail.ApplicationName | Should -BeNullOrEmpty
            }
        }

        It 'Reports what it found when the rest of the sentence is in another language' {
            # Only the identifiers are stable across languages, so a message whose words do not match
            # must still yield the identifiers that do.
            InModuleScope 'OmadaWeb.PS' {
                $Message = "AADSTS50178: Trace ID: c5936087-19ec-4f9d-bbfa-9202d9218900 Correlation ID: 53b30bf1-f9c9-4ad1-8bba-5442011f3a7c"
                $Detail = Get-EntraTenantMismatchDetail -Message $Message

                $Detail.HasDetail | Should -BeTrue
                $Detail.CorrelationId | Should -Be '53b30bf1-f9c9-4ad1-8bba-5442011f3a7c'
                $Detail.ResourceTenant | Should -BeNullOrEmpty
            }
        }
    }
}
