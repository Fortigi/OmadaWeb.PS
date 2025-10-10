function Invoke-DataFromWebDriver {
    [CmdletBinding()]
    param(
        [string]$EdgeProfile,
        [switch]$InPrivate
    )

    $AuthCookie = $null

    "Opening Edge to retrieve authentication cookie" | Write-Host
    $EdgeDriver = Start-EdgeDriver -InPrivate:$InPrivate.IsPresent -EdgeProfile $EdgeProfile

    Start-EdgeDriverLogin

    $AgentString = $EdgeDriver.ExecuteScript("return navigator.userAgent")

    Start-Sleep -Seconds 1
    $LoginMessageShown = $false
    $MfaRequestDisplayed = $false
    $PhoneLinkActive = $false
    if ((Get-Process | Where-Object { $_.ProcessName -eq "PhoneExperienceHost" } | Measure-Object).Count -gt 0) {
        $PhoneLinkActive = $true
    }
    do {
        if (-not $LoginMessageShown) {
            Write-Host "`r`nBrowser opened, please login! Waiting for login." -NoNewline -ForegroundColor Yellow
            if ($Script:Credential -and ![string]::IsNullOrWhiteSpace($Script:Credential.UserName)) {
                " Execute automated login steps for user: {0}" -f $Script:Credential.UserName | Write-Host -ForegroundColor Yellow -NoNewline
            }
            $LoginMessageShown = $true
        }

        Write-Host "." -NoNewline -ForegroundColor Yellow
        Start-Sleep -Milliseconds 500

        if ($Script:Credential -and ![string]::IsNullOrWhiteSpace($Script:Credential.UserName)) {

            if ($EdgeDriver.url -like "https://login.microsoftonline.com/*") {
                try {
                    $UserNameElementId = "i0116"
                    $PasswordElementId = "i0118"
                    $SubmitButton = "idSIButton9"
                    #$DisplayNameElement = "displayName"
                    $CantAccessAccountId = "cantAccessAccount"
                    $MfaElementId = "idRichContext_DisplaySign"
                    $MfaRetryId1 = "idA_SAASTO_Resend"
                    $MfaRetryId2 = "idA_SAASDS_Resend"
                    $ButtonBackId = "idBtn_Back"
                    $ButtonSubmitId = "idSIButton9"

                    $Elements = $EdgeDriver.FindElements([OpenQA.Selenium.By]::XPath("//*[@id]"))
                    $IdAttributes = $Elements.GetAttribute("id")

                    if ($IdAttributes -contains $UserNameElementId `
                            -and $IdAttributes -contains $PasswordElementId `
                            -and $IdAttributes -notcontains $ButtonBackId `
                            -and $IdAttributes -contains $ButtonSubmitId `
                            -and $IdAttributes -contains $CantAccessAccountId `
                            -and $EdgeDriver.FindElement([OpenQA.Selenium.By]::Id($ButtonSubmitId)).ComputedAccessibleLabel -eq "Next" `
                    ) {
                        Start-Sleep -Milliseconds 500
                        "Enter username" | Write-Verbose
                        $EdgeDriver.FindElements([OpenQA.Selenium.By]::Id($UserNameElementId))[0].SendKeys($Script:Credential.UserName)
                        $EdgeDriver.FindElement([OpenQA.Selenium.By]::Id($SubmitButton)).Click()
                    }

                    if ($IdAttributes -notcontains $UserNameElementId `
                            -and $IdAttributes -contains $PasswordElementId `
                            -and $IdAttributes -contains $ButtonSubmitId `
                            -and $IdAttributes -notcontains $CantAccessAccountId `
                            -and $EdgeDriver.FindElement([OpenQA.Selenium.By]::Id($ButtonSubmitId)).ComputedAccessibleLabel -eq "Sign in"
                    ) {
                        "Enter password" | Write-Verbose
                        $EdgeDriver.FindElements([OpenQA.Selenium.By]::Id($PasswordElementId))[0].SendKeys($Script:Credential.GetNetworkCredential().Password)
                        $EdgeDriver.FindElement([OpenQA.Selenium.By]::Id($SubmitButton)).Click()
                    }

                    if ($IdAttributes -notcontains $UserNameElementId `
                            -and $IdAttributes -notcontains $PasswordElementId `
                            -and $IdAttributes -contains $SelectUserElementId
                    ) {
                        "Select logged-in account" | Write-Verbose
                        if ($AccountElement.GetAttribute("data-test-id") -eq $Script:Credential.UserName) {
                            $AccountElement.Click()
                        }
                    }

                    if ($IdAttributes -notcontains $UserNameElementId `
                            -and $IdAttributes -notcontains $PasswordElementId `
                            -and $IdAttributes -notcontains $SelectUserElementId `
                            -and $IdAttributes -contains $ButtonBackId `
                            -and $IdAttributes -contains $ButtonSubmitId `
                            -and $EdgeDriver.FindElement([OpenQA.Selenium.By]::Id($ButtonBackId)).ComputedAccessibleLabel -eq "No" `
                            -and $EdgeDriver.FindElement([OpenQA.Selenium.By]::Id($ButtonSubmitId)).ComputedAccessibleLabel -eq "Yes" `
                    ) {
                        "Decline Stay signed in? " | Write-Verbose
                        $EdgeDriver.FindElement([OpenQA.Selenium.By]::Id($ButtonBackId)).Click()
                    }

                    if ($IdAttributes -notcontains $UserNameElementId `
                            -and $IdAttributes -notcontains $PasswordElementId `
                            -and $IdAttributes -notcontains $ButtonBackId `
                            -and ($EdgeDriver.FindElements([OpenQA.Selenium.By]::XPath("//*[@data-test-id]")) | Measure-Object).Count -gt 0) {

                        "Select logged-in user " | Write-Verbose
                        $EdgeDriver.FindElements([OpenQA.Selenium.By]::XPath("//*[@data-test-id]")) | ForEach-Object {
                            if ($_.GetAttribute("data-test-id") -eq $Script:Credential.UserName) {
                                $_.Click()
                            }
                        }
                    }

                    if ($MfaRequestDisplayed -ne $true `
                            -and $IdAttributes -notcontains $UserNameElementId `
                            -and $IdAttributes -notcontains $PasswordElementId `
                            -and $IdAttributes -contains $MFAElementId `
                            -and $IdAttributes -notcontains $MfaRetryId `
                            -and ($EdgeDriver.FindElements([OpenQA.Selenium.By]::XPath("//*[@data-test-id]")) | Measure-Object).Count -eq 0
                    ) {
                        $Message = "`nWaiting for your approve this sign-in request."
                        if ($null -ne $EdgeDriver.FindElements([OpenQA.Selenium.By]::Id($MfaElementId)).Text) {
                            if ($PhoneLinkActive) {
                                $Message = "{0}. {1} (This value is now in your clipboard so you can paste it into your Authenticator app using PhoneLink)." -f $Message.TrimEnd("."), $EdgeDriver.FindElements([OpenQA.Selenium.By]::Id($MfaElementId)).Text
                                $EdgeDriver.FindElements([OpenQA.Selenium.By]::Id($MfaElementId)).Text | Clip
                            }
                            else {
                                $Message = "{0}. {1}" -f $Message.TrimEnd("."), $EdgeDriver.FindElements([OpenQA.Selenium.By]::Id($MfaElementId)).Text
                            }
                        }
                        $Message | Write-Host -ForegroundColor Yellow
                        $MfaRequestDisplayed = $true
                    }

                    if ($MfaRequestDisplayed `
                            -and $IdAttributes -notcontains $UserNameElementId `
                            -and $IdAttributes -notcontains $PasswordElementId `
                            -and $IdAttributes -notcontains $MFAElementId `
                            -and (
                            $IdAttributes -contains $MfaRetryId1 `
                                -or $IdAttributes -contains $MfaRetryId2 )`
                            -and ($EdgeDriver.FindElements([OpenQA.Selenium.By]::XPath("//*[@data-test-id]")) | Measure-Object).Count -eq 0
                    ) {
                        "`nMFA failed! Please retry!" | Write-Warning
                        $MfaRequestDisplayed = $false
                        $LoginMessageShown = $false
                    }
                }
                catch {}
            }
        }

        $EdgeDriverHost = "-1"
        $OmadaWebBaseHost = "-2"
        $EdgeDriverAbsolutePath = $null
        if ($null -ne $EdgeDriver.url) {
            $EdgeDriverHost = [System.Uri]::new($EdgeDriver.url).Host
            $EdgeDriverAbsolutePath = [System.Uri]::new($EdgeDriver.url).AbsolutePath
            $OmadaWebBaseHost = [System.Uri]::new($Script:OmadaWebBaseUrl).Host
        }

        if ($OmadaWebBaseHost -ne $EdgeDriverHost -and $EdgeDriverAbsolutePath -ne "/home" ) {
            if ($null -eq $EdgeDriver -or $null -eq $EdgeDriver.WindowHandles) {
                if ($Script:LoginRetryCount -ge 3) {
                    Close-EdgeDriver
                    "`nLogin retry count exceeded! Please check your credentials as no cookie could be retrieved!" | Write-Error -ErrorAction "Stop" -Category AuthenticationError
                }
                else {
                    "`n{0} - Login retry count: {1}" -f $MyInvocation.MyCommand, $Script:LoginRetryCount | Write-Verbose
                }

                "" | Write-Host
                "Edge window seems to be closed before authentication was completed. Re-open Edge driver in 2 seconds!" | Write-Host -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                $LoginMessageShown = $false
                Close-EdgeDriver
                $EdgeDriver = Start-EdgeDriver -InPrivate:$InPrivate.IsPresent -EdgeProfile $EdgeProfile
                Start-EdgeDriverLogin
                $Script:LoginRetryCount++
            }
        }
        else {
            $AuthCookie = $EdgeDriver.Manage().Cookies.AllCookies | Where-Object { $_.Name -eq 'oisauthtoken' }
        }
    }
    until($null -ne $AuthCookie -or $Script:LoginRetryCount -gt 3)
    "{0} (Line {1}): {2}" -f $MyInvocation.MyCommand, $MyInvocation.ScriptLineNumber, $$ | Write-Verbose

    #$CredentialsEntered = $false
    Close-EdgeDriver
    if ($null -ne $AuthCookie) {
        $Script:LoginRetryCount = 0
        return $AuthCookie, $AgentString
    }
    else {
        "Could not authenticate to '{0}" -f $Script:OmadaWebBaseUrl | Write-Error -ErrorAction "Stop"
    }
}