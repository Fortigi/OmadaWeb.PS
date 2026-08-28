param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Switch-ToManualLogin' -Tag 'Unit' {

    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            $Script:ManualLoginFallbackActive = $false
            $Script:MicrosoftOnlineLogin = $true
            $Script:UnmatchedPageSignature = $null
            $Script:UnmatchedPageSince = $null
        }
    }

    It 'Hands control to the user by stopping the sign-in automation' {
        InModuleScope 'OmadaWeb.PS' {
            Switch-ToManualLogin -State 'ProcessingScenarios' -MissingElementId 'i0116' -WarningAction SilentlyContinue | Should -BeTrue

            $Script:MicrosoftOnlineLogin | Should -BeFalse
            $Script:ManualLoginFallbackActive | Should -BeTrue
        }
    }

    It 'Names the state, the missing selector and the page URL' {
        InModuleScope 'OmadaWeb.PS' {
            # Capture the warning stream only. The verbose stream repeats the URL, so folding the
            # streams together would let this pass without the warning saying anything at all.
            Switch-ToManualLogin -State 'ProcessingScenarios' -MissingElementId @('i0116', 'idSIButton9') -Url 'https://login.microsoftonline.com/common/oauth2/authorize?client_id=abc' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

            $Warning = $Warnings -join "`n"

            $Warning | Should -BeLike '*ProcessingScenarios*'
            $Warning | Should -BeLike '*i0116*'
            $Warning | Should -BeLike '*idSIButton9*'
            $Warning | Should -BeLike '*https://login.microsoftonline.com/common/oauth2/authorize*'
        }
    }

    It 'Keeps the query string of the page URL out of the warning' {
        InModuleScope 'OmadaWeb.PS' {
            Switch-ToManualLogin -State 'ProcessingScenarios' -Url 'https://login.microsoftonline.com/common/oauth2/authorize?client_id=abc&state=secretstate' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

            ($Warnings -join "`n") | Should -Not -BeLike '*secretstate*'
        }
    }

    It 'States that signing in still works' {
        InModuleScope 'OmadaWeb.PS' {
            Switch-ToManualLogin -State 'ProcessingScenarios' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

            ($Warnings -join "`n") | Should -BeLike '*sign in yourself in the browser window*'
        }
    }

    It 'Says the missing selector is unknown when the caller cannot name one' {
        InModuleScope 'OmadaWeb.PS' {
            # A script exception carries a reason but no element. Claiming the page matched no known
            # step would be a different, and wrong, statement.
            Switch-ToManualLogin -State 'EdgeDriverLoginScenarios' -Reason 'stale element reference' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

            $Warning = $Warnings -join "`n"

            $Warning | Should -BeLike '*Missing elements : unknown*'
            $Warning | Should -Not -BeLike '*matched none of the known sign-in steps*'
        }
    }

    It 'Leaves empty entries out of the element lists' {
        InModuleScope 'OmadaWeb.PS' {
            Switch-ToManualLogin -State 'ProcessingScenarios' -MissingElementId @('i0116', '', $null) -FoundElementId @('', $null) -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

            $Warning = $Warnings -join "`n"

            $Warning | Should -BeLike '*Missing elements : i0116*'
            $Warning | Should -Not -BeLike '*i0116,*'
            $Warning | Should -Not -BeLike '*Elements present*'
        }
    }

    It 'Reports once per sign-in, not once per poll' {
        InModuleScope 'OmadaWeb.PS' {
            $First = Switch-ToManualLogin -State 'ProcessingScenarios' -WarningAction SilentlyContinue
            $Second = Switch-ToManualLogin -State 'ProcessingScenarios' -WarningVariable Warnings -WarningAction SilentlyContinue

            $First | Should -BeTrue
            $Second | Should -BeFalse
            ($Warnings | Measure-Object).Count | Should -Be 0
        }
    }

    It 'Reports a reason when one is given, with secrets removed' {
        InModuleScope 'OmadaWeb.PS' {
            Switch-ToManualLogin -State 'Scenario1/SettingUsername' -Reason 'Request failed with Authorization: Bearer abcdef1234567890' -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null

            $Warning = $Warnings -join "`n"

            $Warning | Should -BeLike '*Scenario1/SettingUsername*'
            $Warning | Should -BeLike '*Request failed*'
            $Warning | Should -Not -BeLike '*abcdef1234567890*'
        }
    }
}

