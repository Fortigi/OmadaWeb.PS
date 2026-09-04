param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    # No listener is started on purpose. The flag under test is set before any request is made, so a
    # test that reached the network would be testing something else; the call is expected to fail.
    $Script:Uri = 'http://localhost:19999/api/unit-test'
}

Describe 'Invoke-OmadaRequest -SkipBodyRedaction' -Tag 'Unit' {

    It 'Should be off by default' {
        InModuleScope 'OmadaWeb.PS' {
            $Script:SkipBodyRedaction | Should -BeFalse
        }
    }

    It 'Should turn body redaction off for the request that asked for it' {
        try {
            Invoke-OmadaRestMethod -Uri $Script:Uri -AuthenticationType 'None' -SkipBodyRedaction -ErrorAction Stop
        }
        catch {
            # Expected: nothing is listening on that port.
        }

        InModuleScope 'OmadaWeb.PS' {
            $Script:SkipBodyRedaction | Should -BeTrue
        }
    }

    It 'Should turn body redaction back on for the next request that does not ask for it' {
        # The flag is module state. Left sticky, one troubleshooting call would keep bodies in the
        # verbose stream for every later call in the same PowerShell session.
        try {
            Invoke-OmadaRestMethod -Uri $Script:Uri -AuthenticationType 'None' -SkipBodyRedaction -ErrorAction Stop
        }
        catch {
        }

        try {
            Invoke-OmadaRestMethod -Uri $Script:Uri -AuthenticationType 'None' -ErrorAction Stop
        }
        catch {
        }

        InModuleScope 'OmadaWeb.PS' {
            $Script:SkipBodyRedaction | Should -BeFalse
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
