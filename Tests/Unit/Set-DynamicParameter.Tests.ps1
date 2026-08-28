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
            foreach ($Name in @('AuthenticationType', 'EntraIdTenantId', 'CookiePath', 'ForceAuthentication', 'InPrivate', 'UseWebView2', 'SessionKey')) {
                $Dictionary.ContainsKey($Name) | Should -Be $true
            }
        }
    }

    It 'Should add a SessionKey parameter of type string' {
        InModuleScope 'OmadaWeb.PS' {
            $Dictionary = Set-DynamicParameter -FunctionName 'Invoke-RestMethod'
            $Dictionary['SessionKey'].ParameterType | Should -Be ([string])
        }
    }

    It 'Should default AuthenticationType to WebView2' {
        InModuleScope 'OmadaWeb.PS' {
            $Dictionary = Set-DynamicParameter -FunctionName 'Invoke-RestMethod'
            $Dictionary['AuthenticationType'].Value | Should -Be 'WebView2'
        }
    }

    It 'Should describe Windows authentication using Negotiate' {
        InModuleScope 'OmadaWeb.PS' {
            $Dictionary = Set-DynamicParameter -FunctionName 'Invoke-RestMethod'
            $HelpMessage = ($Dictionary['AuthenticationType'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Select-Object -First 1).HelpMessage

            $HelpMessage | Should -Match "Windows.+Negotiate"
            $HelpMessage | Should -Match "Kerberos/NTLM"
            $HelpMessage | Should -Not -Match "Windows.+Bearer"
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

    It 'Should add a -Paged parameter for Invoke-RestMethod' {
        InModuleScope 'OmadaWeb.PS' {
            $Dictionary = Set-DynamicParameter -FunctionName 'Invoke-RestMethod'
            $Dictionary.ContainsKey('Paged') | Should -Be $true
            $Dictionary['Paged'].ParameterType | Should -Be ([System.Management.Automation.SwitchParameter])
        }
    }

    It 'Should add the retry parameters for <FunctionName>' -ForEach @(
        @{ FunctionName = 'Invoke-RestMethod' }
        @{ FunctionName = 'Invoke-WebRequest' }
    ) {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ FunctionName = $FunctionName } {
            param($FunctionName)
            # Declared by the module for both engines, rather than inherited from the native cmdlet,
            # which only offers them on PowerShell 7 - so the surface must not depend on the engine.
            $Dictionary = Set-DynamicParameter -FunctionName $FunctionName

            $Dictionary.ContainsKey('MaximumRetryCount') | Should -Be $true
            $Dictionary['MaximumRetryCount'].ParameterType | Should -Be ([int])
            $Dictionary['MaximumRetryCount'].Value | Should -Be 3

            $Dictionary.ContainsKey('RetryIntervalSec') | Should -Be $true
            $Dictionary['RetryIntervalSec'].ParameterType | Should -Be ([int])
            $Dictionary['RetryIntervalSec'].Value | Should -Be 2
        }
    }

    It 'Should alias MaxRetryCount onto MaximumRetryCount' {
        InModuleScope 'OmadaWeb.PS' {
            $Dictionary = Set-DynamicParameter -FunctionName 'Invoke-RestMethod'
            $AliasAttribute = $Dictionary['MaximumRetryCount'].Attributes | Where-Object { $_ -is [System.Management.Automation.AliasAttribute] } | Select-Object -First 1

            $AliasAttribute.AliasNames | Should -Contain 'MaxRetryCount'
        }
    }

    It 'Should document the retry policy, its default and how to switch it off' {
        InModuleScope 'OmadaWeb.PS' {
            $Dictionary = Set-DynamicParameter -FunctionName 'Invoke-RestMethod'
            $HelpMessage = ($Dictionary['MaximumRetryCount'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Select-Object -First 1).HelpMessage

            $HelpMessage | Should -Match 'Defaults to 3'
            $HelpMessage | Should -Match '-MaximumRetryCount 0'
            $HelpMessage | Should -Match 'Retry-After'
        }
    }

    It 'Should not add a -Paged parameter for Invoke-WebRequest' {
        InModuleScope 'OmadaWeb.PS' {
            $Dictionary = Set-DynamicParameter -FunctionName 'Invoke-WebRequest'
            $Dictionary.ContainsKey('Paged') | Should -Be $false
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
