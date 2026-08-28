param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-BasicAuthentication' -Tag 'Unit' {
    BeforeAll {
        InModuleScope 'OmadaWeb.PS' {
            # Each test builds its own context instead of relying on ambient variables inherited
            # from the caller's scope. Script: so the definition lands in the module's scope and
            # stays visible to the InModuleScope block of every It below.
            function Script:New-TestRequestContext {
                param(
                    [hashtable]$BoundParams,
                    [string]$Key = 'unit-test-basic-authentication'
                )

                return New-OmadaRequestContext -BoundParams $BoundParams -Session ([Microsoft.PowerShell.Commands.WebRequestSession]::new()) -SessionContext (Get-OmadaSessionContext -Key $Key)
            }
        }
    }

    Context 'Contract' {
        It 'Should require a RequestContext' {
            InModuleScope 'OmadaWeb.PS' {
                { Invoke-BasicAuthentication -ErrorAction Stop } | Should -Throw
            }
        }

        It 'Should return the same context instance it was given' {
            InModuleScope 'OmadaWeb.PS' {
                $Credential = New-Object System.Management.Automation.PSCredential('user', (ConvertTo-SecureString 'password' -AsPlainText -Force))
                $RequestContext = New-TestRequestContext -BoundParams @{ Credential = $Credential; Headers = @{} }

                $Returned = Invoke-BasicAuthentication -RequestContext $RequestContext

                [object]::ReferenceEquals($Returned, $RequestContext) | Should -BeTrue
            }
        }
    }

    It 'Should add a Basic Authorization header built from the provided Credential' {
        InModuleScope 'OmadaWeb.PS' {
            $Credential = New-Object System.Management.Automation.PSCredential('user', (ConvertTo-SecureString 'password' -AsPlainText -Force))
            $BoundParams = @{ Credential = $Credential; Headers = @{} }

            Invoke-BasicAuthentication -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null

            $Expected = 'Basic {0}' -f [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes('user:password'))
            $BoundParams.Headers.Authorization | Should -Be $Expected
        }
    }

    It 'Should prompt for credentials when none are provided' {
        $Credential = New-Object System.Management.Automation.PSCredential('prompted-user', (ConvertTo-SecureString 'prompted-pass' -AsPlainText -Force))
        InModuleScope 'OmadaWeb.PS' -Parameters @{ Credential = $Credential } {
            # Mock script blocks don't reliably close over InModuleScope -Parameters
            # variables; assign into module script scope first, then read that back.
            $Script:PromptedCredential = $Credential
            Mock Get-Credential { $Script:PromptedCredential }

            $BoundParams = @{ Headers = @{} }

            Invoke-BasicAuthentication -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null

            Should -Invoke Get-Credential -Times 1
            $BoundParams.Headers.Authorization | Should -Match '^Basic '
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
