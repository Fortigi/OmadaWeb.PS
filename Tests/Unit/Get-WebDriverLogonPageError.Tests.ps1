param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-WebDriverLogonPageError' -Tag 'Unit' {

    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            $Script:LoginAbortReason = $null
            $Script:LogonPageErrorReported = $null
            $Script:MicrosoftOnlineLogin = $true
        }
    }

    It 'Stops the sign-in when the logon page carries a tenant error' {
        InModuleScope 'OmadaWeb.PS' {
            # Selenium hands back whatever the script returned, so the fake driver returns the
            # scraper's JSON document as it stands.
            $Scrape = [pscustomobject]@{
                found        = $true
                message      = "AADSTS50178: User account 'x' does not exist in tenant 'Example' and cannot access the application."
                source       = 'InfoText Error GlobPage'
                hasLogonForm = $false
                onLogonPage  = $true
                path         = '/logon.aspx'
            } | ConvertTo-Json -Compress

            $Driver = [pscustomobject]@{ Url = 'https://omada.example.com/logon.aspx?ReturnUrl=%2fOA%2fhome' }
            $Driver | Add-Member -MemberType ScriptMethod -Name ExecuteScript -Value { param($JavaScript) $Scrape }.GetNewClosure()

            Get-WebDriverLogonPageError -EdgeDriver $Driver -WarningAction SilentlyContinue | Should -BeTrue

            $Script:LoginAbortReason | Should -Not -BeNullOrEmpty
            $Script:LoginAbortReason.Code | Should -Be 'AADSTS50178'
            $Script:LoginAbortReason.Engine | Should -Be 'EdgeWebDriver'
            $Script:LoginAbortReason.Url | Should -Be 'https://omada.example.com/logon.aspx'
        }
    }

    It 'Leaves an error the user can correct to the user' {
        InModuleScope 'OmadaWeb.PS' {
            $Scrape = [pscustomobject]@{
                found        = $true
                message      = 'The user name or password is incorrect.'
                source       = 'ErrorText'
                hasLogonForm = $true
                onLogonPage  = $true
                path         = '/logon.aspx'
            } | ConvertTo-Json -Compress

            $Driver = [pscustomobject]@{ Url = 'https://omada.example.com/logon.aspx' }
            $Driver | Add-Member -MemberType ScriptMethod -Name ExecuteScript -Value { param($JavaScript) $Scrape }.GetNewClosure()

            Get-WebDriverLogonPageError -EdgeDriver $Driver -WarningVariable Warnings -WarningAction SilentlyContinue | Should -BeFalse

            $Script:LoginAbortReason | Should -BeNullOrEmpty
            ($Warnings -join "`n") | Should -BeLike '*user name or password is incorrect*'
        }
    }

    It 'Says nothing when the page carries no error' {
        InModuleScope 'OmadaWeb.PS' {
            $Scrape = [pscustomobject]@{
                found        = $false
                message      = ''
                source       = ''
                hasLogonForm = $true
                onLogonPage  = $true
                path         = '/logon.aspx'
            } | ConvertTo-Json -Compress

            $Driver = [pscustomobject]@{ Url = 'https://omada.example.com/logon.aspx' }
            $Driver | Add-Member -MemberType ScriptMethod -Name ExecuteScript -Value { param($JavaScript) $Scrape }.GetNewClosure()

            Get-WebDriverLogonPageError -EdgeDriver $Driver -WarningVariable Warnings -WarningAction SilentlyContinue | Should -BeFalse

            $Script:LoginAbortReason | Should -BeNullOrEmpty
            $Warnings | Should -BeNullOrEmpty
        }
    }

    It 'Treats a browser that has gone away as no answer, not as a refusal' {
        # The caller has its own handling for a closed window; guessing at one here would turn a
        # user closing the browser into a permanent failure.
        InModuleScope 'OmadaWeb.PS' {
            $Driver = [pscustomobject]@{ Url = 'https://omada.example.com/logon.aspx' }
            $Driver | Add-Member -MemberType ScriptMethod -Name ExecuteScript -Value { param($JavaScript) throw 'no such window: target window already closed' }

            Get-WebDriverLogonPageError -EdgeDriver $Driver -WarningAction SilentlyContinue | Should -BeFalse

            $Script:LoginAbortReason | Should -BeNullOrEmpty
        }
    }

    It 'Reports a page it could not parse as no answer' {
        InModuleScope 'OmadaWeb.PS' {
            $Driver = [pscustomobject]@{ Url = 'https://omada.example.com/logon.aspx' }
            $Driver | Add-Member -MemberType ScriptMethod -Name ExecuteScript -Value { param($JavaScript) 'not json at all' }

            Get-WebDriverLogonPageError -EdgeDriver $Driver -WarningAction SilentlyContinue | Should -BeFalse

            $Script:LoginAbortReason | Should -BeNullOrEmpty
        }
    }

    It 'Reports an already stopped sign-in without reading the page again' {
        InModuleScope 'OmadaWeb.PS' {
            $Script:LoginAbortReason = [pscustomobject]@{ Message = 'Access denied.' }

            $Driver = [pscustomobject]@{ Url = 'https://omada.example.com/logon.aspx' }
            $Driver | Add-Member -MemberType ScriptMethod -Name ExecuteScript -Value { param($JavaScript) throw 'the page must not be read again' }

            Get-WebDriverLogonPageError -EdgeDriver $Driver | Should -BeTrue
        }
    }

    It 'Does nothing without a driver' {
        InModuleScope 'OmadaWeb.PS' {
            Get-WebDriverLogonPageError -EdgeDriver $null | Should -BeFalse
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
