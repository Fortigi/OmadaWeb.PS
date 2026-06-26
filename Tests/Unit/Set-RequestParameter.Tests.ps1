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
                }
                $Result = Set-RequestParameter
                $Result.Keys | Should -Contain 'Uri'
                $Result.Keys | Should -Contain 'Method'
                $Result.Keys | Should -Not -Contain 'AuthenticationType'
                $Result.Keys | Should -Not -Contain 'EntraIdTenantId'
                $Result.Keys | Should -Not -Contain 'ForceAuthentication'
                $Result.Keys | Should -Not -Contain 'CookiePath'
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
                    NotAParam  = 'should be excluded'
                }
                $Result = Set-RequestParameter -InvokeOmadaRequest
                $Result.Keys | Should -Contain 'Uri'
                $Result.Keys | Should -Contain 'Method'
                $Result.Keys | Should -Not -Contain 'NotAParam'
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
