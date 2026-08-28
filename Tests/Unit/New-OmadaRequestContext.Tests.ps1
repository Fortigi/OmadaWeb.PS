param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'New-OmadaRequestContext' -Tag 'Unit' {
    Context 'Shape' {
        It 'Should tag the context with the OmadaWeb.PS.RequestContext type name' {
            InModuleScope 'OmadaWeb.PS' {
                $RequestContext = New-OmadaRequestContext -BoundParams @{} -Session ([Microsoft.PowerShell.Commands.WebRequestSession]::new()) -SessionContext (Get-OmadaSessionContext -Key 'unit-test-context-shape')

                $RequestContext.PSObject.TypeNames | Should -Contain 'OmadaWeb.PS.RequestContext'
            }
        }

        It 'Should expose exactly BoundParams, Session and SessionContext' {
            InModuleScope 'OmadaWeb.PS' {
                $RequestContext = New-OmadaRequestContext -BoundParams @{} -Session ([Microsoft.PowerShell.Commands.WebRequestSession]::new()) -SessionContext (Get-OmadaSessionContext -Key 'unit-test-context-members')

                $MemberNames = @($RequestContext.PSObject.Properties.Name | Sort-Object)
                $MemberNames | Should -Be @('BoundParams', 'Session', 'SessionContext')
            }
        }
    }

    Context 'Reference semantics' {
        It 'Should hold the same object instances that were passed in, not copies' {
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{ Method = 'GET' }
                $Session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
                $SessionContext = Get-OmadaSessionContext -Key 'unit-test-context-references'

                $RequestContext = New-OmadaRequestContext -BoundParams $BoundParams -Session $Session -SessionContext $SessionContext

                # The helpers mutate what they are handed, so the context must alias the caller's
                # objects. A copy here would silently discard every header and cookie they add.
                [object]::ReferenceEquals($RequestContext.BoundParams, $BoundParams) | Should -BeTrue
                [object]::ReferenceEquals($RequestContext.Session, $Session) | Should -BeTrue
                [object]::ReferenceEquals($RequestContext.SessionContext, $SessionContext) | Should -BeTrue
            }
        }

        It 'Should surface mutations made through the context to the original hashtable' {
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{ Headers = @{} }
                $RequestContext = New-OmadaRequestContext -BoundParams $BoundParams -Session ([Microsoft.PowerShell.Commands.WebRequestSession]::new()) -SessionContext (Get-OmadaSessionContext -Key 'unit-test-context-mutation')

                $RequestContext.BoundParams.Headers.Add('X-Test', 'value')

                $BoundParams.Headers.'X-Test' | Should -Be 'value'
            }
        }
    }

    Context 'Required input' {
        It 'Should require BoundParams, Session and SessionContext' {
            InModuleScope 'OmadaWeb.PS' {
                $Parameters = (Get-Command New-OmadaRequestContext).Parameters
                foreach ($Name in @('BoundParams', 'Session', 'SessionContext')) {
                    $Parameters[$Name].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
                }
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
