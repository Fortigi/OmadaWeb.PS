param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-WindowsAuthentication' -Tag 'Unit' {
    BeforeAll {
        InModuleScope 'OmadaWeb.PS' {
            # Each test builds its own context instead of relying on ambient variables inherited
            # from the caller's scope. Script: so the definition lands in the module's scope and
            # stays visible to the InModuleScope block of every It below.
            function Script:New-TestRequestContext {
                param(
                    [hashtable]$BoundParams,
                    [string]$Key = 'unit-test-windows-authentication'
                )

                return New-OmadaRequestContext -BoundParams $BoundParams -Session ([Microsoft.PowerShell.Commands.WebRequestSession]::new()) -SessionContext (Get-OmadaSessionContext -Key $Key)
            }
        }
    }

    Context 'Contract' {
        It 'Should require a RequestContext' {
            InModuleScope 'OmadaWeb.PS' {
                # Asserted through the parameter metadata rather than by calling the function
                # without it: in an interactive host a missing mandatory parameter prompts rather
                # than throwing, which would hang the run.
                (Get-Command Invoke-WindowsAuthentication).Parameters['RequestContext'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
            }
        }

        It 'Should return the same context instance it was given' {
            InModuleScope 'OmadaWeb.PS' {
                $Credential = New-Object System.Management.Automation.PSCredential('domain\user', (ConvertTo-SecureString 'password' -AsPlainText -Force))
                $RequestContext = New-TestRequestContext -BoundParams @{ Credential = $Credential; Headers = @{} }

                $Returned = Invoke-WindowsAuthentication -RequestContext $RequestContext

                [object]::ReferenceEquals($Returned, $RequestContext) | Should -BeTrue
            }
        }
    }

    It 'Should set the Credential in BoundParams from the provided Credential' {
        InModuleScope 'OmadaWeb.PS' {
            $Credential = New-Object System.Management.Automation.PSCredential('domain\user', (ConvertTo-SecureString 'password' -AsPlainText -Force))
            $BoundParams = @{ Credential = $Credential; Headers = @{} }

            Invoke-WindowsAuthentication -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null

            $BoundParams.Credential | Should -Be $Credential
        }
    }

    It 'Should not set Authentication in BoundParams' {
        InModuleScope 'OmadaWeb.PS' {
            $Credential = New-Object System.Management.Automation.PSCredential('domain\user', (ConvertTo-SecureString 'password' -AsPlainText -Force))
            $BoundParams = @{ Credential = $Credential; Headers = @{} }

            Invoke-WindowsAuthentication -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null

            $BoundParams.ContainsKey('Authentication') | Should -Be $false
        }
    }

    It 'Should remove a pre-existing Authorization header' {
        InModuleScope 'OmadaWeb.PS' {
            $Credential = New-Object System.Management.Automation.PSCredential('domain\user', (ConvertTo-SecureString 'password' -AsPlainText -Force))
            $BoundParams = @{ Credential = $Credential; Headers = @{ Authorization = '******' } }

            Invoke-WindowsAuthentication -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null

            $BoundParams.Headers.Keys | Should -Not -Contain 'Authorization'
        }
    }

    It 'Should not add a Basic Authorization header' {
        InModuleScope 'OmadaWeb.PS' {
            $Credential = New-Object System.Management.Automation.PSCredential('domain\user', (ConvertTo-SecureString 'password' -AsPlainText -Force))
            $BoundParams = @{ Credential = $Credential; Headers = @{} }

            Invoke-WindowsAuthentication -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null

            $BoundParams.Headers.Keys | Should -Not -Contain 'Authorization'
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

            Invoke-WindowsAuthentication -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null

            Should -Invoke Get-Credential -Times 1
            $BoundParams.Credential | Should -Not -BeNullOrEmpty
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
