param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'New-EntraSignInUri' -Tag 'Unit' {

    BeforeAll {
        $Script:Authorize = 'https://login.microsoftonline.com/be4c52b6-1a23-493e-a8ce-f36325d16462/oauth2/v2.0/authorize?client_id=abc&state=xyz'
    }

    Context 'When nobody named an account' {
        It 'Leaves the request exactly as the application built it' {
            # The default has to be indistinguishable from this function not existing.
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Authorize = $Script:Authorize } {
                New-EntraSignInUri -Uri $Authorize | Should -BeNullOrEmpty
            }
        }

        It 'Treats a blank user name as no account at all' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Authorize = $Script:Authorize } {
                New-EntraSignInUri -Uri $Authorize -UserName '   ' | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Asking for a named account' {
        It 'Sends the account as a login hint, and refuses an existing session for anybody else' {
            # login_hint alone is a suggestion: a session for another account answers the request
            # before the hint is read, which is the failure this whole function exists to prevent.
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Authorize = $Script:Authorize } {
                New-EntraSignInUri -Uri $Authorize -UserName 'mark@example.com' |
                    Should -Be ('{0}&login_hint=mark%40example.com&prompt=login' -f $Authorize)
            }
        }

        It 'Escapes the account name instead of pasting it into the query' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Authorize = $Script:Authorize } {
                $Rewritten = New-EntraSignInUri -Uri $Authorize -UserName 'mark@example.com&prompt=none'

                $Rewritten | Should -BeLike '*login_hint=mark%40example.com%26prompt%3Dnone*'
                $Rewritten | Should -Not -BeLike '*prompt=none*'
            }
        }

        It 'Adds the parameters to a request that carries no query at all' {
            InModuleScope 'OmadaWeb.PS' {
                New-EntraSignInUri -Uri 'https://login.microsoftonline.com/common/oauth2/authorize' -UserName 'mark@example.com' |
                    Should -Be 'https://login.microsoftonline.com/common/oauth2/authorize?login_hint=mark%40example.com&prompt=login'
            }
        }
    }

    Context 'Asking for the account picker' {
        It 'Sends prompt=select_account' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Authorize = $Script:Authorize } {
                New-EntraSignInUri -Uri $Authorize -SelectAccount | Should -Be ('{0}&prompt=select_account' -f $Authorize)
            }
        }

        It 'Refuses to combine an account name with the picker' {
            # Entra ID accepts one or the other; sending both would have it resolve by guessing.
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Authorize = $Script:Authorize } {
                New-EntraSignInUri -Uri $Authorize -UserName 'mark@example.com' -SelectAccount | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Requests it must not touch' {
        It 'Leaves another identity provider alone, so no account name is handed to it' {
            InModuleScope 'OmadaWeb.PS' {
                New-EntraSignInUri -Uri 'https://sso.contoso.com/oauth2/v2.0/authorize?client_id=abc' -UserName 'mark@example.com' | Should -BeNullOrEmpty
            }
        }

        It 'Leaves a plain HTTP request alone' {
            InModuleScope 'OmadaWeb.PS' {
                New-EntraSignInUri -Uri 'http://login.microsoftonline.com/common/oauth2/authorize' -SelectAccount | Should -BeNullOrEmpty
            }
        }

        It 'Leaves every request in the chain that is not an authorization request' {
            # A sign-in is a series of navigations on the same host. Only the first one takes these
            # parameters; the rest would be rewritten for nothing, or broken.
            InModuleScope 'OmadaWeb.PS' {
                foreach ($Uri in @(
                        'https://login.microsoftonline.com/common/login?x=1',
                        'https://login.microsoftonline.com/kmsi',
                        'https://login.microsoftonline.com/common/oauth2/v2.0/token'
                    )) {
                    New-EntraSignInUri -Uri $Uri -SelectAccount | Should -BeNullOrEmpty -Because "$Uri is not an authorization request"
                }
            }
        }

        It 'Leaves a prompt the application set itself alone' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Authorize = $Script:Authorize } {
                New-EntraSignInUri -Uri ('{0}&prompt=login' -f $Authorize) -SelectAccount | Should -BeNullOrEmpty
            }
        }

        It 'Leaves a login hint the application set itself alone, and only insists on a fresh sign-in' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Authorize = $Script:Authorize } {
                $WithHint = '{0}&login_hint=other%40example.com' -f $Authorize

                New-EntraSignInUri -Uri $WithHint -UserName 'mark@example.com' | Should -Be ('{0}&prompt=login' -f $WithHint)
            }
        }

        It 'Does nothing when the request already carries both' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Authorize = $Script:Authorize } {
                New-EntraSignInUri -Uri ('{0}&login_hint=other%40example.com&prompt=login' -f $Authorize) -UserName 'mark@example.com' | Should -BeNullOrEmpty
            }
        }

        It 'Survives a value that is not a URI at all' {
            InModuleScope 'OmadaWeb.PS' {
                New-EntraSignInUri -Uri 'not a uri' -SelectAccount | Should -BeNullOrEmpty
                New-EntraSignInUri -Uri '' -SelectAccount | Should -BeNullOrEmpty
            }
        }
    }

    Context 'WS-Federation, which cannot name an account' {
        It 'Asks for a fresh sign-in instead' {
            InModuleScope 'OmadaWeb.PS' {
                New-EntraSignInUri -Uri 'https://login.microsoftonline.com/common/wsfed?wa=wsignin1.0' -UserName 'mark@example.com' |
                    Should -Be 'https://login.microsoftonline.com/common/wsfed?wa=wsignin1.0&wfresh=0'
            }
        }

        It 'Leaves a request that already asks for one alone' {
            InModuleScope 'OmadaWeb.PS' {
                New-EntraSignInUri -Uri 'https://login.microsoftonline.com/common/wsfed?wa=wsignin1.0&wfresh=0' -SelectAccount | Should -BeNullOrEmpty
            }
        }
    }

    Context 'The other Microsoft clouds' {
        It 'Rewrites a US Government sign-in the same way' {
            InModuleScope 'OmadaWeb.PS' {
                New-EntraSignInUri -Uri 'https://login.microsoftonline.us/common/oauth2/v2.0/authorize' -SelectAccount |
                    Should -Be 'https://login.microsoftonline.us/common/oauth2/v2.0/authorize?prompt=select_account'
            }
        }
    }
}
