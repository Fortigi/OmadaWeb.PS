param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'New-DynamicParam' -Tag 'Unit' {
    Context 'Standalone dictionary creation' {
        It 'Should return a RuntimeDefinedParameterDictionary containing the parameter when no DPDictionary is supplied' {
            InModuleScope 'OmadaWeb.PS' {
                $Result = New-DynamicParam -Name 'TestParam' -Type 'string'
                $Result | Should -BeOfType [System.Management.Automation.RuntimeDefinedParameterDictionary]
                $Result.ContainsKey('TestParam') | Should -Be $true
            }
        }
    }

    Context 'Shared dictionary' {
        It 'Should add the parameter to a provided DPDictionary' {
            InModuleScope 'OmadaWeb.PS' {
                $Dictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
                New-DynamicParam -Name 'Shared' -Type 'string' -DPDictionary $Dictionary
                $Dictionary.ContainsKey('Shared') | Should -Be $true
            }
        }

        It 'Should mark the parameter as mandatory when requested' {
            InModuleScope 'OmadaWeb.PS' {
                $Dictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
                New-DynamicParam -Name 'Required' -Type 'string' -Mandatory -DPDictionary $Dictionary
                $Dictionary['Required'].Attributes[0].Mandatory | Should -Be $true
            }
        }

        It 'Should apply a ValidateSet attribute' {
            InModuleScope 'OmadaWeb.PS' {
                $Dictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
                New-DynamicParam -Name 'Choice' -Type 'string' -ValidateSet @('A', 'B') -DPDictionary $Dictionary
                $ValidateSetAttr = $Dictionary['Choice'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
                $ValidateSetAttr.ValidValues | Should -Contain 'A'
                $ValidateSetAttr.ValidValues | Should -Contain 'B'
            }
        }

        It 'Should set a default Value when provided' {
            InModuleScope 'OmadaWeb.PS' {
                $Dictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
                New-DynamicParam -Name 'WithDefault' -Type 'string' -Value 'DefaultValue' -DPDictionary $Dictionary
                $Dictionary['WithDefault'].Value | Should -Be 'DefaultValue'
            }
        }

        It 'Should resolve a Type provided as a type-name string' {
            InModuleScope 'OmadaWeb.PS' {
                $Dictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
                New-DynamicParam -Name 'SwitchParam' -Type 'System.Management.Automation.SwitchParameter' -DPDictionary $Dictionary
                $Dictionary['SwitchParam'].ParameterType | Should -Be ([System.Management.Automation.SwitchParameter])
            }
        }

        It 'Should fall back to string when the Type name cannot be resolved' {
            InModuleScope 'OmadaWeb.PS' {
                $Dictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
                New-DynamicParam -Name 'Unknown' -Type 'Not.A.Real.Type' -DPDictionary $Dictionary
                $Dictionary['Unknown'].ParameterType | Should -Be ([string])
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
