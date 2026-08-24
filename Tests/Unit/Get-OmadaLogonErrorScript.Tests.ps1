param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    $Script:LogonErrorScript = InModuleScope 'OmadaWeb.PS' { Get-OmadaLogonErrorScript }
}

Describe 'Get-OmadaLogonErrorScript' -Tag 'Unit' {

    It 'Invokes itself, because both call sites execute it as it stands' {
        # WebView2 passes it to ExecuteScriptAsync unchanged and Edge WebDriver prefixes "return".
        # A bare function expression would give both of them a function back instead of a result.
        $Script:LogonErrorScript.TrimEnd() | Should -BeLike '*})();'
    }

    It 'Stays a single expression, so "return" in front of it is valid JavaScript' {
        $Script:LogonErrorScript.TrimStart() | Should -BeLike '(function*'
    }

    It 'Looks in the container Omada renders page messages into' {
        $Script:LogonErrorScript | Should -BeLike '*PageMsgsContnr*'
        $Script:LogonErrorScript | Should -BeLike '*InfoTextPageWideTable*'
    }

    It 'Also matches an id an ASP.NET control hierarchy has prefixed' {
        # Compared with Contains rather than -BeLike: the selector's own square brackets would be
        # read as a wildcard character class.
        $Script:LogonErrorScript.Contains('[id$="PageMsgsContnr"]') | Should -BeTrue
    }

    It 'Reports the members the callers read' -TestCases @(
        @{ Member = 'found' }
        @{ Member = 'message' }
        @{ Member = 'source' }
        @{ Member = 'hasLogonForm' }
        @{ Member = 'onLogonPage' }
        @{ Member = 'path' }
    ) {
        $Script:LogonErrorScript | Should -BeLike ("*{0}:*" -f $Member)
    }

    It 'Returns its result as JSON, which is what the callers parse' {
        $Script:LogonErrorScript | Should -BeLike '*JSON.stringify*'
    }

    It 'Keeps the page-wide sweep to sign-in pages' {
        # On any other page of the Omada host only the page-message container is read, so an error
        # somewhere in the application cannot end a sign-in that is still in progress.
        $Script:LogonErrorScript | Should -BeLike '*onLogonPage*'
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
