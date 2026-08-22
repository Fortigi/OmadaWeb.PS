param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Stop-OmadaLogin' -Tag 'Unit' {

    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            $Script:LoginAbortReason = $null
            $Script:MicrosoftOnlineLogin = $true
            $Script:LoginFailed = $false
        }
    }

    It 'Records why the sign-in was stopped, so the driver can report it instead of retrying' {
        InModuleScope 'OmadaWeb.PS' {
            Stop-OmadaLogin -Message 'AADSTS50178: ... does not exist in tenant ...' -Code 'AADSTS50178' -Reason 'Account unknown in the tenant.' -Url 'https://omada.example.com/logon.aspx' -Engine 'WebView2' -WarningAction SilentlyContinue | Should -BeTrue

            $Script:LoginAbortReason | Should -Not -BeNullOrEmpty
            $Script:LoginAbortReason.Code | Should -Be 'AADSTS50178'
            $Script:LoginAbortReason.Reason | Should -Be 'Account unknown in the tenant.'
            $Script:LoginAbortReason.Engine | Should -Be 'WebView2'
            $Script:LoginAbortReason.Message | Should -BeLike '*does not exist in tenant*'
        }
    }

    It 'Stops the credential autofill along with the sign-in' {
        InModuleScope 'OmadaWeb.PS' {
            Stop-OmadaLogin -Message 'Access denied.' -WarningAction SilentlyContinue | Out-Null

            $Script:MicrosoftOnlineLogin | Should -BeFalse
            $Script:LoginFailed | Should -BeTrue
        }
    }

    It 'Reports once, however often the 150 ms timer calls it' {
        InModuleScope 'OmadaWeb.PS' {
            Stop-OmadaLogin -Message 'First.' -Code 'AADSTS50178' -WarningAction SilentlyContinue | Should -BeTrue

            Stop-OmadaLogin -Message 'Second.' -Code 'AADSTS90072' -WarningVariable Warnings -WarningAction SilentlyContinue | Should -BeFalse

            $Warnings | Should -BeNullOrEmpty
            $Script:LoginAbortReason.Message | Should -Be 'First.'
        }
    }

    It 'Names the code, the page and the message in the warning' {
        InModuleScope 'OmadaWeb.PS' {
            Stop-OmadaLogin -Message 'User account does not exist in tenant.' -Code 'AADSTS50178' -Reason 'Account unknown in the tenant.' -Url 'https://omada.example.com/logon.aspx' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

            $Warning = $Warnings -join "`n"

            $Warning | Should -BeLike '*AADSTS50178*'
            $Warning | Should -BeLike '*https://omada.example.com/logon.aspx*'
            $Warning | Should -BeLike '*does not exist in tenant*'
            $Warning | Should -BeLike '*Account unknown in the tenant.*'
        }
    }

    It 'Says that no further attempt will be made' {
        InModuleScope 'OmadaWeb.PS' {
            Stop-OmadaLogin -Message 'Access denied.' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

            ($Warnings -join "`n") | Should -BeLike '*no further attempts are made*'
        }
    }

    It 'Keeps the query string of the page URL out of the warning' {
        # A logon page URL carries the return URL and request identifiers, and this text is what
        # users paste into support tickets.
        InModuleScope 'OmadaWeb.PS' {
            Stop-OmadaLogin -Message 'Access denied.' -Url 'https://omada.example.com/logon.aspx?ReturnUrl=%2fOA%2fhome&state=secretstate' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

            ($Warnings -join "`n") | Should -Not -BeLike '*secretstate*'
            $Script:LoginAbortReason.Url | Should -Be 'https://omada.example.com/logon.aspx'
        }
    }

    It 'Redacts secret material a page quoted back at the browser' {
        InModuleScope 'OmadaWeb.PS' {
            Stop-OmadaLogin -Message 'Sign-in failed for oisauthtoken=abc123secret' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

            ($Warnings -join "`n") | Should -Not -BeLike '*abc123secret*'
            $Script:LoginAbortReason.Message | Should -Not -BeLike '*abc123secret*'
        }
    }

    It 'Reports an unusable page URL rather than failing on it' {
        InModuleScope 'OmadaWeb.PS' {
            Stop-OmadaLogin -Message 'Access denied.' -Url '' -WarningAction SilentlyContinue | Out-Null

            $Script:LoginAbortReason.Url | Should -Be 'unknown'
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
