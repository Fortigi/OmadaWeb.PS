param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Set-DynamicParameter' -Tag 'Unit' {
    It 'Should return a dictionary including the common Omada parameters' {
        InModuleScope 'OmadaWeb.PS' {
            $Dictionary = Set-DynamicParameter -FunctionName 'Invoke-RestMethod'
            $Dictionary | Should -BeOfType [System.Management.Automation.RuntimeDefinedParameterDictionary]
            foreach ($Name in @('AuthenticationType', 'EntraIdTenantId', 'CookiePath', 'ForceAuthentication', 'InPrivate', 'UseWebView2')) {
                $Dictionary.ContainsKey($Name) | Should -Be $true
            }
        }
    }

    It 'Should default AuthenticationType to WebView2' {
        InModuleScope 'OmadaWeb.PS' {
            $Dictionary = Set-DynamicParameter -FunctionName 'Invoke-RestMethod'
            $Dictionary['AuthenticationType'].Value | Should -Be 'WebView2'
        }
    }

    It 'Should exclude PowerShell common parameters from the generated dynamic parameters' {
        InModuleScope 'OmadaWeb.PS' {
            $Dictionary = Set-DynamicParameter -FunctionName 'Invoke-RestMethod'
            foreach ($Name in @('Verbose', 'Debug', 'WebSession', 'UseBasicParsing')) {
                $Dictionary.ContainsKey($Name) | Should -Be $false
            }
        }
    }

    It 'Should expose the native parameters of the wrapped function (e.g. Uri, Method)' {
        InModuleScope 'OmadaWeb.PS' {
            $Dictionary = Set-DynamicParameter -FunctionName 'Invoke-RestMethod'
            $Dictionary.ContainsKey('Uri') | Should -Be $true
            $Dictionary.ContainsKey('Method') | Should -Be $true
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
