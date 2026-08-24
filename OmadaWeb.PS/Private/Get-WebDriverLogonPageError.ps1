function Get-WebDriverLogonPageError {
    <#
    .SYNOPSIS
        Reads the Omada logon page in the Edge WebDriver browser and stops a sign-in that was refused.

    .DESCRIPTION
        The Edge WebDriver driver leaves its poll loop as soon as the browser is back on the Omada
        host, and reports "Could not authenticate to ..." when no oisauthtoken cookie is there. That
        sentence is true and says nothing: the page in front of the user is the interesting part, and
        for a failed federated sign-in it carries the account, the tenant and an AADSTS code.

        This is the Edge WebDriver half of the same check Get-WebView2LogonPageError performs, sharing
        the scraper in Get-OmadaLogonErrorScript and the judgement in Test-OmadaLogonPageError so the
        two engines cannot disagree about what counts as a refusal. Selenium runs a script as a
        function body, hence the "return" the WebView2 side does not need.

        A refusal that a retry cannot change is recorded through Stop-OmadaLogin, which is what makes
        Get-DataFromWebDriver report the page's own message - and what stops the re-open path in its
        exception handler from opening another browser for a sign-in that has already been answered.

    .PARAMETER EdgeDriver
        The Selenium WebDriver instance driving the browser.

    .OUTPUTS
        System.Boolean. True when the sign-in was stopped, false when the page carries no terminal
        error - including when it could not be read at all.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        $EdgeDriver
    )

    if ($null -eq $EdgeDriver) {
        return $false
    }

    if ($null -ne $Script:LoginAbortReason) {
        return $true
    }

    $Scrape = $null
    try {
        $Result = $EdgeDriver.ExecuteScript(("return {0}" -f (Get-OmadaLogonErrorScript)))
        if (-not [string]::IsNullOrWhiteSpace($Result)) {
            $Scrape = $Result | ConvertFrom-Json -ErrorAction Stop
        }
    }
    catch {
        # A page that navigated away mid-script, or a browser the user has already closed. Neither
        # says anything about the sign-in, and the caller has its own handling for both.
        "Get-WebDriverLogonPageError - Could not read the page: {0}" -f (Protect-LogMessage -Message $_.Exception.Message) | Write-Verbose
        return $false
    }

    if ($null -eq $Scrape -or -not $Scrape.found) {
        return $false
    }

    $Verdict = Test-OmadaLogonPageError -Message $Scrape.message -Source $Scrape.source -HasLogonForm:([bool]$Scrape.hasLogonForm) -OnLogonPage:([bool]$Scrape.onLogonPage)
    if (-not $Verdict.IsError) {
        return $false
    }

    $PageUrl = $null
    try {
        $PageUrl = $EdgeDriver.Url
    }
    catch {
        "Get-WebDriverLogonPageError - Could not read the page URL" | Write-Verbose
    }

    if (-not $Verdict.IsFatal) {
        if ($Script:LogonPageErrorReported -ne $Verdict.Message) {
            $Script:LogonPageErrorReported = $Verdict.Message
            "The Omada logon page reports: {0}" -f (Protect-LogMessage -Message $Verdict.Message) | Write-Warning
        }
        return $false
    }

    "Get-WebDriverLogonPageError - Terminal logon page error found in '{0}'" -f $Verdict.Source | Write-Verbose

    Stop-OmadaLogin -Message $Verdict.Message -Code $Verdict.Code -Reason $Verdict.Reason -Url $PageUrl -Engine "EdgeWebDriver" | Out-Null

    return $true
}
