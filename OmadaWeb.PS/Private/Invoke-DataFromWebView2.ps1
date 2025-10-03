function Invoke-DataFromWebView2 {
    <#
    .SYNOPSIS
    Retrieves authentication cookie and user agent from WebView2 browser.

    .DESCRIPTION
    This function uses WebView2 to perform authentication with Omada and retrieves
    the authentication cookie and user agent string. This is an alternative to
    the Selenium WebDriver approach.

    .PARAMETER EdgeProfile
    The Edge profile to use for the browser session.

    .PARAMETER InPrivate
    Use InPrivate browsing mode.

    .EXAMPLE
    Invoke-DataFromWebView2

    .EXAMPLE
    Invoke-DataFromWebView2
    #>

    [CmdletBinding()]
    param()

    $AuthCookie = $null
    $AgentString = $null

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        "Opening WebView2 to retrieve authentication cookie" | Write-Host

        Initialize-WebView2Assemblies

        $Form = New-Object System.Windows.Forms.Form
        $Form.Text = 'Omada Cookie Grabber (WebView2, PowerShell)'
        $Form.Width = 1100
        $Form.Height = 800
        $Form.StartPosition = 'CenterScreen'

        $FormsPanel = New-Object System.Windows.Forms.Panel
        $FormsPanel.Dock = 'Top'
        $FormsPanel.Height = 44

        $WebView2 = New-Object Microsoft.Web.WebView2.WinForms.WebView2
        $WebView2.Dock = 'Fill'

        $STatusStrip = New-Object System.Windows.Forms.StatusStrip
        $StatusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
        $StatusLabel.Text = 'Ready.'
        $STatusStrip.Items.Add($StatusLabel) | Out-Null

        $Form.Controls.Add($WebView2)
        $Form.Controls.Add($FormsPanel)
        $Form.Controls.Add($STatusStrip)

        Initialize-WebView2Helper -Control $WebView2 -OnReady {
            "WebView2 is ready" | Write-Verbose
        }

        Start-WebView2Login

        Get-WebView2Cookies -Url $Script:OmadaWebBaseUrl -Cookies $Script:Task.Result | Out-Null



        # Navigate to login page
        $LoginUrl = $Script:OmadaWebBaseUrl
        "Navigating to login URL: {0}" -f $LoginUrl | Write-Verbose

        if ($Script:WebView2HelperInitialized) {
            # Use C# helper for navigation
            Invoke-WebView2Navigate -Url $LoginUrl -WaitForCompletion
        }
        elseif ($isHeadless) {
            # For direct headless mode, navigate directly
            $WebView2Core.Navigate($LoginUrl)
        }
        else {
            # For UI modes, use the login function
            Start-WebView2Login
        }

        # Get the user agent string
        $getUserAgentScript = "navigator.userAgent"
        if ($Script:WebView2HelperInitialized) {
            # Use C# helper for script execution
            $AgentString = Invoke-WebView2Script -Script $getUserAgentScript
            $AgentString = $AgentString.Trim('"') # Remove JSON quotes
        }
        elseif ($isHeadless) {
            $AgentString = $WebView2Core.ExecuteScriptAsync($getUserAgentScript).GetAwaiter().GetResult()
            $AgentString = $AgentString.Trim('"') # Remove JSON quotes
        }
        else {
            $AgentString = $WebView2Control.CoreWebView2.ExecuteScriptAsync($getUserAgentScript).GetAwaiter().GetResult()
            $AgentString = $AgentString.Trim('"') # Remove JSON quotes
        }

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

            # Handle automated login if credentials are provided
            if ($Script:Credential -and ![string]::IsNullOrWhiteSpace($Script:Credential.UserName)) {
                try {
                    if ($isHeadless) {
                        $currentUrl = $WebView2Core.Source
                    }
                    else {
                        $currentUrl = $WebView2Control.CoreWebView2.Source
                    }

                    if ($currentUrl -like "https://login.microsoftonline.com/*") {
                        # Check for username field
                        $checkUsernameScript = @"
                            var usernameField = document.getElementById('i0116');
                            var passwordField = document.getElementById('i0118');
                            var submitButton = document.getElementById('idSIButton9');
                            var backButton = document.getElementById('idBtn_Back');
                            var cantAccessAccount = document.getElementById('cantAccessAccount');

                            JSON.stringify({
                                hasUsername: usernameField !== null && usernameField.offsetParent !== null,
                                hasPassword: passwordField !== null && passwordField.offsetParent !== null,
                                hasSubmit: submitButton !== null && submitButton.offsetParent !== null,
                                hasBack: backButton !== null && backButton.offsetParent !== null,
                                hasCantAccess: cantAccessAccount !== null && cantAccessAccount.offsetParent !== null,
                                submitLabel: submitButton ? submitButton.textContent.trim() : '',
                                backLabel: backButton ? backButton.textContent.trim() : ''
                            });
"@

                        if ($isHeadless) {
                            $elementInfo = $WebView2Core.ExecuteScriptAsync($checkUsernameScript).GetAwaiter().GetResult()
                        }
                        else {
                            $elementInfo = $WebView2Control.CoreWebView2.ExecuteScriptAsync($checkUsernameScript).GetAwaiter().GetResult()
                        }
                        $elementInfo = $elementInfo.Trim('"').Replace('\"', '"')
                        $elements = ConvertFrom-Json $elementInfo

                        # Enter username
                        if ($elements.hasUsername -and $elements.hasPassword -and -not $elements.hasBack -and $elements.hasSubmit -and $elements.hasCantAccess -and $elements.submitLabel -eq "Next") {
                            "Enter username" | Write-Verbose
                            $enterUsernameScript = @"
                                var usernameField = document.getElementById('i0116');
                                var submitButton = document.getElementById('idSIButton9');
                                if (usernameField && submitButton) {
                                    usernameField.value = '$($Script:Credential.UserName)';
                                    usernameField.dispatchEvent(new Event('input', { bubbles: true }));
                                    setTimeout(function() { submitButton.click(); }, 100);
                                    return 'username_entered';
                                }
                                return 'username_failed';
"@
                            if ($isHeadless) {
                                $WebView2Core.ExecuteScriptAsync($enterUsernameScript).GetAwaiter().GetResult() | Out-Null
                            }
                            else {
                                $WebView2Control.CoreWebView2.ExecuteScriptAsync($enterUsernameScript).GetAwaiter().GetResult() | Out-Null
                            }
                        }

                        # Enter password
                        if (-not $elements.hasUsername -and $elements.hasPassword -and $elements.hasSubmit -and -not $elements.hasCantAccess -and $elements.submitLabel -eq "Sign in") {
                            "Enter password" | Write-Verbose
                            $enterPasswordScript = @"
                                var passwordField = document.getElementById('i0118');
                                var submitButton = document.getElementById('idSIButton9');
                                if (passwordField && submitButton) {
                                    passwordField.value = '$($Script:Credential.GetNetworkCredential().Password)';
                                    passwordField.dispatchEvent(new Event('input', { bubbles: true }));
                                    setTimeout(function() { submitButton.click(); }, 100);
                                    return 'password_entered';
                                }
                                return 'password_failed';
"@
                            if ($isHeadless) {
                                $WebView2Core.ExecuteScriptAsync($enterPasswordScript).GetAwaiter().GetResult() | Out-Null
                            }
                            else {
                                $WebView2Control.CoreWebView2.ExecuteScriptAsync($enterPasswordScript).GetAwaiter().GetResult() | Out-Null
                            }
                        }

                        # Handle "Stay signed in?" dialog
                        if (-not $elements.hasUsername -and -not $elements.hasPassword -and $elements.hasBack -and $elements.hasSubmit -and $elements.backLabel -eq "No" -and $elements.submitLabel -eq "Yes") {
                            "Decline Stay signed in?" | Write-Verbose
                            $declineStaySignedInScript = @"
                                var backButton = document.getElementById('idBtn_Back');
                                if (backButton) {
                                    backButton.click();
                                    return 'declined_stay_signed_in';
                                }
                                return 'decline_failed';
"@
                            if ($isHeadless) {
                                $WebView2Core.ExecuteScriptAsync($declineStaySignedInScript).GetAwaiter().GetResult() | Out-Null
                            }
                            else {
                                $WebView2Control.CoreWebView2.ExecuteScriptAsync($declineStaySignedInScript).GetAwaiter().GetResult() | Out-Null
                            }
                        }

                        # Handle MFA display
                        $checkMfaScript = @"
                            var mfaElement = document.getElementById('idRichContext_DisplaySign');
                            if (mfaElement && mfaElement.offsetParent !== null) {
                                return mfaElement.textContent.trim();
                            }
                            return '';
"@

                        if ($isHeadless) {
                            $mfaText = $WebView2Core.ExecuteScriptAsync($checkMfaScript).GetAwaiter().GetResult()
                        }
                        else {
                            $mfaText = $WebView2Control.CoreWebView2.ExecuteScriptAsync($checkMfaScript).GetAwaiter().GetResult()
                        }
                        $mfaText = $mfaText.Trim('"')

                        if (-not $MfaRequestDisplayed -and ![string]::IsNullOrWhiteSpace($mfaText)) {
                            $Message = "`nWaiting for your approve this sign-in request."
                            if ($PhoneLinkActive) {
                                $Message = "{0}. {1} (This value is now in your clipboard so you can paste it into your Authenticator app using PhoneLink)." -f $Message.TrimEnd("."), $mfaText
                                $mfaText | Set-Clipboard
                            }
                            else {
                                $Message = "{0}. {1}" -f $Message.TrimEnd("."), $mfaText
                            }
                            $Message | Write-Host -ForegroundColor Yellow
                            $MfaRequestDisplayed = $true
                        }
                    }
                }
                catch {
                    "Error during automated login: {0}" -f $_.Exception.Message | Write-Verbose
                }
            }

            # Check if we're on the Omada domain and look for the authentication cookie
            if ($isHeadless) {
                $currentUrl = $WebView2Core.Source
            }
            else {
                $currentUrl = $WebView2Control.CoreWebView2.Source
            }
            $WebView2Host = "-1"
            $OmadaWebBaseHost = "-2"
            $WebView2AbsolutePath = $null

            if (![string]::IsNullOrWhiteSpace($currentUrl)) {
                try {
                    $uri = [System.Uri]::new($currentUrl)
                    $WebView2Host = $uri.Host
                    $WebView2AbsolutePath = $uri.AbsolutePath
                    $OmadaWebBaseHost = [System.Uri]::new($Script:OmadaWebBaseUrl).Host
                }
                catch {
                    "Error parsing URL: {0}" -f $_.Exception.Message | Write-Verbose
                }
            }

            # Check if we're on the correct domain and path
            if ($OmadaWebBaseHost -eq $WebView2Host -and ($WebView2AbsolutePath -eq "/home" -or $WebView2AbsolutePath -eq "/")) {
                # Get all cookies
                $getCookiesScript = @"
                    var cookies = document.cookie.split(';');
                    var authCookie = null;
                    for (var i = 0; i < cookies.length; i++) {
                        var cookie = cookies[i].trim();
                        if (cookie.startsWith('oisauthtoken=')) {
                            var cookieParts = cookie.split('=');
                            authCookie = {
                                name: cookieParts[0],
                                value: cookieParts.slice(1).join('='),
                                domain: window.location.hostname
                            };
                            break;
                        }
                    }
                    JSON.stringify(authCookie);
"@

                try {
                    if ($Script:WebView2HelperInitialized) {
                        # Use C# helper to get cookies directly
                        $cookies = Get-WebView2Cookies
                        $authCookie = $cookies | Where-Object { $_.name -eq "oisauthtoken" }

                        if ($authCookie) {
                            $AuthCookie = [PSCustomObject]@{
                                Name   = $authCookie.name
                                Value  = $authCookie.value
                                Domain = $authCookie.domain
                                Path   = $authCookie.path
                            }
                            "Authentication cookie retrieved successfully via helper" | Write-Verbose
                        }
                    }
                    else {
                        # Fallback to JavaScript execution
                        if ($isHeadless) {
                            $cookieResult = $WebView2Core.ExecuteScriptAsync($getCookiesScript).GetAwaiter().GetResult()
                        }
                        else {
                            $cookieResult = $WebView2Control.CoreWebView2.ExecuteScriptAsync($getCookiesScript).GetAwaiter().GetResult()
                        }
                        $cookieResult = $cookieResult.Trim('"').Replace('\"', '"')

                        if ($cookieResult -ne "null" -and ![string]::IsNullOrWhiteSpace($cookieResult)) {
                            $cookieObject = ConvertFrom-Json $cookieResult
                            if ($cookieObject -and $cookieObject.name -eq "oisauthtoken") {
                                # Create a cookie object similar to Selenium's format
                                $AuthCookie = [PSCustomObject]@{
                                    Name   = $cookieObject.name
                                    Value  = $cookieObject.value
                                    Domain = $cookieObject.domain
                                    Path   = "/"
                                }
                                "Authentication cookie retrieved successfully" | Write-Verbose
                            }
                        }
                    }
                }
                catch {
                    "Error retrieving cookie: {0}" -f $_.Exception.Message | Write-Verbose
                }
            }

            # Check if browser was closed (only applies to UI modes)
            $browserClosed = $false
            if (-not $isHeadless) {
                $browserClosed = (-not $Script:WebView2Form -or $Script:WebView2Form.IsDisposed -or -not $Script:WebView2Form.Visible)
            }

            if ($browserClosed) {
                if ($Script:LoginRetryCount -ge 3) {
                    Close-WebView2
                    "`nLogin retry count exceeded! Please check your credentials as no cookie could be retrieved!" | Write-Error -ErrorAction "Stop" -Category AuthenticationError
                }
                else {
                    "`n{0} - Login retry count: {1}" -f $MyInvocation.MyCommand, $Script:LoginRetryCount | Write-Verbose
                }

                "" | Write-Host
                "Browser window was closed before authentication was completed. Re-opening browser!" | Write-Host -ForegroundColor Yellow
                $LoginMessageShown = $false
                Close-WebView2

                # Retry with the same approach that worked initially
                if ($isHeadless) {
                    $WebView2Core = Start-WebView2Headless -InPrivate:$InPrivate.IsPresent -EdgeProfile $EdgeProfile
                    $LoginUrl = "{0}/login" -f $Script:OmadaWebBaseUrl.TrimEnd('/')
                    $WebView2Core.Navigate($LoginUrl)
                }
                else {
                    # Try different UI approaches
                    try {
                        $WebView2Control = Start-WebView2Minimal -InPrivate:$InPrivate.IsPresent -EdgeProfile $EdgeProfile
                    }
                    catch {
                        try {
                            $WebView2Control = Start-WebView2Simple -InPrivate:$InPrivate.IsPresent -EdgeProfile $EdgeProfile
                        }
                        catch {
                            $WebView2Control = Start-WebView2 -InPrivate:$InPrivate.IsPresent -EdgeProfile $EdgeProfile
                        }
                    }
                    Start-WebView2Login
                }
                $Script:LoginRetryCount++
            }

            # Process Windows messages to keep the form responsive (UI modes only)
            if (-not $isHeadless) {
                try {
                    [System.Windows.Forms.Application]::DoEvents()
                }
                catch {
                    # If DoEvents fails, just continue
                }
            }
            else {
                # For headless mode, just add a small delay
                Start-Sleep -Milliseconds 100
            }

        }
        until($null -ne $AuthCookie -or $Script:LoginRetryCount -gt 3)

        # Cleanup WebView2 resources
        if ($Script:WebView2HelperInitialized) {
            Stop-WebView2Helper
        }
        else {
            Close-WebView2
        }

        if ($null -ne $AuthCookie) {
            $Script:LoginRetryCount = 0
            "Authentication successful with WebView2" | Write-Verbose
            return $AuthCookie, $AgentString
        }
        else {
            "Could not authenticate to '{0}'" -f $Script:OmadaWebBaseUrl | Write-Error -ErrorAction "Stop"
        }
    }
    catch {
        # Cleanup WebView2 resources on error
        if ($Script:WebView2HelperInitialized) {
            Stop-WebView2Helper
        }
        else {
            Close-WebView2
        }
        "Failed to retrieve data from WebView2: {0}" -f $_.Exception.Message | Write-Error
        throw
    }
}