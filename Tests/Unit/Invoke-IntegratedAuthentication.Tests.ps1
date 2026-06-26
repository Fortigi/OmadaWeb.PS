param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-IntegratedAuthentication' -Tag 'Unit' {
    It 'Should add UseDefaultCredentials to the bound parameters' {
        InModuleScope 'OmadaWeb.PS' {
            $BoundParams = @{}

            Invoke-IntegratedAuthentication

            $BoundParams.UseDefaultCredentials | Should -Be $true
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
