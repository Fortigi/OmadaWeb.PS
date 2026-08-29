param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

<#
    Runs the JavaScript this module actually ships against pages shaped like the Entra ID sign-in
    screens, in a real browser.

    Every other test of the sign-in automation feeds Resolve-EntraSignInScreen a snapshot written by
    hand, which proves the rules but assumes the snapshot. That assumption is where the automation
    has been wrong before: whether an element counts as visible is decided by the browser's computed
    style, not by the fixture author, and several defects lived exactly in the gap between what the
    probe reported and what the click helpers then did with it.

    So these tests take the shipping script out of the module - the probe from
    Get-EntraSignInProbeScript, the click helpers out of the here-strings inside
    Invoke-WebView2MicrosoftLogin - run it in headless Edge against file:// fixtures, and feed the
    real output to the real resolver. What is asserted is the whole chain: page -> probe -> decision,
    and page -> click -> what the page did about it.

    They are skipped rather than failed when Edge WebDriver cannot start, so a machine without it
    does not break the build. CI warms the driver up before running this, so it does run there.
#>

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    $Script:DriverSkipReason = $null
    $Script:Driver = $null
    $Script:FixtureDir = Join-Path ([System.IO.Path]::GetTempPath()) ("EntraSignInFixtures_{0}" -f ([guid]::NewGuid().ToString('N')))

    # The page-level state each fixture needs, with the parts every Entra page carries filled in.
    function Script:New-Fixture {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$Body,
            [string]$Config = '{ iErrorCode: 0, sErrorCode: "", arrUserProofs: [] }'
        )

        $Html = @"
