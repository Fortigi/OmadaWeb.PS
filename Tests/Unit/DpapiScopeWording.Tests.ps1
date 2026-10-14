param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

# Issue #100. DPAPI without -Key is CurrentUser scope: bound to the Windows user account, not the
# machine - the account's keys can roam through a roaming profile or credential roaming, so a copy
# is not inert off the original machine and any process running as that account can decrypt it
# there too. The claim that protection is bound to "the machine", that a copy is "inert" off it, or
# that it cannot reach "another computer" survived in two generated-help sources after the first fix
# (#110): the -CookiePath HelpMessage in Set-DynamicParameter.ps1, and the Protection text
# Get-OmadaWebCacheItem reports for the cookie cache. These tests pin the corrected wording so it
# cannot regress the same way twice.

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'DPAPI scope wording' -Tag 'Unit' {
    Context '-CookiePath HelpMessage' {
        It 'Should not claim the protection is bound to the machine' {
            InModuleScope 'OmadaWeb.PS' {
                $Dictionary = Set-DynamicParameter -FunctionName 'Invoke-RestMethod'
                $HelpMessage = ($Dictionary['CookiePath'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Select-Object -First 1).HelpMessage

                $HelpMessage | Should -Not -Match 'machine where it was created'
                $HelpMessage | Should -Not -Match 'user and the machine'
                $HelpMessage | Should -Not -Match 'another computer'
                $HelpMessage | Should -Match 'Windows user account'
            }
        }
    }

    Context 'Get-OmadaWebCacheItem Protection text' {
        It 'Should not mention the machine for the encrypted cookie cache' {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ CachePath = (Join-Path $TestDrive 'Cookies') } {
                param($CachePath)

                $Script:CookieCachePath = $CachePath
                $Items = Get-OmadaWebCacheItem -Scope 'Cookies'

                $Items | Should -Not -BeNullOrEmpty
                foreach ($Item in $Items) {
                    $Item.Protection | Should -Not -Match 'machine'
                }
            }
        }
    }

    Context 'Export-OmadaSession / Import-OmadaSession help' {
        It 'Should not claim a copy of the state is inert, portable to another computer, or bound to the exporting machine' {
            $ExportHelp = Get-Help Export-OmadaSession -Full | Out-String
            $ImportHelp = Get-Help Import-OmadaSession -Full | Out-String

            $ExportHelp | Should -Not -Match 'is inert'
            $ExportHelp | Should -Not -Match 'on another computer'
            $ExportHelp | Should -Not -Match 'machine it was exported'

            $ImportHelp | Should -Not -Match 'is inert'
            $ImportHelp | Should -Not -Match 'on another computer'
            $ImportHelp | Should -Not -Match 'machine it was exported'
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
