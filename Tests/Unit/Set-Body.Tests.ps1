param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Set-Body' -Tag 'Unit' {
    BeforeAll {
        InModuleScope 'OmadaWeb.PS' {
            # Each test builds its own context instead of relying on ambient variables inherited
            # from the caller's scope, so the function under test is exercised in isolation.
            # Script: so the definition lands in the module's scope and stays visible to the
            # InModuleScope block of every It below, rather than only inside this one.
            function Script:New-TestRequestContext {
                param(
                    [hashtable]$BoundParams,
                    [string]$Key = 'unit-test-set-body'
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
                (Get-Command Set-Body).Parameters['RequestContext'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
            }
        }

        It 'Should return the same context instance it was given' {
            InModuleScope 'OmadaWeb.PS' {
                $RequestContext = New-TestRequestContext -BoundParams @{ Method = 'POST'; Headers = @{} ; Body = @{ key = 'value' } }

                $Returned = Set-Body -RequestContext $RequestContext

                [object]::ReferenceEquals($Returned, $RequestContext) | Should -BeTrue
            }
        }
    }

    Context 'Missing Body' {
        It 'Should throw a terminating error when -Body is empty' {
            InModuleScope 'OmadaWeb.PS' {
                $RequestContext = New-TestRequestContext -BoundParams @{ Method = 'POST'; Headers = @{} ; Body = $null }
                { Set-Body -RequestContext $RequestContext -ErrorAction Stop } | Should -Throw
            }
        }
    }

    Context 'Content-Type header' {
        It 'Should add Content-Type application/json when not present' {
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{ Method = 'POST'; Headers = @{} ; Body = @{ key = 'value' } }
                Set-Body -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null
                $BoundParams.Headers.'Content-Type' | Should -Be 'application/json'
            }
        }

        It 'Should overwrite an existing Content-Type header with application/json when the body is converted' {
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{ Method = 'POST'; Headers = @{ 'Content-Type' = 'application/x-www-form-urlencoded' } ; Body = @{ key = 'value' } }
                Set-Body -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null
                $BoundParams.Headers.'Content-Type' | Should -Be 'application/json'
                ($BoundParams.Body | ConvertFrom-Json).key | Should -Be 'value'
            }
        }

        It 'Should keep a caller-supplied Content-Type when the body is a raw string (issue #105)' {
            # A string body is passed through as-is, so a caller who set their own Content-Type
            # (e.g. application/xml) must not have it silently overwritten with application/json.
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{ Method = 'POST'; Headers = @{ 'Content-Type' = 'application/xml' } ; Body = '<xml>raw</xml>' }
                Set-Body -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null
                $BoundParams.Headers.'Content-Type' | Should -Be 'application/xml'
                $BoundParams.Body | Should -Be '<xml>raw</xml>'
            }
        }

        It 'Should default a raw string body with no Content-Type header to application/json' {
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{ Method = 'POST'; Headers = @{} ; Body = '{"already":"json"}' }
                Set-Body -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null
                $BoundParams.Headers.'Content-Type' | Should -Be 'application/json'
            }
        }

        It 'Should recognise a caller-supplied Content-Type header regardless of its casing (issue #105)' {
            # The Headers dictionary is a case-insensitive copy since #103, so a lowercase
            # "content-type" from the caller must be recognised as already present.
            InModuleScope 'OmadaWeb.PS' {
                $Headers = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
                $Headers['content-type'] = 'application/xml'
                $BoundParams = @{ Method = 'POST'; Headers = $Headers ; Body = '<xml>raw</xml>' }
                Set-Body -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null
                $BoundParams.Headers['content-type'] | Should -Be 'application/xml'
            }
        }
    }

    Context 'Body conversion' {
        It 'Should convert a Hashtable body to JSON' {
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{ Method = 'POST'; Headers = @{} ; Body = @{ key = 'value' } }
                Set-Body -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null
                $BoundParams.Body | Should -BeOfType [string]
                ($BoundParams.Body | ConvertFrom-Json).key | Should -Be 'value'
            }
        }

        It 'Should convert an ordered dictionary body to JSON' {
            InModuleScope 'OmadaWeb.PS' {
                $Ordered = [ordered]@{ key = 'value' }
                $BoundParams = @{ Method = 'POST'; Headers = @{} ; Body = $Ordered }
                Set-Body -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null
                ($BoundParams.Body | ConvertFrom-Json).key | Should -Be 'value'
            }
        }

        It 'Should convert a PSCustomObject body to JSON' {
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{ Method = 'POST'; Headers = @{} ; Body = [PSCustomObject]@{ key = 'value' } }
                Set-Body -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null
                ($BoundParams.Body | ConvertFrom-Json).key | Should -Be 'value'
            }
        }

        It 'Should serialize a deeply nested body without truncation' {
            InModuleScope 'OmadaWeb.PS' {
                $NestedBody = @{
                    L1 = @{
                        L2 = @{
                            L3 = @{
                                L4 = @{
                                    L5 = @{
                                        Value = 'deep'
                                    }
                                }
                            }
                        }
                    }
                }
                $BoundParams = @{ Method = 'POST'; Headers = @{} ; Body = $NestedBody }
                Set-Body -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null
                $BoundParams.Body | Should -Not -Match 'System\.Collections\.Hashtable'
                ($BoundParams.Body | ConvertFrom-Json).L1.L2.L3.L4.L5.Value | Should -Be 'deep'
            }
        }

        It 'Should serialize nested arrays of objects' {
            InModuleScope 'OmadaWeb.PS' {
                $NestedBody = @{
                    IDENTITY = @{
                        ASSIGNMENTS = @(
                            @{ Id = 1 ; Resource = @{ Name = 'FirstResource' } }
                            @{ Id = 2 ; Resource = @{ Name = 'SecondResource' } }
                        )
                    }
                }
                $BoundParams = @{ Method = 'POST'; Headers = @{} ; Body = $NestedBody }
                Set-Body -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null
                $BoundParams.Body | Should -Not -Match 'System\.Collections\.Hashtable'
                $Result = $BoundParams.Body | ConvertFrom-Json
                ($Result.IDENTITY.ASSIGNMENTS | Measure-Object).Count | Should -Be 2
                $Result.IDENTITY.ASSIGNMENTS[1].Resource.Name | Should -Be 'SecondResource'
            }
        }

        It 'Should leave a raw string body untouched' {
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{ Method = 'POST'; Headers = @{} ; Body = '<xml>raw</xml>' }
                Set-Body -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null
                $BoundParams.Body | Should -Be '<xml>raw</xml>'
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
