param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Test-WebView2NavigationReady' -Tag 'Unit' {
    It 'Should be ready when no clear is pending' {
        InModuleScope 'OmadaWeb.PS' {
            $SessionContext = [pscustomobject]@{ BrowserDataClearPending = $false }
            Test-WebView2NavigationReady -SessionContext $SessionContext -Source 'about:blank' | Should -BeTrue
        }
    }

    It 'Should not be ready while a clear is pending' {
        InModuleScope 'OmadaWeb.PS' {
            $SessionContext = [pscustomobject]@{ BrowserDataClearPending = $true }
            Test-WebView2NavigationReady -SessionContext $SessionContext -Source 'about:blank' | Should -BeFalse
        }
    }

    It 'Should be ready again once the pending flag clears' {
        InModuleScope 'OmadaWeb.PS' {
            $SessionContext = [pscustomobject]@{ BrowserDataClearPending = $true }
            Test-WebView2NavigationReady -SessionContext $SessionContext -Source 'about:blank' | Should -BeFalse

            $SessionContext.BrowserDataClearPending = $false
            Test-WebView2NavigationReady -SessionContext $SessionContext -Source 'about:blank' | Should -BeTrue
        }
    }

    It 'Should not be ready when Source is not about:blank' {
        InModuleScope 'OmadaWeb.PS' {
            $SessionContext = [pscustomobject]@{ BrowserDataClearPending = $false }
            Test-WebView2NavigationReady -SessionContext $SessionContext -Source ([System.Uri]'https://login.microsoftonline.com/') | Should -BeFalse
        }
    }
}
