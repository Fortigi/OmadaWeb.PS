param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Test-OmadaLogonPageError' -Tag 'Unit' {

    # The message that started this: a federated sign-in for an account the application's tenant
    # does not know, rendered by Omada on its own logon page.
    BeforeAll {
        $Script:TenantError = "OpenIdConnectMessage.Error was not null, indicating an error. Error: 'invalid_request'. Error_Description (may be empty): 'AADSTS50178: User account '{EUII Hidden}' from identity provider 'https://sts.windows.net/be4c52b6-1a23f-493e-a8ce-f36325d16462/' does not exist in tenant 'Example' and cannot access the application 'a1880835-5fff3-4d48-b926-44471e6f3c6c'(example.com (Omada)) in that tenant. The account needs to be added as an external user in the tenant first."
    }

    Context 'A page without an error' {
        It 'Reports no error for an empty message' {
            InModuleScope 'OmadaWeb.PS' {
                $Verdict = Test-OmadaLogonPageError -Message ''

                $Verdict.IsError | Should -BeFalse
                $Verdict.IsFatal | Should -BeFalse
                $Verdict.Message | Should -BeNullOrEmpty
            }
        }

        It 'Reports no error for whitespace only' {
            InModuleScope 'OmadaWeb.PS' {
                (Test-OmadaLogonPageError -Message "  `r`n  ").IsError | Should -BeFalse
            }
        }
    }

    Context 'The tenant error this exists for' {
        It 'Stops the sign-in' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                $Verdict = Test-OmadaLogonPageError -Message $TenantError -OnLogonPage -HasLogonForm:$false

                $Verdict.IsError | Should -BeTrue
                $Verdict.IsFatal | Should -BeTrue
            }
        }

        It 'Names the AADSTS code, which is what the support article is indexed by' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                (Test-OmadaLogonPageError -Message $TenantError).Code | Should -Be 'AADSTS50178'
            }
        }

        It 'Explains it as an account the tenant does not know' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                (Test-OmadaLogonPageError -Message $TenantError).Reason | Should -BeLike '*not known in the tenant*'
            }
        }

        It 'Stops it even when the page still offers a way to sign in' {
            # The page shape must not be able to talk the module into retrying an error that a
            # retry cannot change.
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                (Test-OmadaLogonPageError -Message $TenantError -OnLogonPage -HasLogonForm).IsFatal | Should -BeTrue
            }
        }
    }

    Context 'Errors the user can still act on' {
        It 'Leaves a wrong password to the user' {
            InModuleScope 'OmadaWeb.PS' {
                $Verdict = Test-OmadaLogonPageError -Message 'The user name or password is incorrect.' -OnLogonPage -HasLogonForm

                $Verdict.IsError | Should -BeTrue
                $Verdict.IsFatal | Should -BeFalse
            }
        }

        It 'Leaves an error the identity provider may recover from' -TestCases @(
            @{ Message = 'Sign-in failed: server_error' }
            @{ Message = 'Sign-in failed: temporarily_unavailable' }
            @{ Message = 'Sign-in failed: interaction_required' }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Message = $Message } {
                (Test-OmadaLogonPageError -Message $Message -OnLogonPage -HasLogonForm).IsFatal | Should -BeFalse
            }
        }
    }

    Context 'Any error on a sign-in page that offers nothing to retry with' {
        It 'Stops the sign-in even when the wording is unknown' {
            # The widening: Omada versions and themes do not agree on the wording, so a logon page
            # that reports a failure and has no field to correct it in is terminal on its shape.
            InModuleScope 'OmadaWeb.PS' {
                $Verdict = Test-OmadaLogonPageError -Message 'Something went wrong. Please contact your administrator.' -OnLogonPage -HasLogonForm:$false

                $Verdict.IsFatal | Should -BeTrue
                $Verdict.Reason | Should -BeLike '*offers no way to sign in again*'
            }
        }

        It 'Leaves the same error alone when it is not a sign-in page' {
            # An error on an ordinary Omada page says nothing about a sign-in that may still be
            # running, so only a recognized identity-provider failure ends one from there.
            InModuleScope 'OmadaWeb.PS' {
                $Verdict = Test-OmadaLogonPageError -Message 'Something went wrong. Please contact your administrator.' -OnLogonPage:$false -HasLogonForm:$false

                $Verdict.IsError | Should -BeTrue
                $Verdict.IsFatal | Should -BeFalse
            }
        }

        It 'Still stops a recognized identity-provider failure off a sign-in page' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                (Test-OmadaLogonPageError -Message $TenantError -OnLogonPage:$false -HasLogonForm:$false).IsFatal | Should -BeTrue
            }
        }
    }

    Context 'Identity-provider failures other than AADSTS' {
        It 'Stops the sign-in for <Message>' -TestCases @(
            @{ Message = "Error: 'invalid_request'."; Code = 'invalid_request' }
            @{ Message = "Error: 'access_denied'."; Code = 'access_denied' }
            @{ Message = "Error: 'unauthorized_client'."; Code = 'unauthorized_client' }
            @{ Message = "Error: 'consent_required'."; Code = 'consent_required' }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Message = $Message; Code = $Code } {
                $Verdict = Test-OmadaLogonPageError -Message $Message -OnLogonPage -HasLogonForm

                $Verdict.IsFatal | Should -BeTrue
                $Verdict.Code | Should -Be $Code
            }
        }
    }

    Context 'The reported message' {
        It 'Collapses the whitespace the markup left in it' {
            InModuleScope 'OmadaWeb.PS' {
                (Test-OmadaLogonPageError -Message "  Access   `r`n  denied.  " -OnLogonPage -HasLogonForm).Message | Should -Be 'Access denied.'
            }
        }

        It 'Truncates a page that dumped a stack trace into the banner' {
            InModuleScope 'OmadaWeb.PS' {
                $Verdict = Test-OmadaLogonPageError -Message ('x' * 3000) -OnLogonPage -HasLogonForm

                $Verdict.Message.Length | Should -Be 2003
                $Verdict.Message | Should -BeLike '*...'
            }
        }

        It 'Carries the element it came from through to the caller' {
            InModuleScope 'OmadaWeb.PS' {
                (Test-OmadaLogonPageError -Message 'Access denied.' -Source 'InfoText Error GlobPage').Source | Should -Be 'InfoText Error GlobPage'
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }

    Context 'Classifying what kind of refusal it is' {
        It 'Calls an account of another tenant a WrongAccount, which a different account can get past' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ TenantError = $Script:TenantError } {
                $Verdict = Test-OmadaLogonPageError -Message $TenantError -OnLogonPage

                $Verdict.Category | Should -Be 'WrongAccount'
                $Verdict.Recoverable | Should -BeTrue
            }
        }

        It 'Recognizes the same condition by its code alone, for a page served in another language' {
            # Only the number survives translation, and losing the category there would lose the one
            # remedy that works.
            InModuleScope 'OmadaWeb.PS' {
                foreach ($Code in @('AADSTS50020', 'AADSTS50178', 'AADSTS51004')) {
                    $Verdict = Test-OmadaLogonPageError -Message ("{0}: Fout bij aanmelden." -f $Code) -OnLogonPage

                    $Verdict.Category | Should -Be 'WrongAccount' -Because "$Code names an account the tenant does not know"
                    $Verdict.Recoverable | Should -BeTrue
                }
            }
        }

        It 'Does not offer another account for an application the tenant rejected' {
            InModuleScope 'OmadaWeb.PS' {
                $Verdict = Test-OmadaLogonPageError -Message "Error: 'unauthorized_client'. The client does not exist." -OnLogonPage

                $Verdict.Category | Should -Be 'AppRegistration'
                $Verdict.Recoverable | Should -BeFalse
            }
        }

        It 'Does not offer another account for an account that is simply not assigned' {
            # Same tenant, no assignment. Another account is a guess, and the answer is usually an
            # administrator's to give.
            InModuleScope 'OmadaWeb.PS' {
                $Verdict = Test-OmadaLogonPageError -Message 'AADSTS50105: The signed in user cannot access the application.' -OnLogonPage

                $Verdict.Category | Should -Be 'Authorization'
                $Verdict.Recoverable | Should -BeFalse
            }
        }

        It 'Leaves a page without an error uncategorized' {
            InModuleScope 'OmadaWeb.PS' {
                $Verdict = Test-OmadaLogonPageError -Message ''

                $Verdict.Category | Should -Be 'None'
                $Verdict.Recoverable | Should -BeFalse
            }
        }

        It 'Does not categorize an error the user can still correct in the open window' {
            InModuleScope 'OmadaWeb.PS' {
                $Verdict = Test-OmadaLogonPageError -Message 'The user name or password is incorrect.' -OnLogonPage -HasLogonForm

                $Verdict.IsFatal | Should -BeFalse
                $Verdict.Recoverable | Should -BeFalse
            }
        }

        It 'Marks a page that is final only by its shape as Unknown rather than recoverable' {
            InModuleScope 'OmadaWeb.PS' {
                $Verdict = Test-OmadaLogonPageError -Message 'Something went wrong.' -OnLogonPage

                $Verdict.IsFatal | Should -BeTrue
                $Verdict.Category | Should -Be 'Unknown'
                $Verdict.Recoverable | Should -BeFalse
            }
        }
    }

}
