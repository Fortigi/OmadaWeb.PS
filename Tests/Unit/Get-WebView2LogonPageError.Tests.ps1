param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    # A stand-in for the WebView2 control, built outside the module because it is only ever read
    # through $Script:WebView2. CoreWebView2.ExecuteScriptAsync hands the script result back JSON
    # encoded, so the fake task's Result is the scraper's JSON document as a JSON string - the double
    # encoding ConvertFrom-JavaScriptResult exists to undo.
    function New-FakeWebView2 {
        param(
            [AllowEmptyString()]
            [string]$Message,

            [bool]$HasLogonForm = $false,
            [bool]$Found = $true,
            $Counter
        )

        $Document = [pscustomobject]@{
            found        = $Found
            message      = $Message
            source       = 'InfoText Error GlobPage'
            hasLogonForm = $HasLogonForm
            onLogonPage  = $true
            path         = '/logon.aspx'
        } | ConvertTo-Json -Compress

        $Task = [pscustomobject]@{
            IsCompleted = $true
            IsFaulted   = $false
            Result      = ($Document | ConvertTo-Json)
        }

        $Core = [pscustomobject]@{}
        $Core | Add-Member -MemberType ScriptMethod -Name ExecuteScriptAsync -Value {
            param($JavaScript)
            if ($null -ne $Counter) { $Counter.Value++ }
            return $Task
        }.GetNewClosure()

        $WebView = [pscustomobject]@{
            CoreWebView2 = $Core
            Source       = [System.Uri]::new('https://omada.example.com/logon.aspx?ReturnUrl=%2fOA%2fhome')
        }
        # The window is not part of this test - what matters is what gets recorded before it closes.
        $WebView | Add-Member -MemberType ScriptMethod -Name FindForm -Value { return $null }

        return $WebView
    }

    function New-FaultedWebView2 {
        $Task = [pscustomobject]@{
            IsCompleted = $true
            IsFaulted   = $true
            Exception   = [pscustomobject]@{ Message = 'Script execution was cancelled by a navigation.' }
            Result      = $null
        }

        $Core = [pscustomobject]@{}
        $Core | Add-Member -MemberType ScriptMethod -Name ExecuteScriptAsync -Value { param($JavaScript) return $Task }.GetNewClosure()

        $WebView = [pscustomobject]@{
            CoreWebView2 = $Core
            Source       = [System.Uri]::new('https://omada.example.com/logon.aspx')
        }
        $WebView | Add-Member -MemberType ScriptMethod -Name FindForm -Value { return $null }

        return $WebView
    }
}

