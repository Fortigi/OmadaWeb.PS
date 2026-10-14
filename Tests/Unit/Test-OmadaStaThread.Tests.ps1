param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    # A multi-threaded apartment, built rather than hoped for. A thread's apartment cannot be changed
    # once it is set, so the MTA half of this cannot be asserted in the Pester host - which is STA,
    # and is the very reason the PasswordAutofill canary scenario kept passing while the two that ran
    # in a background job did not. Start-Job is the shortest route to a real MTA runspace, and it is
    # also the exact host that issue #90 was about.
    function Invoke-InMultiThreadedApartment {
        param(
            [Parameter(Mandatory)]
            [scriptblock]$Body
        )

        $Job = Start-Job -ScriptBlock {
            param($ModulePath, $Body)

            $Module = Import-Module $ModulePath -Force -PassThru -WarningAction SilentlyContinue -ErrorAction Stop
            & $Module ([scriptblock]::Create($Body))
        } -ArgumentList $ModulePath, $Body.ToString()

        try {
            $null = $Job | Wait-Job -Timeout 120
            return @(Receive-Job -Job $Job -ErrorAction SilentlyContinue)
        }
        finally {
            Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}

Describe 'Test-OmadaStaThread' -Tag 'Unit' {

    It 'Answers with a boolean' {
        $Result = InModuleScope 'OmadaWeb.PS' { Test-OmadaStaThread }

        $Result | Should -BeOfType [System.Boolean]
    }

    It 'Agrees with the apartment the thread is actually in' {
        # Not a tautology: it asserts the predicate reports the same thing the WebView2 call a moment
        # later will experience. Anything that answered from somewhere else - a cached value, a host
        # name, a version check - could disagree with the thread, and that disagreement is the bug.
        $Expected = [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::MTA

        InModuleScope 'OmadaWeb.PS' { Test-OmadaStaThread } | Should -Be $Expected
    }

    It 'Reports false on a multi-threaded apartment' {
        # The regression test for issue #90. A background job is MTA, and this is the answer that
        # stops a sign-in there before it reaches WebView2 and fails with a COM error code instead.
        $Result = Invoke-InMultiThreadedApartment -Body { Test-OmadaStaThread }

        @($Result)[-1] | Should -BeFalse
    }

    It 'Is asked about the apartment that was the problem in the first place' {
        # Guards the guard: if a future PowerShell ran jobs on an STA thread, the test above would
        # pass for the wrong reason - the predicate returning true and the assertion still reading
        # false off something else. This is what says the job really was MTA.
        $Result = Invoke-InMultiThreadedApartment -Body { [System.Threading.Thread]::CurrentThread.GetApartmentState().ToString() }

        @($Result)[-1] | Should -Be 'MTA'
    }
}

Describe 'Start-WebView2Login on a multi-threaded apartment' -Tag 'Unit' {

    It 'Says the apartment is the problem instead of failing on a COM error code' {
        # What the canary trace showed before this: two attempts at CoreWebView2Environment, then
        # "Error occurred" and nothing else - no reason anywhere in the verbose stream, which is the
        # only stream a scheduled run captures. Issue #90 was filed guessing at a changed Microsoft
        # sign-in page as a result.
        #
        # Called with no session context, so it fails either way. What is asserted is *which* failure,
        # and that the reason is in the message rather than left to be inferred.
        $Result = Invoke-InMultiThreadedApartment -Body {
            try {
                Start-WebView2Login -EdgeProfile "Default"
            }
            catch {
                "CAUGHT: {0}" -f $_.Exception.Message
            }
        }

        ($Result -join [System.Environment]::NewLine) | Should -Match 'single-threaded apartment'
    }
}
