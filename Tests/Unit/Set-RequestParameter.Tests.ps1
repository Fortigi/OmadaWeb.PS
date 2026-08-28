param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Set-RequestParameter' -Tag 'Unit' {
    BeforeAll {
        InModuleScope 'OmadaWeb.PS' {
            # Each test builds its own context instead of relying on ambient variables inherited
            # from the caller's scope. Script: so the definition lands in the module's scope and
            # stays visible to the InModuleScope block of every It below.
            function Script:New-TestRequestContext {
                param(
                    [hashtable]$BoundParams,
                    [Microsoft.PowerShell.Commands.WebRequestSession]$Session = ([Microsoft.PowerShell.Commands.WebRequestSession]::new()),
                    [string]$Key = 'unit-test-set-requestparameter'
                )

                return New-OmadaRequestContext -BoundParams $BoundParams -Session $Session -SessionContext (Get-OmadaSessionContext -Key $Key)
            }
        }
    }

    Context 'Contract' {
        It 'Should require a RequestContext' {
            InModuleScope 'OmadaWeb.PS' {
                # Asserted through the parameter metadata rather than by calling the function
                # without it: in an interactive host a missing mandatory parameter prompts rather
                # than throwing, which would hang the run.
                (Get-Command Set-RequestParameter).Parameters['RequestContext'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
            }
        }

        It 'Should read the context without modifying the bound parameters' {
            InModuleScope 'OmadaWeb.PS' {
                # Unlike the authentication helpers, this one is a pure reader: it returns a new
                # hashtable and must leave the caller's own parameter set untouched.
                $BoundParams = @{ Uri = 'https://example.omada.cloud'; Method = 'GET'; SessionKey = 'user-a' }
                $Before = @($BoundParams.Keys | Sort-Object)

                Set-RequestParameter -RequestContext (New-TestRequestContext -BoundParams $BoundParams) | Out-Null

                @($BoundParams.Keys | Sort-Object) | Should -Be $Before
            }
        }
    }

    Context 'Default mode (Invoke-OmadaRestMethod/Invoke-OmadaWebRequest)' {
        It 'Should exclude Omada-specific parameters not understood by the native cmdlets' {
            InModuleScope 'OmadaWeb.PS' {
                $BoundParams = @{
                    Uri                 = 'https://example.omada.cloud'
                    Method              = 'GET'
                    AuthenticationType  = 'Basic'
                    EntraIdTenantId     = 'tenant'
                    ForceAuthentication = $true
                    CookiePath          = 'C:\Temp'
                    Paged               = $true
                    SessionKey          = 'user-a'
                }
                $Result = Set-RequestParameter -RequestContext (New-TestRequestContext -BoundParams $BoundParams)
                $Result.Keys | Should -Contain 'Uri'
                $Result.Keys | Should -Contain 'Method'
                $Result.Keys | Should -Not -Contain 'AuthenticationType'
                $Result.Keys | Should -Not -Contain 'EntraIdTenantId'
                $Result.Keys | Should -Not -Contain 'ForceAuthentication'
                $Result.Keys | Should -Not -Contain 'CookiePath'
                $Result.Keys | Should -Not -Contain 'Paged'
                $Result.Keys | Should -Not -Contain 'SessionKey'
            }
        }

        It 'Should exclude the retry parameters, which the module implements around the native call' {
            InModuleScope 'OmadaWeb.PS' {
                # Passing these on would nest PowerShell 7's own retry loop inside the module's,
                # retrying each attempt again and ignoring Retry-After on the inner one.
                $BoundParams = @{
                    Uri               = 'https://example.omada.cloud'
                    Method            = 'GET'
                    MaximumRetryCount = 3
                    RetryIntervalSec  = 2
                }
                $Result = Set-RequestParameter -RequestContext (New-TestRequestContext -BoundParams $BoundParams)

                $Result.Keys | Should -Contain 'Uri'
                $Result.Keys | Should -Not -Contain 'MaximumRetryCount'
                $Result.Keys | Should -Not -Contain 'RetryIntervalSec'
            }
        }
    }

    Context '-InvokeOmadaRequest mode' {
        It 'Should only exclude parameters that Invoke-OmadaRequest does not declare' {
            InModuleScope 'OmadaWeb.PS' {
                # Invoke-OmadaRequest exposes Uri/Method as dynamic parameters wrapping the native cmdlet
                # named by $Script:FunctionName; without it set, Get-Command can't resolve them.
                $Script:FunctionName = 'Invoke-RestMethod'
                $BoundParams = @{
                    Uri        = 'https://example.omada.cloud'
                    Method     = 'GET'
                    SessionKey = 'user-a'
                    NotAParam  = 'should be excluded'
                }
                $Result = Set-RequestParameter -RequestContext (New-TestRequestContext -BoundParams $BoundParams) -InvokeOmadaRequest
                $Result.Keys | Should -Contain 'Uri'
                $Result.Keys | Should -Contain 'Method'
                $Result.Keys | Should -Not -Contain 'NotAParam'
            }
        }

        It 'Should forward SessionKey to the Invoke-OmadaRequest retry call since it is one of its own dynamic parameters' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:FunctionName = 'Invoke-RestMethod'
                $BoundParams = @{
                    Uri        = 'https://example.omada.cloud'
                    Method     = 'GET'
                    SessionKey = 'user-a'
                }
                $Result = Set-RequestParameter -RequestContext (New-TestRequestContext -BoundParams $BoundParams) -InvokeOmadaRequest
                $Result.Keys | Should -Contain 'SessionKey'
                $Result.SessionKey | Should -Be 'user-a'
            }
        }
    }

    Context 'Verbose output' {
        It 'Should log the parameter set without the Basic header, the session cookie or the password' {
            InModuleScope 'OmadaWeb.PS' {
                $Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                $Session.Cookies.Add((New-Object System.Net.Cookie('oisauthtoken', 'cookie-secret-value', '/', 'example.omada.cloud')))
                $BoundParams = @{
                    Uri        = 'https://example.omada.cloud/OData'
                    Method     = 'POST'
                    Headers    = @{ Authorization = 'Basic dXNlcjpTdXAzclNlY3JldCE=' }
                    WebSession = $Session
                    Credential = New-Object System.Management.Automation.PSCredential('omada\svc_sql', (ConvertTo-SecureString 'Sup3rSecret!' -AsPlainText -Force))
                    Body       = '{"C_QUERY":"SELECT * FROM dbo.Person"}'
                }
                $RequestContext = New-TestRequestContext -BoundParams $BoundParams -Session $Session

                # Keep the verbose records only. The function also returns the parameter hashtable,
                # and formatting that for comparison would print the very values under test - a
                # property of this test, not of the log line it is checking.
                $VerboseOutput = ((Set-RequestParameter -RequestContext $RequestContext -Verbose 4>&1) | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }) | Out-String

                # Nothing secret.
                $VerboseOutput | Should -Not -Match 'dXNlcjpTdXAzclNlY3JldCE'
                $VerboseOutput | Should -Not -Match 'cookie-secret-value'
                $VerboseOutput | Should -Not -Match 'Sup3rSecret'
                $VerboseOutput | Should -Not -Match 'dbo\.Person'

                # Still useful: which account, which endpoint, which method.
                $VerboseOutput | Should -Match 'svc_sql'
                $VerboseOutput | Should -Match 'example\.omada\.cloud'
                $VerboseOutput | Should -Match 'POST'
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
