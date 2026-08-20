param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-BrowserAuthentication' -Tag 'Unit' {
    It 'Should warn about the Selenium deprecation when the Selenium engine drives the login' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Get-DataFromWebDriver {
                @(
                    [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'cookie-value'; domain = 'localhost' },
                    'user-agent'
                )
            }
            Mock Write-OmadaDeprecationWarning {}

            # Invoke-BrowserAuthentication reads $BoundParams/$SessionContext/$Session out of its
            # caller's scope, so they are set up here rather than passed as parameters.
            # -SkipCookieCache keeps the run off the encrypted cookie cache on disk.
            $BoundParams = @{
                AuthenticationType = 'Browser'
                Headers            = @{}
                SkipCookieCache    = $true
            }
            $Session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
            $SessionContext = Get-OmadaSessionContext -Key 'unit-test-selenium-deprecation'
            $SessionContext.BaseUrl = 'http://localhost:19000/'

            Invoke-BrowserAuthentication

            Should -Invoke Get-DataFromWebDriver -Times 1 -Exactly
            Should -Invoke Write-OmadaDeprecationWarning -Times 1 -Exactly -ParameterFilter {
                $Feature -eq 'SeleniumBrowserEngine'
            }
        }
    }

    It 'Should not warn about the Selenium deprecation when WebView2 drives the login' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Get-DataFromWebView2 {
                $SessionContext.AuthCookie = [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'cookie-value'; domain = 'localhost' }
            }
            Mock Write-OmadaDeprecationWarning {}

            $BoundParams = @{
                AuthenticationType = 'WebView2'
                Headers            = @{}
                SkipCookieCache    = $true
            }
            $Session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
            $SessionContext = Get-OmadaSessionContext -Key 'unit-test-webview2-no-deprecation'
            $SessionContext.BaseUrl = 'http://localhost:19000/'

            Invoke-BrowserAuthentication

            Should -Invoke Get-DataFromWebView2 -Times 1 -Exactly
            Should -Invoke Write-OmadaDeprecationWarning -Times 0 -Exactly
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
