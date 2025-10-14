BeforeAll {
    $ModulePath = Join-Path $(Split-Path $PSScriptRoot) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1'
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop -Prefix Test

    $RandomPort = Get-Random -Minimum 17000 -Maximum 19000

    . (Join-Path $PSScriptRoot 'Start-WebServer.ps1') -Action Start -Port $RandomPort -Force | Out-Null
    Start-Sleep -Seconds 2
    $Uri = "http://localhost:{0}/" -f $RandomPort
}

Describe 'Invoke-TestOmadaRestMethod' {
    Context 'Function Definition' {
        It 'Should have Invoke-(Test)OmadaODataMethod alias' {
            (Get-Alias Invoke-TestOmadaODataMethod).ReferencedCommand.Name | Should -Eq 'Invoke-TestOmadaRestMethod'
        }

        It 'Should have CmdletBinding attribute' {
            (Get-Command Invoke-TestOmadaRestMethod).CmdletBinding | Should -Be $true
        }

        It 'Should have DefaultParameterSetName set to StandardMethod' {
            $cmd = Get-Command Invoke-TestOmadaRestMethod
            $cmd.DefaultParameterSet | Should -Be 'StandardMethod'
        }
    }

    Context 'Process Block - Success' {
        It 'Should return result from Invoke-(Test)OmadaRequest' {
            $result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType None
            $result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRequest using Basic Authentication' {
            $result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType Basic -Credential (New-Object System.Management.Automation.PSCredential("user", (ConvertTo-SecureString "password" -AsPlainText -Force))) -AllowUnencryptedAuthentication
            $result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRequest using Windows Authentication' {
            $result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType Windows -Credential (New-Object System.Management.Automation.PSCredential("user", (ConvertTo-SecureString "password" -AsPlainText -Force))) -AllowUnencryptedAuthentication
            $result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRequest using Integrated Authentication' {
            $result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType Integrated -AllowUnencryptedAuthentication
            $result | Should -Be "OK"
        }
    }

    Context 'Process Block - Error Handling' {
        It 'Should throw terminating error when Invoke-OmadaRequest fails' {
            InModuleScope 'OmadaWeb.PS' {
                Mock Invoke-OmadaRequest { throw "Test Error" }
            }
            { Invoke-TestOmadaRestMethod -Uri "http://localhost" -ErrorAction Stop } | Should -Throw
        }
    }
}

AfterAll {
    . (Join-Path $PSScriptRoot 'Start-WebServer.ps1') -Port $RandomPort -Action Stop -Force | Out-Null
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}