Describe 'Reset-LoginAutomationState' -Tag 'Unit' {

    It 'Lets a new browser window report a fallback of its own' {
        InModuleScope 'OmadaWeb.PS' {
            $Script:MicrosoftOnlineLogin = $true
            Switch-ToManualLogin -State 'ProcessingScenarios' -WarningAction SilentlyContinue | Out-Null

            # What Initialize-WebView2 and Get-DataFromWebDriver do for every new window. Without it
            # the guard inside Switch-ToManualLogin would keep the next window's diagnostic silent.
            Reset-LoginAutomationState
            $Script:MicrosoftOnlineLogin = $true

            Switch-ToManualLogin -State 'ProcessingScenarios' -WarningAction SilentlyContinue | Should -BeTrue
        }
    }

    It 'Clears the stall clock' {
        InModuleScope 'OmadaWeb.PS' {
            $Script:UnmatchedPageSignature = 'i0116'
            $Script:UnmatchedPageSince = [DateTime]::Now

            Reset-LoginAutomationState

            $Script:UnmatchedPageSignature | Should -BeNullOrEmpty
            $Script:UnmatchedPageSince | Should -BeNullOrEmpty
        }
    }

    It 'Is called by Initialize-WebView2 before the sign-in timer starts' {
        InModuleScope 'OmadaWeb.PS' {
            # Initialize-WebView2 needs a real WinForms WebView2 to run, so assert on the call site
            # instead: this is the only place a WebView2 window arms autofill again.
            $Definition = (Get-Command Initialize-WebView2).Definition

            $Definition | Should -BeLike '*$Script:MicrosoftOnlineLogin = $true*'
            $Definition | Should -BeLike '*Reset-LoginAutomationState*'
        }
    }
}

Describe 'Test-LoginAutomationStalled' -Tag 'Unit' {

    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            $Script:UnmatchedPageSignature = $null
            $Script:UnmatchedPageSince = $null
            $Script:LoginAutomationFallbackTimeout = 0
        }
    }

    AfterAll {
        InModuleScope 'OmadaWeb.PS' {
            $Script:LoginAutomationFallbackTimeout = 60
        }
    }

    It 'Does not report a stall on the first sight of a page' {
        InModuleScope 'OmadaWeb.PS' {
            Test-LoginAutomationStalled -ElementId @('i0116', 'idSIButton9') | Should -BeFalse
        }
    }

    It 'Reports a stall when the same page keeps coming back' {
        InModuleScope 'OmadaWeb.PS' {
            Test-LoginAutomationStalled -ElementId @('someNewId') | Out-Null

            Test-LoginAutomationStalled -ElementId @('someNewId') | Should -BeTrue
        }
    }

    It 'Restarts the clock when the page changes' {
        InModuleScope 'OmadaWeb.PS' {
            Test-LoginAutomationStalled -ElementId @('i0116') | Out-Null

            Test-LoginAutomationStalled -ElementId @('i0118') | Should -BeFalse
        }
    }

    It 'Restarts the clock when a call site reports progress' {
        InModuleScope 'OmadaWeb.PS' {
            Test-LoginAutomationStalled -ElementId @('i0116') | Out-Null
            # What the call sites do after a successful click.
            $Script:UnmatchedPageSince = $null

            Test-LoginAutomationStalled -ElementId @('i0116') | Should -BeFalse
        }
    }

    It 'Ignores element order' {
        InModuleScope 'OmadaWeb.PS' {
            Test-LoginAutomationStalled -ElementId @('i0116', 'i0118') | Out-Null

            Test-LoginAutomationStalled -ElementId @('i0118', 'i0116') | Should -BeTrue
        }
    }

    It 'Does not report a stall while waiting for the user to approve the sign-in request' {
        InModuleScope 'OmadaWeb.PS' {
            Test-LoginAutomationStalled -ElementId @('idRichContext_DisplaySign') | Out-Null

            Test-LoginAutomationStalled -ElementId @('idRichContext_DisplaySign') -WaitingForApproval | Should -BeFalse
        }
    }

    It 'Treats a page without any known element as a page in its own right' {
        InModuleScope 'OmadaWeb.PS' {
            Test-LoginAutomationStalled -ElementId @() | Out-Null

            Test-LoginAutomationStalled -ElementId @() | Should -BeTrue
        }
    }

    It 'Holds off while the timeout has not passed' {
        InModuleScope 'OmadaWeb.PS' {
            $Script:LoginAutomationFallbackTimeout = 600

            Test-LoginAutomationStalled -ElementId @('i0116') | Out-Null

            Test-LoginAutomationStalled -ElementId @('i0116') | Should -BeFalse
        }
    }
}

