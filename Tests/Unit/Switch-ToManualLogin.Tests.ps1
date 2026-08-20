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
            # A page that carries none of the element IDs any scenario acts on - what a Microsoft
            # sign-in redesign looks like from here. getAllIdsScript only ever reports IDs from its
            # own list, so an unrecognized page reaches ProcessingScenarios either empty or carrying
            # one of the IDs that list looks for but no scenario handles. i0281 is such an ID, and
            # using it keeps this fixture the shape the state machine really receives.
            $Script:UnknownPageAttributes = @(
                [PSCustomObject]@{ id = 'i0281'; tagName = 'DIV'; outerHTML = '<div id="i0281"></div>' }
            )

            $Script:WebView2 = [PSCustomObject]@{
                Source       = [System.Uri]::New('https://login.microsoftonline.com/common/oauth2/authorize?client_id=abc')
                CoreWebView2 = [PSCustomObject]@{}
            }

            $Script:WebView2.CoreWebView2 | Add-Member -MemberType ScriptMethod -Name ExecuteScriptAsync -Value {
                param($Script)

                [PSCustomObject]@{
                    IsCompleted = $true
                    IsFaulted   = $false
                    Result      = 'null'
                }
            }

            $Script:CurrentWebView2Session = [PSCustomObject]@{
                Credential = New-Object System.Management.Automation.PSCredential('user@contoso.com', (ConvertTo-SecureString 'password' -AsPlainText -Force))
            }

            $Script:MicrosoftOnlineLogin = $true
            $Script:LoginFailed = $false
            $Script:ManualLoginFallbackActive = $false
            $Script:MfaRequestDisplayed = $false
            $Script:LoginState = 'ProcessingScenarios'
            $Script:LoginSubState = $null
            $Script:LoginTask = $null
            $Script:IdAttributes = $Script:UnknownPageAttributes
            $Script:PreviousAttributes = $Script:UnknownPageAttributes
            $Script:UnmatchedPageSignature = $null
            $Script:UnmatchedPageSince = $null
            $Script:LoginAutomationFallbackTimeout = 0
        }
    }

    AfterAll {
        InModuleScope 'OmadaWeb.PS' {
            $Script:WebView2 = $null
            $Script:CurrentWebView2Session = $null
            $Script:IdAttributes = $null
            $Script:PreviousAttributes = $null
            $Script:LoginAutomationFallbackTimeout = 60
        }
    }

    It 'Falls back to manual login when the page matches no known sign-in step' {
        InModuleScope 'OmadaWeb.PS' {
            # First pass arms the stall clock, second pass hits the timeout. Warnings raised inside
            # the state machine do not reach an outer -WarningVariable, so redirect the warning
            # stream and keep only warning records - a fold of every stream would let the verbose
            # logging satisfy these assertions on its own.
            Invoke-WebView2MicrosoftLogin -WarningAction SilentlyContinue | Out-Null
            $Script:LoginState = 'ProcessingScenarios'
            $Script:IdAttributes = $Script:UnknownPageAttributes
            $Warnings = @(Invoke-WebView2MicrosoftLogin 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

            $Script:MicrosoftOnlineLogin | Should -BeFalse
            ($Warnings -join "`n") | Should -BeLike '*ProcessingScenarios*'
        }
    }

    It 'Names the missing selectors and the page in the diagnostic' {
        InModuleScope 'OmadaWeb.PS' {
            Invoke-WebView2MicrosoftLogin -WarningAction SilentlyContinue | Out-Null
            $Script:LoginState = 'ProcessingScenarios'
            $Script:IdAttributes = $Script:UnknownPageAttributes
            $Warnings = @(Invoke-WebView2MicrosoftLogin 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

            $Warning = $Warnings -join "`n"

            $Warning | Should -BeLike '*i0116*'
            $Warning | Should -BeLike '*i0118*'
            $Warning | Should -BeLike '*idSIButton9*'
            $Warning | Should -BeLike '*Elements present : i0281*'
            $Warning | Should -BeLike '*https://login.microsoftonline.com/common/oauth2/authorize*'
        }
    }

    It 'Does not fall back while the page still matches a known sign-in step' {
        InModuleScope 'OmadaWeb.PS' {
            # Working through the sub-states of a recognized page takes several ticks, which is why
            # the timeout is generous in the module. Use the real one here.
            $Script:LoginAutomationFallbackTimeout = 60

            $KnownPage = @(
                [PSCustomObject]@{ id = 'i0116'; outerHTML = '<input id="i0116">' }
                [PSCustomObject]@{ id = 'idSIButton9'; outerHTML = '<input id="idSIButton9">' }
            )

            $Script:IdAttributes = $KnownPage
            $Script:PreviousAttributes = $KnownPage

            Invoke-WebView2MicrosoftLogin -WarningAction SilentlyContinue | Out-Null
            $Script:LoginState = 'ProcessingScenarios'
            $Script:IdAttributes = $KnownPage
            $Warnings = @(Invoke-WebView2MicrosoftLogin 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

            $Script:MicrosoftOnlineLogin | Should -BeTrue
            ($Warnings | Measure-Object).Count | Should -Be 0
        }
    }

    It 'Does not fall back while waiting for the user to approve the sign-in request' {
        InModuleScope 'OmadaWeb.PS' {
            $MfaPage = @(
                [PSCustomObject]@{ id = 'idRichContext_DisplaySign'; outerHTML = '<div id="idRichContext_DisplaySign">42</div>' }
            )

            $Script:MfaRequestDisplayed = $true
            $Script:IdAttributes = $MfaPage
            $Script:PreviousAttributes = $MfaPage

            Invoke-WebView2MicrosoftLogin -WarningAction SilentlyContinue | Out-Null
            $Script:LoginState = 'ProcessingScenarios'
            $Script:IdAttributes = $MfaPage
            $Warnings = @(Invoke-WebView2MicrosoftLogin 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

            $Script:MicrosoftOnlineLogin | Should -BeTrue
            ($Warnings | Measure-Object).Count | Should -Be 0
        }
    }

    It 'Names every known selector when the page carries none of them' {
        InModuleScope 'OmadaWeb.PS' {
            # getAllIds found nothing at all - the loudest form of a selector break. The diagnostic
            # has to list what was looked for, since the page itself offers nothing to report.
            $Script:LoginState = 'GettingIds'
            $Script:LoginTask = [PSCustomObject]@{ IsCompleted = $true; IsFaulted = $false; Result = '"[]"' }

            Invoke-WebView2MicrosoftLogin -WarningAction SilentlyContinue | Out-Null

            $Script:LoginState = 'GettingIds'
            $Script:LoginTask = [PSCustomObject]@{ IsCompleted = $true; IsFaulted = $false; Result = '"[]"' }
            $Warnings = @(Invoke-WebView2MicrosoftLogin 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

            $Warning = $Warnings -join "`n"

            $Warning | Should -BeLike '*i0116*'
            $Warning | Should -BeLike '*KmsiCheckboxField*'
            $Warning | Should -Not -BeLike '*Missing elements : unknown*'
            $Warning | Should -Not -BeLike '*Elements present*'
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
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