<!doctype html><html><head><meta charset="utf-8"><title>Sign in</title>
<script>window.`$Config = $Config;</script>
<style>.offscreen { position:absolute; width:1px; height:1px; overflow:hidden; clip:rect(0 0 0 0); }</style>
</head><body>
$Body
</body></html>
"@

        $Path = Join-Path $Script:FixtureDir ("{0}.html" -f $Name)
        Set-Content -Path $Path -Value $Html -Encoding UTF8
        return ([System.Uri]$Path).AbsoluteUri
    }

    function Script:Get-PageSnapshot {
        param([Parameter(Mandatory)][string]$Url)

        $Script:Driver.Navigate().GoToUrl($Url)
        $ProbeScript = InModuleScope 'OmadaWeb.PS' { Get-EntraSignInProbeScript }

        return ($Script:Driver.ExecuteScript("return " + $ProbeScript) | ConvertFrom-Json)
    }

    # The click helpers live in here-strings inside the function, so they are lifted out through the
    # AST and evaluated in module scope - which is what expands the shared visibility predicate into
    # them. Reading them any other way would test a copy instead of what ships.
    function Script:Get-ShippedSnippet {
        param([Parameter(Mandatory)][string]$Name)

        $Definition = InModuleScope 'OmadaWeb.PS' { (Get-Command Invoke-WebView2MicrosoftLogin).Definition }
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Definition, [ref]$null, [ref]$null)

        $Assignment = $Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $Node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $Node.Left.VariablePath.UserPath -eq $Name
            }, $true) | Select-Object -First 1

        if ($null -eq $Assignment) {
            throw "The snippet '$Name' is no longer assigned in Invoke-WebView2MicrosoftLogin."
        }

        return (InModuleScope 'OmadaWeb.PS' -Parameters @{ Text = $Assignment.Right.Extent.Text } {
                Invoke-Expression $Text
            })
    }

    try {
        # Asked of the module rather than guessed, because the binaries live in a per-edition folder
        # - Bin\Core under PowerShell 7, Bin\Desktop under Windows PowerShell 5.1. Hardcoding either
        # makes this suite skip silently on the other engine, which reads exactly like passing.
        $WebDriverAssembly = InModuleScope 'OmadaWeb.PS' { $Script:WebDriverPath }
        $Core = Split-Path $WebDriverAssembly -Parent

        if (-not (Test-Path $WebDriverAssembly) -or -not (Test-Path (Join-Path $Core "msedgedriver.exe"))) {
            throw "Edge WebDriver is not installed in '$Core'."
        }

        Add-Type -Path $WebDriverAssembly

        New-Item -ItemType Directory -Path $Script:FixtureDir -Force | Out-Null

        $Service = [OpenQA.Selenium.Edge.EdgeDriverService]::CreateDefaultService($Core, "msedgedriver.exe")
        $Service.HideCommandPromptWindow = $true
        $Options = [OpenQA.Selenium.Edge.EdgeOptions]::new()
        $Options.AddArgument("--headless=new")
        $Options.AddArgument("--allow-file-access-from-files")
        $Options.AddArgument("--no-sandbox")

        $Script:Driver = [OpenQA.Selenium.Edge.EdgeDriver]::new($Service, $Options)
    }
    catch {
        $Script:DriverSkipReason = "Edge WebDriver could not be started: {0}" -f $_.Exception.Message
    }
}

Describe 'Entra sign-in scripts against a real browser' -Tag 'Integration' {

    BeforeEach {
        if ($null -ne $Script:DriverSkipReason) {
            Set-ItResult -Skipped -Because $Script:DriverSkipReason
        }
    }

    Context 'The probe, against elements a real browser has laid out' {
        It 'Reports a left-over username field as present but not visible' {
            # The shape that makes presence useless as a signal: Entra keeps i0116 in the markup on
            # the password screen. Every hand-written snapshot in the other tests asserts this; here
            # the browser decides it.
            $Url = New-Fixture -Name 'password' -Body @'
  <input id="i0116" type="email" name="loginfmt" value="someone@contoso.com" style="display:none">
  <input id="i0118" type="password" name="passwd">
  <input id="idSIButton9" type="submit" value="Sign in">
'@

            $Snapshot = Get-PageSnapshot -Url $Url

            $Snapshot.ids | Should -Contain 'i0116'
            $Snapshot.visibleIds | Should -Not -Contain 'i0116'
            $Snapshot.visibleIds | Should -Contain 'i0118'
            $Snapshot.hasVisiblePasswordInput | Should -BeTrue
        }

        It 'Treats a field hidden by <Technique> as not visible' -TestCases @(
            @{ Technique = 'display:none'; Style = 'style="display:none"' }
            @{ Technique = 'visibility:hidden'; Style = 'style="visibility:hidden"' }
            @{ Technique = 'zero opacity'; Style = 'style="opacity:0"' }
            @{ Technique = 'an off-screen clip'; Style = 'class="offscreen"' }
            @{ Technique = 'aria-hidden'; Style = 'aria-hidden="true"' }
            @{ Technique = 'the disabled attribute'; Style = 'disabled' }
            @{ Technique = 'the readonly attribute'; Style = 'readonly' }
        ) {
            # Each of these is a different mechanism and only the browser knows what they compute to.
            # readonly is in the list because a field that cannot be typed into is as useless to this
            # module as one that cannot be seen.
            $Url = New-Fixture -Name ('hidden-{0}' -f ($Technique -replace '[^a-z]', '')) -Body @"
  <input id="i0118" type="password" name="passwd" $Style>
  <input id="idSIButton9" type="submit" value="Sign in">
"@

            $Snapshot = Get-PageSnapshot -Url $Url

            $Snapshot.ids | Should -Contain 'i0118'
            $Snapshot.visibleIds | Should -Not -Contain 'i0118'
        }

        It 'Reads the error code out of the page $Config' {
            $Url = New-Fixture -Name 'blocked' -Config '{ iErrorCode: 53003, sErrorCode: "53003", arrUserProofs: [] }' -Body '<div id="idBtn_Back">Back</div>'

            (Get-PageSnapshot -Url $Url).errorCode | Should -Be '53003'
        }

        It 'Reads the passwordless approval number' {
            $Url = New-Fixture -Name 'approval' -Body '<div id="idRemoteNGC_DisplaySign">42</div>'

            (Get-PageSnapshot -Url $Url).displaySign | Should -Be '42'
        }
    }

    Context 'The whole chain, from page to decision' {
        It 'Decides the password screen from a page that still carries the username field' {
            $Url = New-Fixture -Name 'chain-password' -Body @'
  <input id="i0116" type="email" name="loginfmt" style="display:none">
  <input id="i0118" type="password" name="passwd">
  <input id="idSIButton9" type="submit" value="Sign in">
'@

            $Snapshot = Get-PageSnapshot -Url $Url

            InModuleScope 'OmadaWeb.PS' -Parameters @{ Snapshot = $Snapshot } {
                $Decision = Resolve-EntraSignInScreen -PageState $Snapshot -UserName 'someone@contoso.com' -HasPassword

                $Decision.Screen | Should -Be 'PasswordEntry'
                $Decision.ElementId | Should -Be 'i0118'
                $Decision.ValueSource | Should -Be 'Password'
            }
        }

        It 'Decides the same screen when the page is served in Dutch' {
            # The defect this whole change exists for. The markup is identical apart from the words,
            # and the words are what the previous implementation read.
            $Url = New-Fixture -Name 'chain-password-nl' -Body @'
  <input id="i0116" type="email" name="loginfmt" style="display:none">
  <input id="i0118" type="password" name="passwd" placeholder="Wachtwoord">
  <input id="idSIButton9" type="submit" value="Aanmelden">
'@

            $Snapshot = Get-PageSnapshot -Url $Url

            InModuleScope 'OmadaWeb.PS' -Parameters @{ Snapshot = $Snapshot } {
                (Resolve-EntraSignInScreen -PageState $Snapshot -UserName 'someone@contoso.com' -HasPassword).Screen | Should -Be 'PasswordEntry'
            }
        }

        It 'Recognizes "stay signed in" when its checkbox is styled out of sight' {
            # The one rule that deliberately asks for presence rather than visibility. A styled
            # checkbox hides the real input behind its label, and this is the fixture that proves the
            # exception is needed rather than merely asserted in a comment.
            $Url = New-Fixture -Name 'chain-kmsi' -Body @'
  <input id="KmsiCheckboxField" type="checkbox" class="offscreen">
  <label for="KmsiCheckboxField">Don't show this again</label>
  <input id="idBtn_Back" type="button" value="No">
  <input id="idSIButton9" type="submit" value="Yes">
'@

            $Snapshot = Get-PageSnapshot -Url $Url

            $Snapshot.visibleIds | Should -Not -Contain 'KmsiCheckboxField' -Because 'the styled checkbox really is invisible to the browser'

            InModuleScope 'OmadaWeb.PS' -Parameters @{ Snapshot = $Snapshot } {
                $Decision = Resolve-EntraSignInScreen -PageState $Snapshot -UserName 'someone@contoso.com' -HasPassword

                $Decision.Screen | Should -Be 'StaySignedIn'
                $Decision.ElementId | Should -Be 'idBtn_Back'
            }
        }

        It 'Ends the sign-in on a Conditional Access block' {
            $Url = New-Fixture -Name 'chain-blocked' -Config '{ iErrorCode: 53003, sErrorCode: "53003", arrUserProofs: [] }' -Body @'
  <input id="i0118" type="password" name="passwd">
  <input id="idSIButton9" type="submit" value="Sign in">
'@

            $Snapshot = Get-PageSnapshot -Url $Url

            InModuleScope 'OmadaWeb.PS' -Parameters @{ Snapshot = $Snapshot } {
                $Decision = Resolve-EntraSignInScreen -PageState $Snapshot -UserName 'someone@contoso.com' -HasPassword

                $Decision.Action | Should -Be 'Stop'
                $Decision.Code | Should -Be 'AADSTS53003'
                $Decision.ValueSource | Should -Not -Be 'Password' -Because 'the password must not be sent to a page that already refused it'
            }
        }

        It 'Does not offer a passwordless account a hidden way out of the password screen' {
            $Url = New-Fixture -Name 'chain-passwordless-hidden-link' -Body @'
  <input id="i0118" type="password" name="passwd">
  <input id="idSIButton9" type="submit" value="Sign in">
  <a id="idA_PWD_SwitchToCredPicker" href="#" style="display:none">Sign in another way</a>
'@

            $Snapshot = Get-PageSnapshot -Url $Url

            InModuleScope 'OmadaWeb.PS' -Parameters @{ Snapshot = $Snapshot } {
                $Decision = Resolve-EntraSignInScreen -PageState $Snapshot -UserName 'someone@contoso.com'

                $Decision.Screen | Should -Be 'PasswordRequired'
                $Decision.ValueSource | Should -Not -Be 'Password'
            }
        }
    }

    Context 'The click helpers, against a page that answers back' {
        It 'Clicks the visible account tile and not its hidden namesake' {
            # Copilot found this by reading. Here the browser settles it: two elements carry the same
            # data-test-id and only one of them can be clicked by a person.
            $Url = New-Fixture -Name 'tiles' -Body @'
  <div id="hiddenTile" data-test-id="someone@contoso.com" style="display:none" onclick="window.__clicked='hidden'">someone@contoso.com</div>
  <div id="visibleTile" data-test-id="someone@contoso.com" onclick="window.__clicked='visible'">someone@contoso.com</div>
'@

            $Script:Driver.Navigate().GoToUrl($Url)
            $Snippet = Get-ShippedSnippet -Name 'ClickAccountTileScript'

            $Clicked = $Script:Driver.ExecuteScript(("return ({0})('someone@contoso.com');" -f $Snippet))

            $Clicked | Should -BeTrue
            $Script:Driver.ExecuteScript("return window.__clicked;") | Should -Be 'visible'
        }

        It 'Answers false rather than clicking an element the page is hiding' {
            $Url = New-Fixture -Name 'hidden-button' -Body '<input id="idSIButton9" type="submit" value="Sign in" style="display:none" onclick="window.__clicked=1">'

            $Script:Driver.Navigate().GoToUrl($Url)
            $Snippet = Get-ShippedSnippet -Name 'ClickElementScript'

            $Clicked = $Script:Driver.ExecuteScript(("return ({0})('idSIButton9');" -f $Snippet))

            $Clicked | Should -BeFalse -Because 'the driver reads this answer as "the page moved", and it did not'
            $Script:Driver.ExecuteScript("return window.__clicked;") | Should -BeNullOrEmpty
        }

        It 'Answers false rather than typing into a field the page is hiding' {
            $Url = New-Fixture -Name 'hidden-field' -Body '<input id="i0118" type="password" style="display:none">'

            $Script:Driver.Navigate().GoToUrl($Url)
            $Snippet = Get-ShippedSnippet -Name 'SetElementValueScript'

            $Written = $Script:Driver.ExecuteScript(("return ({0})('i0118', 'secret');" -f $Snippet))

            $Written | Should -BeFalse
            $Script:Driver.ExecuteScript("return document.getElementById('i0118').value;") | Should -BeNullOrEmpty
        }
    }

    Context 'The verification-method picker, counted and clicked the same way' {
        It 'Counts only the options a user could click, and clicks the one that was chosen' {
            # The count is the only thing linking a method to an option, so a hidden template option
            # counted on one side and not the other selects a different method than the one chosen -
            # and the click still succeeds, so nothing reports it.
            $Config = '{ iErrorCode: 0, sErrorCode: "", arrUserProofs: [ { authMethodId: "OneWaySMS", isDefault: true }, { authMethodId: "PhoneAppNotification", isDefault: false } ] }'
            $Url = New-Fixture -Name 'proofs' -Config $Config -Body @'
  <div id="idDiv_SAOTCS_Proofs">
    <div data-value="template" style="display:none" onclick="window.__clicked='template'">template</div>
    <div data-value="sms" onclick="window.__clicked='sms'">Text me</div>
    <div data-value="app" onclick="window.__clicked='app'">Approve a request</div>
  </div>
'@

            $Snapshot = Get-PageSnapshot -Url $Url

            $Snapshot.proofOptionCount | Should -Be 2 -Because 'the hidden template option is not one a user could choose'

            $Index = InModuleScope 'OmadaWeb.PS' -Parameters @{ Snapshot = $Snapshot } {
                $Decision = Resolve-EntraSignInScreen -PageState $Snapshot -UserName 'someone@contoso.com'

                $Decision.Action | Should -Be 'ClickProofOption'
                $Decision.Value | Should -Be 'PhoneAppNotification'
                return $Decision.Index
            }

            $Snippet = Get-ShippedSnippet -Name 'ClickProofOptionScript'
            $Clicked = $Script:Driver.ExecuteScript(("return ({0})('idDiv_SAOTCS_Proofs', {1});" -f $Snippet, $Index))

            $Clicked | Should -BeTrue
            $Script:Driver.ExecuteScript("return window.__clicked;") | Should -Be 'app' -Because 'the most secure offered method is the one that must be selected'
        }
    }
}

AfterAll {
    if ($null -ne $Script:Driver) {
        $Script:Driver.Quit()
        $Script:Driver = $null
    }

    if (Test-Path $Script:FixtureDir) {
        Remove-Item $Script:FixtureDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