Describe 'Invoke-WebView2MicrosoftLogin selector fallback' -Tag 'Unit' {

    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            # The sign-in automation reads the page once per step, as one JSON snapshot. The fake
            # CoreWebView2 below returns whatever snapshot a test puts in $Script:NextScriptResult,
            # encoded the way ExecuteScriptAsync encodes a return value: the script's JSON document,
            # itself JSON-encoded.
            function Script:New-SnapshotResult {
                param([hashtable]$Override = @{})

                $State = [ordered]@{
                    ids                     = @()
                    visibleIds              = @()
                    errorCode               = '0'
                    errorCodeText           = ''
                    proofs                  = @()
                    proofOptionCount        = 0
                    accountTiles            = @()
                    hasOtherTile            = $false
                    displaySign             = $null
                    hasVisiblePasswordInput = $false
                    hasVisibleEmailInput    = $false
                    path                    = '/common/login'
                }

                foreach ($Key in $Override.Keys) {
                    $State[$Key] = $Override[$Key]
                }

                return (ConvertTo-Json -InputObject (ConvertTo-Json -InputObject $State -Depth 5 -Compress) -Compress)
            }

            # A page carrying one element the module knows of but no screen is recognized by - what a
            # Microsoft sign-in redesign looks like from here.
            $Script:NextScriptResult = Script:New-SnapshotResult @{ ids = @('idA_PWD_ForgotPassword'); visibleIds = @('idA_PWD_ForgotPassword') }

            $Script:WebView2 = [PSCustomObject]@{
                Source       = [System.Uri]::New('https://login.microsoftonline.com/common/oauth2/authorize?client_id=abc')
                CoreWebView2 = [PSCustomObject]@{}
            }

            # What a snippet answers is not the same as whether it ran: the probe returns the page
            # snapshot, and every acting snippet returns "true" when it found its element and
            # "false" when it did not. The fake has to keep those apart, or a test would never
            # exercise the difference. $Script:NextClickResult lets a test say the click found
            # nothing.
            $Script:NextClickResult = 'true'
            $Script:WebView2.CoreWebView2 | Add-Member -MemberType ScriptMethod -Name ExecuteScriptAsync -Value {
                param($ScriptText)

                $Result = $Script:NextClickResult
                if ($ScriptText -like '*knownIds*') {
                    $Result = $Script:NextScriptResult
                }

                [PSCustomObject]@{
                    IsCompleted = $true
                    IsFaulted   = $false
                    Result      = $Result
                }
            }

            $Script:CurrentWebView2Session = [PSCustomObject]@{
                Credential         = New-Object System.Management.Automation.PSCredential('user@contoso.com', (ConvertTo-SecureString 'password' -AsPlainText -Force))
                PreferredMfaMethod = $null
            }

            $Script:MicrosoftOnlineLogin = $true
            $Script:LoginFailed = $false
            $Script:ManualLoginFallbackActive = $false
            $Script:MfaRequestDisplayed = $false
            $Script:MfaWaitLastReported = $null
            $Script:LoginState = $null
            $Script:LoginTask = $null
            $Script:PageState = $null
            $Script:PendingSubmitId = $null
            $Script:CurrentScenario = $null
            $Script:PreviousScenario = $null
            $Script:UnmatchedPageSignature = $null
            $Script:UnmatchedPageSince = $null
            $Script:LoginAutomationFallbackTimeout = 0

            # Reading the page, deciding, and acting each take their own tick, so a test that wants
            # to see what several ticks produce has to run several. Warnings raised inside the state
            # machine do not reach an outer -WarningVariable, so the warning stream is redirected and
            # only warning records are kept - folding every stream together would let the verbose
            # logging satisfy the assertions on its own.
            function Script:Invoke-LoginTick {
                param([int]$Count = 6)

                $Warnings = @()
                for ($Tick = 0; $Tick -lt $Count; $Tick++) {
                    $Warnings += @(Invoke-WebView2MicrosoftLogin 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
                }

                return ($Warnings -join "`n")
            }
        }
    }

    AfterAll {
        InModuleScope 'OmadaWeb.PS' {
            $Script:WebView2 = $null
            $Script:CurrentWebView2Session = $null
            $Script:PageState = $null
            $Script:LoginAutomationFallbackTimeout = 60
        }
    }

    It 'Falls back to manual login when the page matches no known sign-in step' {
        InModuleScope 'OmadaWeb.PS' {
            $Warning = Script:Invoke-LoginTick

            $Script:MicrosoftOnlineLogin | Should -BeFalse
            $Warning | Should -BeLike '*Deciding*'
        }
    }

    It 'Names the missing selectors and the page in the diagnostic' {
        InModuleScope 'OmadaWeb.PS' {
            $Warning = Script:Invoke-LoginTick

            $Warning | Should -BeLike '*i0116*'
            $Warning | Should -BeLike '*i0118*'
            $Warning | Should -BeLike '*idSIButton9*'
            $Warning | Should -BeLike '*Elements present : idA_PWD_ForgotPassword*'
            $Warning | Should -BeLike '*https://login.microsoftonline.com/common/oauth2/authorize*'
        }
    }

    It 'Does not fall back while the page still matches a known sign-in step' {
        InModuleScope 'OmadaWeb.PS' {
            # Working through a recognized page takes several ticks, which is why the timeout is
            # generous in the module. Use the real one here.
            $Script:LoginAutomationFallbackTimeout = 60
            $Script:NextScriptResult = Script:New-SnapshotResult @{ ids = @('i0116', 'idSIButton9'); visibleIds = @('i0116', 'idSIButton9') }

            $Warning = Script:Invoke-LoginTick

            $Script:MicrosoftOnlineLogin | Should -BeTrue
            $Warning | Should -BeNullOrEmpty
        }
    }

    It 'Does not fall back while waiting for the user to approve the sign-in request' {
        InModuleScope 'OmadaWeb.PS' {
            $Script:MfaRequestDisplayed = $true
            $Script:NextScriptResult = Script:New-SnapshotResult @{
                ids         = @('idRichContext_DisplaySign')
                visibleIds  = @('idRichContext_DisplaySign')
                displaySign = '42'
            }

            $Warning = Script:Invoke-LoginTick -Count 10

            $Script:MicrosoftOnlineLogin | Should -BeTrue
            $Warning | Should -BeNullOrEmpty
        }
    }

    It 'Reports the screen it could not act on rather than the previous one' {
        InModuleScope 'OmadaWeb.PS' {
            # The username screen was recognized, then the sign-in moved to a page nothing
            # recognizes. Naming UsernameEntry in the diagnostic would send a reader to the wrong
            # code.
            $Script:CurrentScenario = 'UsernameEntry'

            $Warning = Script:Invoke-LoginTick

            $Warning | Should -Not -BeLike '*UsernameEntry*'
            $Warning | Should -BeLike '*Deciding/NoMatchingScreen*'
        }
    }

    It 'Names every known selector when the page cannot be read at all' {
        InModuleScope 'OmadaWeb.PS' {
            # The probe answered with nothing usable - the loudest form of a selector break. The
            # diagnostic has to list what was looked for, since the page offers nothing to report.
            $Script:NextScriptResult = 'null'

            $Warning = Script:Invoke-LoginTick

            $Warning | Should -BeLike '*i0116*'
            $Warning | Should -BeLike '*KmsiCheckboxField*'
            $Warning | Should -Not -BeLike '*Missing elements : unknown*'
            $Warning | Should -Not -BeLike '*Elements present*'
        }
    }

    It 'Hands over when the page cannot be read at all, instead of retrying for ever' {
        InModuleScope 'OmadaWeb.PS' {
            # A script that will not execute is no different from a page that answers nothing: both
            # have to arm the stall clock. Without that the driver re-issues the same failing script
            # every 150 ms and never hands the sign-in back, however long the timeout is.
            $Script:WebView2.CoreWebView2 | Add-Member -MemberType ScriptMethod -Name ExecuteScriptAsync -Force -Value {
                param($ScriptText)

                [PSCustomObject]@{
                    IsCompleted = $true
                    IsFaulted   = $true
                    Exception   = [PSCustomObject]@{ Message = 'Script execution is disabled' }
                    Result      = $null
                }
            }

            $Warning = Script:Invoke-LoginTick

            $Script:MicrosoftOnlineLogin | Should -BeFalse
            $Warning | Should -BeLike '*Script execution is disabled*'
        }
    }

    It 'Hands over when the page is recognized but does not respond to being driven' {
        InModuleScope 'OmadaWeb.PS' {
            # A screen this module recognizes, whose element has been renamed underneath it: the
            # script executes perfectly and does nothing, answering false. Counting that as progress
            # would clear the stall clock on every tick, so the driver would re-issue the same
            # useless click for as long as the window stayed open and never hand over.
            $Script:NextScriptResult = Script:New-SnapshotResult @{ ids = @('i0116', 'idSIButton9'); visibleIds = @('i0116', 'idSIButton9') }
            $Script:NextClickResult = 'false'

            $Warning = Script:Invoke-LoginTick -Count 8

            $Script:MicrosoftOnlineLogin | Should -BeFalse
            $Warning | Should -BeLike '*Deciding/UsernameEntry*'
        }
    }

    It 'Does not submit a field it could not fill in' {
        InModuleScope 'OmadaWeb.PS' {
            # Writing the value and clicking submit are two scripts. If the first found no field,
            # clicking submit would send whatever the field already held - nothing - and spend one
            # of the attempts before Entra ID smart lockout on it.
            $Script:LoginAutomationFallbackTimeout = 60
            $Script:NextScriptResult = Script:New-SnapshotResult @{ ids = @('i0118', 'idSIButton9'); visibleIds = @('i0118', 'idSIButton9') }
            $Script:NextClickResult = 'false'

            $Script:ClickedElementId = @()
            $Script:WebView2.CoreWebView2 | Add-Member -MemberType ScriptMethod -Name ExecuteScriptAsync -Force -Value {
                param($ScriptText)

                $Result = $Script:NextClickResult
                if ($ScriptText -like '*knownIds*') {
                    $Result = $Script:NextScriptResult
                }
                else {
                    $Script:ClickedElementId += $ScriptText
                }

                [PSCustomObject]@{
                    IsCompleted = $true
                    IsFaulted   = $false
                    Result      = $Result
                }
            }

            Script:Invoke-LoginTick -Count 8 | Out-Null

            # The password field was written to; the submit button never was.
            ($Script:ClickedElementId | Where-Object { $_ -like '*"i0118"*' } | Measure-Object).Count | Should -BeGreaterThan 0
            ($Script:ClickedElementId | Where-Object { $_ -like '*("idSIButton9")*' } | Measure-Object).Count | Should -Be 0
        }
    }

    It 'Resets the fallback when the browser leaves the Microsoft sign-in page' {
        InModuleScope 'OmadaWeb.PS' {
            $Script:ManualLoginFallbackActive = $true
            $Script:UnmatchedPageSince = [DateTime]::Now
            $Script:WebView2.Source = [System.Uri]::New('https://omada.contoso.com/home')

            Invoke-WebView2MicrosoftLogin -WarningAction SilentlyContinue | Out-Null

            $Script:ManualLoginFallbackActive | Should -BeFalse
            $Script:UnmatchedPageSince | Should -BeNullOrEmpty
        }
    }

    It 'Ends the sign-in without retrying when Entra ID reports a Conditional Access block' {
        InModuleScope 'OmadaWeb.PS' {
            # Issue #18: a 53003 page is terminal. Re-opening the window lands on it again, and the
            # driver has to be told that rather than spending its retries discovering it.
            $Script:LoginAbortReason = $null
            $Script:LoginAutomationFallbackTimeout = 60
            $Script:WebView2 | Add-Member -MemberType ScriptMethod -Name FindForm -Value { return $null } -Force
            $Script:NextScriptResult = Script:New-SnapshotResult @{ errorCode = '53003' }

            $Warning = Script:Invoke-LoginTick -Count 4

            $Script:LoginAbortReason | Should -Not -BeNullOrEmpty
            $Script:LoginAbortReason.Code | Should -Be 'AADSTS53003'
            $Script:LoginFailed | Should -BeTrue
            $Script:MicrosoftOnlineLogin | Should -BeFalse
            $Warning | Should -BeLike '*will not be retried*'

            $Script:LoginAbortReason = $null
        }
    }

    It 'Does not resubmit a credential Entra ID has just refused' {
        InModuleScope 'OmadaWeb.PS' {
            # The refused password screen is rendered again with the field intact. Filling it in is
            # what drives an account into smart lockout, so the sign-in stops instead.
            $Script:LoginAbortReason = $null
            $Script:LoginAutomationFallbackTimeout = 60
            $Script:WebView2 | Add-Member -MemberType ScriptMethod -Name FindForm -Value { return $null } -Force
            $Script:NextScriptResult = Script:New-SnapshotResult @{
                ids        = @('i0118', 'idSIButton9', 'passwordError')
                visibleIds = @('i0118', 'idSIButton9', 'passwordError')
                errorCode  = '50126'
            }

            Script:Invoke-LoginTick -Count 4 | Out-Null

            $Script:LoginAbortReason.Code | Should -Be 'AADSTS50126'
            $Script:LoginFailed | Should -BeTrue

            $Script:LoginAbortReason = $null
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
