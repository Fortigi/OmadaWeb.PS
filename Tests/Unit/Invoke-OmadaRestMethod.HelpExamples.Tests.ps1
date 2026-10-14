param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-OmadaRestMethod help' -Tag 'Unit' {
    It 'Should not leak the dev-505878 Okta tenant in its OAuth example' {
        $HelpText = Get-Help Invoke-OmadaRestMethod -Full | Out-String
        $HelpText | Should -Not -Match 'dev-505878'
    }
}
