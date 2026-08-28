param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-IntegratedAuthentication' -Tag 'Unit' {
    BeforeAll {
        InModuleScope 'OmadaWeb.PS' {
            # Each test builds its own context instead of relying on ambient variables inherited
            # from the caller's scope. Script: so the definition lands in the module's scope and
            # stays visible to the InModuleScope block of every It below.
            function Script:New-TestRequestContext {
                param(
                    [hashtable]$BoundParams,
                    [string]$Key = 'unit-test-integrated-authentication'
                )

                return New-OmadaRequestContext -BoundParams $BoundParams -Session ([Microsoft.PowerShell.Commands.WebRequestSession]::new()) -SessionContext (Get-OmadaSessionContext -Key $Key)
            }
        }
    }

    Context 'Contract' {
        It 'Should require a RequestContext' {
            InModuleScope 'OmadaWeb.PS' {
                { Invoke-IntegratedAuthentication -ErrorAction Stop } | Should -Throw
            }
        }

        It 'Should return the same context instance it was given' {
            InModuleScope 'OmadaWeb.PS' {
                $RequestContext = New-TestRequestContext -BoundParams @{}

                $Returned = Invoke-IntegratedAuthentication -RequestContext $RequestContext

                [object]::ReferenceEquals($Returned, $RequestContext) | Should -BeTrue
            }
        }
    }

    It 'Should add UseDefaultCredentials to the bound parameters' {
        InModuleScope 'OmadaWeb.PS' {
            $BoundParams = @{}

            Invoke-IntegratedAuthentication -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null

            $BoundParams.UseDefaultCredentials | Should -Be $true
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
