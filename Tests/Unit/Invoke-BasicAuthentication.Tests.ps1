param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-BasicAuthentication' -Tag 'Unit' {
    It 'Should add a Basic Authorization header built from the provided Credential' {
        InModuleScope 'OmadaWeb.PS' {
            $Credential = New-Object System.Management.Automation.PSCredential('user', (ConvertTo-SecureString 'password' -AsPlainText -Force))
            $BoundParams = @{ Credential = $Credential; Headers = @{} }

            Invoke-BasicAuthentication

            $Expected = 'Basic {0}' -f [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes('user:password'))
            $BoundParams.Headers.Authorization | Should -Be $Expected
        }
    }

    It 'Should prompt for credentials when none are provided' {
        $Credential = New-Object System.Management.Automation.PSCredential('prompted-user', (ConvertTo-SecureString 'prompted-pass' -AsPlainText -Force))
        InModuleScope 'OmadaWeb.PS' -Parameters @{ Credential = $Credential } {
            Mock Get-Credential { $Credential }

            $BoundParams = @{ Headers = @{} }

            Invoke-BasicAuthentication

            Should -Invoke Get-Credential -Times 1
            $BoundParams.Headers.Authorization | Should -Match '^Basic '
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
