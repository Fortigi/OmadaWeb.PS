param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-WindowsAuthentication' -Tag 'Unit' {
    It 'Should set the Credential in BoundParams from the provided Credential' {
        InModuleScope 'OmadaWeb.PS' {
            $Credential = New-Object System.Management.Automation.PSCredential('domain\user', (ConvertTo-SecureString 'password' -AsPlainText -Force))
            $BoundParams = @{ Credential = $Credential; Headers = @{} }

            Invoke-WindowsAuthentication

            $BoundParams.Credential | Should -Be $Credential
        }
    }

    It 'Should set Authentication to Negotiate in BoundParams on PowerShell 6+' -Skip:($PSVersionTable.PSVersion.Major -lt 6) {
        InModuleScope 'OmadaWeb.PS' {
            $Credential = New-Object System.Management.Automation.PSCredential('domain\user', (ConvertTo-SecureString 'password' -AsPlainText -Force))
            $BoundParams = @{ Credential = $Credential; Headers = @{} }

            Invoke-WindowsAuthentication

            $BoundParams.Authentication | Should -Be "Negotiate"
        }
    }

    It 'Should not add a Basic Authorization header' {
        InModuleScope 'OmadaWeb.PS' {
            $Credential = New-Object System.Management.Automation.PSCredential('domain\user', (ConvertTo-SecureString 'password' -AsPlainText -Force))
            $BoundParams = @{ Credential = $Credential; Headers = @{} }

            Invoke-WindowsAuthentication

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

            Invoke-WindowsAuthentication

            Should -Invoke Get-Credential -Times 1
            $BoundParams.Credential | Should -Not -BeNullOrEmpty
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
