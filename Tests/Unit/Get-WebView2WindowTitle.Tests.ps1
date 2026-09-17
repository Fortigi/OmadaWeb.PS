param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-WebView2WindowTitle' -Tag 'Unit' {
    It 'Should show only the host, dropping login_hint, state and nonce from the sign-in URI' {
        InModuleScope 'OmadaWeb.PS' {
            $Uri = [System.Uri]'https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id=abc&login_hint=someone%40example.com&state=xyz&nonce=123'

            $Title = Get-WebView2WindowTitle -Uri $Uri

            $Title | Should -Be 'OmadaWeb.PS - login.microsoftonline.com'
            $Title | Should -Not -Match 'login_hint'
            $Title | Should -Not -Match 'state='
            $Title | Should -Not -Match 'nonce'
        }
    }
}
