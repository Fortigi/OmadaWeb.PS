param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSignInAccount' -Tag 'Unit' {

    It 'Takes the account the caller named' {
        InModuleScope 'OmadaWeb.PS' {
            $SessionContext = [PSCustomObject]@{ UserName = '  mark@example.com  '; Credential = $null; SelectAccount = $false }

            (Get-OmadaSignInAccount -SessionContext $SessionContext).UserName | Should -Be 'mark@example.com'
        }
    }

    It 'Falls back to the user name of the credential' {
        # The regression this function exists for. A session that carries only a credential - which is
        # every session built before -UserName existed, and every one built by something other than
        # Invoke-BrowserAuthentication - still names an account, and autofill has to find it there.
        InModuleScope 'OmadaWeb.PS' {
            $SessionContext = [PSCustomObject]@{
                Credential = New-Object System.Management.Automation.PSCredential('user@contoso.com', (ConvertTo-SecureString 'password' -AsPlainText -Force))
            }

            (Get-OmadaSignInAccount -SessionContext $SessionContext).UserName | Should -Be 'user@contoso.com'
        }
    }

    It 'Prefers the named account over the one on the credential' {
        InModuleScope 'OmadaWeb.PS' {
            $SessionContext = [PSCustomObject]@{
                UserName   = 'named@example.com'
                Credential = New-Object System.Management.Automation.PSCredential('other@example.com', (ConvertTo-SecureString 'x' -AsPlainText -Force))
            }

            (Get-OmadaSignInAccount -SessionContext $SessionContext).UserName | Should -Be 'named@example.com'
        }
    }

    It 'Treats a blank name as no name at all' {
        InModuleScope 'OmadaWeb.PS' {
            $SessionContext = [PSCustomObject]@{
                UserName   = '   '
                Credential = New-Object System.Management.Automation.PSCredential('fallback@example.com', (ConvertTo-SecureString 'x' -AsPlainText -Force))
            }

            (Get-OmadaSignInAccount -SessionContext $SessionContext).UserName | Should -Be 'fallback@example.com'
        }
    }

    It 'Reports no account when nobody named one' {
        InModuleScope 'OmadaWeb.PS' {
            (Get-OmadaSignInAccount -SessionContext ([PSCustomObject]@{ UserName = $null; Credential = $null })).UserName | Should -BeNullOrEmpty
        }
    }

    It 'Survives a session that carries none of these members' {
        # Read through the property bag, because under StrictMode a member that is not there is a
        # terminating error - and this is called from a timer handler, where that is not a failed
        # sign-in but a window that stops responding.
        InModuleScope 'OmadaWeb.PS' {
            $Account = Get-OmadaSignInAccount -SessionContext ([PSCustomObject]@{})

            $Account.UserName | Should -BeNullOrEmpty
            $Account.SelectAccount | Should -BeFalse
        }
    }

    It 'Survives no session at all' {
        InModuleScope 'OmadaWeb.PS' {
            $Account = Get-OmadaSignInAccount -SessionContext $null

            $Account.UserName | Should -BeNullOrEmpty
            $Account.SelectAccount | Should -BeFalse
        }
    }

    It 'Reports the account picker when it was asked for' {
        InModuleScope 'OmadaWeb.PS' {
            (Get-OmadaSignInAccount -SessionContext ([PSCustomObject]@{ SelectAccount = $true })).SelectAccount | Should -BeTrue
        }
    }
}
