param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Set-RequestParameter' -Tag 'Unit' {
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
                $Result = Set-RequestParameter
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
                $Result = Set-RequestParameter -InvokeOmadaRequest
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
                $Result = Set-RequestParameter -InvokeOmadaRequest
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

                # Keep the verbose records only. The function also returns the parameter hashtable,
                # and formatting that for comparison would print the very values under test - a
                # property of this test, not of the log line it is checking.
                $VerboseOutput = ((Set-RequestParameter -Verbose 4>&1) | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }) | Out-String

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
