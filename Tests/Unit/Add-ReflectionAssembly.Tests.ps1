param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

# Regression: OmadaSqlTroubleshooter loads its own pinned Microsoft.Web.WebView2.Core at
# start-up and calls this module to sign in later. LoadFrom of this module's bundled, older version then
# failed with "A different copy of assembly 'Microsoft.Web.WebView2.Core' is already loaded", and so
# did every WebView2 sign-in in that session. An assembly already loaded in the same or a newer
# version is now used instead of loading the bundled file.
#
# The versions below are invented: only their order matters. The real bundled version lives in
# Build/Dependencies.psd1 and must not be copied here (see DependencyVersionLiterals.Tests.ps1).

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    # A file that exists, standing in for the bundled assembly; its identity comes from the mock.
    $Script:AssemblyFile = Join-Path $TestDrive 'Microsoft.Web.WebView2.Core.dll'
    Set-Content -Path $Script:AssemblyFile -Value 'not a real assembly'
}

Describe 'Resolve-AssemblyLoadAction' -Tag 'Unit' {
    It 'Should load when nothing by that name is loaded' {
        InModuleScope 'OmadaWeb.PS' {
            Resolve-AssemblyLoadAction -RequestedVersion '1.0.2000.0' -LoadedVersion $null | Should -Be 'Load'
        }
    }

    It 'Should reuse a loaded <Case> version' -ForEach @(
        @{ Case = 'newer'; Loaded = '1.0.3000.0' }
        @{ Case = 'equal'; Loaded = '1.0.2000.0' }
    ) {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ Loaded = $Loaded } {
            param($Loaded)
            Resolve-AssemblyLoadAction -RequestedVersion '1.0.2000.0' -LoadedVersion $Loaded | Should -Be 'Reuse'
        }
    }

    It 'Should report a loaded older version as a conflict' {
        InModuleScope 'OmadaWeb.PS' {
            Resolve-AssemblyLoadAction -RequestedVersion '1.0.2000.0' -LoadedVersion '1.0.1000.0' | Should -Be 'Conflict'
        }
    }
}

Describe 'Add-ReflectionAssembly -Type LoadFrom' -Tag 'Unit' {
    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            Mock Get-AssemblyFileName { [System.Reflection.AssemblyName]::new('Microsoft.Web.WebView2.Core, Version=1.0.2000.0') }
        }
    }

    It 'Should not load the bundled file when another module already loaded a newer version' {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ File = $Script:AssemblyFile } {
            param($File)
            $Newer = [PSCustomObject]@{ Location = 'C:\Other\Microsoft.Web.WebView2.Core.dll' }
            $Newer | Add-Member -MemberType ScriptMethod -Name GetName -Value { [System.Reflection.AssemblyName]::new('Microsoft.Web.WebView2.Core, Version=1.0.3000.0') }
            Mock Get-LoadedAssembly { $Newer }

            # The file is not a real assembly: reaching LoadFrom would throw.
            { Add-ReflectionAssembly -Object $File } | Should -Not -Throw
            Should -Invoke Get-LoadedAssembly -Times 1 -Exactly -ParameterFilter { $Name -eq 'Microsoft.Web.WebView2.Core' }
        }
    }

    It 'Should explain an older loaded version instead of failing obscurely' {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ File = $Script:AssemblyFile } {
            param($File)
            $Older = [PSCustomObject]@{ Location = 'C:\Other\Microsoft.Web.WebView2.Core.dll' }
            $Older | Add-Member -MemberType ScriptMethod -Name GetName -Value { [System.Reflection.AssemblyName]::new('Microsoft.Web.WebView2.Core, Version=1.0.1000.0') }
            Mock Get-LoadedAssembly { $Older }

            { Add-ReflectionAssembly -Object $File } | Should -Throw -ExpectedMessage "*1.0.1000.0 is already loaded*C:\Other\Microsoft.Web.WebView2.Core.dll*older than the 1.0.2000.0*new PowerShell session*"
        }
    }

    It 'Should load the file when nothing by that name is loaded' {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ File = $Script:AssemblyFile } {
            param($File)
            Mock Get-LoadedAssembly { }

            # Reaching LoadFrom with a file that is not an assembly is the proof that it was attempted.
            { Add-ReflectionAssembly -Object $File } | Should -Throw
        }
    }

    It 'Should leave a path that is not a file to LoadFrom, without inspecting it' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Get-LoadedAssembly { }

            { Add-ReflectionAssembly -Object (Join-Path $TestDrive 'missing.dll') } | Should -Throw
            Should -Invoke Get-AssemblyFileName -Times 0 -Exactly
            Should -Invoke Get-LoadedAssembly -Times 0 -Exactly
        }
    }
}

Describe 'Get-LoadedAssembly' -Tag 'Unit' {
    It 'Should find an assembly that is loaded' {
        InModuleScope 'OmadaWeb.PS' {
            (Get-LoadedAssembly -Name 'System.Management.Automation').GetName().Name | Should -Be 'System.Management.Automation'
        }
    }

    It 'Should return nothing for one that is not' {
        InModuleScope 'OmadaWeb.PS' {
            Get-LoadedAssembly -Name 'No.Such.Assembly.Loaded' | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-AssemblyFileName' -Tag 'Unit' {
    It 'Should read the identity of an assembly file without loading it' {
        InModuleScope 'OmadaWeb.PS' {
            $Path = [System.Management.Automation.PSObject].Assembly.Location

            (Get-AssemblyFileName -Path $Path).Name | Should -Be 'System.Management.Automation'
        }
    }
}