Describe 'Get-WebView2LogonPageError' -Tag 'Unit' {

    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            $Script:LoginAbortReason = $null
            $Script:LogonPageErrorTask = $null
            $Script:LogonPageErrorLastCheck = $null
            $Script:LogonPageErrorReported = $null
            $Script:MicrosoftOnlineLogin = $true
            $Script:WebView2 = $null
        }
    }

    It 'Starts the scrape on one tick and answers on the next' {
        # The scrape must not block the 150 ms timer tick it runs in, so the first call only starts it.
        $Fake = New-FakeWebView2 -Message "AADSTS50178: User account 'x' does not exist in tenant 'Example'."

        InModuleScope 'OmadaWeb.PS' -Parameters @{ Fake = $Fake } {
            $Script:WebView2 = $Fake

            Get-WebView2LogonPageError -WarningAction SilentlyContinue | Should -BeFalse
            $Script:LogonPageErrorTask | Should -Not -BeNullOrEmpty
            $Script:LoginAbortReason | Should -BeNullOrEmpty

            Get-WebView2LogonPageError -WarningAction SilentlyContinue | Should -BeTrue

            $Script:LoginAbortReason.Code | Should -Be 'AADSTS50178'
            $Script:LoginAbortReason.Engine | Should -Be 'WebView2'
            $Script:LoginAbortReason.Url | Should -Be 'https://omada.example.com/logon.aspx'
        }
    }

    It 'Stops the credential autofill along with the sign-in' {
        $Fake = New-FakeWebView2 -Message "AADSTS50178: User account 'x' does not exist in tenant 'Example'."

        InModuleScope 'OmadaWeb.PS' -Parameters @{ Fake = $Fake } {
            $Script:WebView2 = $Fake

            Get-WebView2LogonPageError -WarningAction SilentlyContinue | Out-Null
            Get-WebView2LogonPageError -WarningAction SilentlyContinue | Out-Null

            $Script:MicrosoftOnlineLogin | Should -BeFalse
        }
    }

    It 'Leaves the window open on an error the user can correct' {
        $Fake = New-FakeWebView2 -Message 'The user name or password is incorrect.' -HasLogonForm $true

        InModuleScope 'OmadaWeb.PS' -Parameters @{ Fake = $Fake } {
            $Script:WebView2 = $Fake

            Get-WebView2LogonPageError -WarningAction SilentlyContinue | Out-Null
            Get-WebView2LogonPageError -WarningVariable Warnings -WarningAction SilentlyContinue | Should -BeFalse

            $Script:LoginAbortReason | Should -BeNullOrEmpty
            ($Warnings -join "`n") | Should -BeLike '*user name or password is incorrect*'
        }
    }

    It 'Repeats a correctable error once, not seven times a second' {
        $Fake = New-FakeWebView2 -Message 'The user name or password is incorrect.' -HasLogonForm $true

        InModuleScope 'OmadaWeb.PS' -Parameters @{ Fake = $Fake } {
            $Script:WebView2 = $Fake

            Get-WebView2LogonPageError -WarningAction SilentlyContinue | Out-Null
            Get-WebView2LogonPageError -WarningAction SilentlyContinue | Out-Null

            # Let the throttle through for a second read of the same unchanged page.
            $Script:LogonPageErrorLastCheck = $null
            Get-WebView2LogonPageError -WarningAction SilentlyContinue | Out-Null
            Get-WebView2LogonPageError -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

            $Warnings | Should -BeNullOrEmpty
        }
    }

    It 'Does not read the page again inside the throttle interval' {
        $Counter = [ref]0
        $Fake = New-FakeWebView2 -Message '' -Found $false -HasLogonForm $true -Counter $Counter

        InModuleScope 'OmadaWeb.PS' -Parameters @{ Fake = $Fake } {
            $Script:WebView2 = $Fake

            Get-WebView2LogonPageError | Out-Null   # starts a scrape
            Get-WebView2LogonPageError | Out-Null   # picks its result up
            Get-WebView2LogonPageError | Out-Null   # too soon to start another
        }

        $Counter.Value | Should -Be 1
    }

    It 'Does nothing without a browser' {
        InModuleScope 'OmadaWeb.PS' {
            $Script:WebView2 = $null

            Get-WebView2LogonPageError | Should -BeFalse
        }
    }

    It 'Treats a script that could not run as no answer' {
        # A navigation in flight cancels the script. That says nothing about the page, and must not
        # be mistaken for a refusal.
        $Fake = New-FaultedWebView2

        InModuleScope 'OmadaWeb.PS' -Parameters @{ Fake = $Fake } {
            $Script:WebView2 = $Fake

            Get-WebView2LogonPageError | Should -BeFalse
            Get-WebView2LogonPageError | Should -BeFalse

            $Script:LoginAbortReason | Should -BeNullOrEmpty
        }
    }

    It 'Reports an already stopped sign-in without reading the page again' {
        InModuleScope 'OmadaWeb.PS' {
            $Script:LoginAbortReason = [pscustomobject]@{ Message = 'Access denied.' }
            $Script:WebView2 = $null

            Get-WebView2LogonPageError | Should -BeTrue
        }
    }
}

AfterAll {
    InModuleScope 'OmadaWeb.PS' {
        $Script:WebView2 = $null
        $Script:LoginAbortReason = $null
        $Script:LogonPageErrorTask = $null
    }
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
