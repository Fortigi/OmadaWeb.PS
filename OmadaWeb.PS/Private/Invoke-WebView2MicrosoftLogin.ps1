function Invoke-WebView2MicrosoftLogin {
    [CmdletBinding()]
    param(    )

    try {
        # Check if login has already failed - don't attempt again
        if ($Script:LoginFailed) {
            "Login previously failed - not attempting again" | Write-Verbose
            return $false
        }

        # Check if we have credentials
        if (-not $Script:Credential -or [string]::IsNullOrWhiteSpace($Script:Credential.UserName)) {
            return
        }

        if ($null -eq $Script:WebView2 -or $null -eq $Script:WebView2.CoreWebView2) {
            return
        }

        if (!$Script:MicrosoftOnlineLogin ) {
            return
        }

        # Element IDs used by Microsoft login
        $UserNameElementId = "i0116"
        $PasswordElementId = "i0118"
        $SubmitButtonId = "idSIButton9"
        $CantAccessAccountId = "cantAccessAccount"
        $MfaElementId = "idRichContext_DisplaySign"
        $MfaRetryId1 = "idA_SAASTO_Resend"
        $MfaRetryId2 = "idA_SAASDS_Resend"
        $ButtonBackId = "idBtn_Back"

        # JavaScript to get all element IDs on the page
        $getAllIdsScript = @"
(function() {
    var elements = document.querySelectorAll('[id]');
    var ids = [];
    for (var i = 0; i < elements.length; i++) {
        ids.push(elements[i].id);
    }
    return ids;
})();
"@

        # JavaScript to get element property
        $getElementPropertyScript = @"
(function(elementId, property) {
    var element = document.getElementById(elementId);
    if (element) {
        return element[property] || element.getAttribute(property);
    }
    return null;
})
"@

        # JavaScript to set element value and trigger events
        $setElementValueScript = @"
(function(elementId, value) {
    var element = document.getElementById(elementId);
    if (element) {
        element.value = value;
        element.dispatchEvent(new Event('input', { bubbles: true }));
        element.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
    }
    return false;
})
"@

        # JavaScript to click element
        $clickElementScript = @"
(function(elementId) {
    var element = document.getElementById(elementId);
    if (element) {
        element.click();
        return true;
    }
    return false;
})
"@

        # JavaScript to check if element is visible and enabled
        $isElementVisibleScript = @"
(function(elementId) {
    var element = document.getElementById(elementId);
    if (!element) return false;

    var style = window.getComputedStyle(element);
    var isVisible = style.display !== 'none' &&
                    style.visibility !== 'hidden' &&
                    style.opacity !== '0' &&
                    element.offsetWidth > 0 &&
                    element.offsetHeight > 0;

    var isEnabled = !element.disabled && !element.readOnly;

    return isVisible && isEnabled;
})
"@

        # JavaScript to get element by data-test-id
        $getElementByDataTestIdScript = @"
(function(dataTestId) {
    var elements = document.querySelectorAll('[data-test-id]');
    for (var i = 0; i < elements.length; i++) {
        if (elements[i].getAttribute('data-test-id') === dataTestId) {
            elements[i].click();
            return true;
        }
    }
    return false;
})
"@

        # JavaScript to click "Use another account" option
        $clickUseAnotherAccountScript = @"
(function() {
    // Try by aria-labelledby first
    var otherAccount = document.querySelector('[aria-labelledby="otherTileText"]');
    if (otherAccount) {
        otherAccount.click();
        return true;
    }
    return false;
})();
"@

        # JavaScript to check for error messages
        $checkForErrorScript = @"
(function() {
    // Check for common error element IDs and classes
    var errorIds = ['passwordError', 'usernameError'];
    var errorTexts = ['incorrect', 'invalid', 'wrong password', 'wrong username', 'not recognized'];

    // Check by ID
    for (var i = 0; i < errorIds.length; i++) {
        var elem = document.getElementById(errorIds[i]);
        if (elem && elem.offsetHeight > 0) {
            return elem.textContent || elem.innerText;
        }
    }

    // Check by role and aria-live
    var alerts = document.querySelectorAll('[role="alert"], [aria-live="assertive"], [aria-live="polite"]');
    for (var i = 0; i < alerts.length; i++) {
        if (alerts[i].offsetHeight > 0) {
            var text = alerts[i].textContent || alerts[i].innerText;
            if (text && text.trim().length > 0) {
                // Check if it contains error keywords
                var lowerText = text.toLowerCase();
                for (var j = 0; j < errorTexts.length; j++) {
                    if (lowerText.indexOf(errorTexts[j]) !== -1) {
                        return text;
                    }
                }
            }
        }
    }

    return null;
})();
"@

        # Check if we're on the Microsoft login page
        if ($Script:WebView2.Source.Host -ne [System.Uri]::New("https://login.microsoftonline.com").Host) {
            $Script:MicrosoftOnlineLogin = $false
            # Reset state when leaving login page
            $Script:LoginState = $null
            $Script:LoginTask = $null
            $Script:IdAttributes = $null
            $Script:PreviousIdAttributes = $null
            $Script:LoginSubState = $null
            $Script:BackButtonText = $null
            $Script:LoginFailed = $false
            $Script:ActiveScenario = $null
            return $false
        }

        # Initialize login state if needed
        if ($null -eq $Script:LoginState) {
            $Script:LoginState = "GettingIds"
            $Script:LoginTask = $null
            $Script:LoginSubState = $null
        }

        # State machine for non-blocking async operations
        switch ($Script:LoginState) {
            "GettingIds" {
                if ($null -eq $Script:LoginTask) {
                    # Start the async task to get IDs
                    "Getting page element IDs..." | Write-Verbose
                    $Script:LoginTask = $WebView2.CoreWebView2.ExecuteScriptAsync($getAllIdsScript)
                    return $false  # Come back on next timer tick
                }

                # Check if task is complete (non-blocking)
                if ($Script:LoginTask.IsCompleted) {
                    if ($Script:LoginTask.IsFaulted) {
                        "Failed to get element IDs: $($Script:LoginTask.Exception.Message)" | Write-Verbose
                        $Script:LoginState = "GettingIds"
                        $Script:LoginTask = $null
                        return $false
                    }

                    $IdsJson = $Script:LoginTask.Result
                    $Script:IdAttributes = $IdsJson | ConvertFrom-Json

                    if ($null -eq $Script:IdAttributes -or $Script:IdAttributes.Count -eq 0) {
                        "No element IDs found on page, retrying..." | Write-Verbose
                        $Script:LoginState = "GettingIds"
                        $Script:LoginTask = $null
                        return $false
                    }

                    # Check if page has changed (different IDs) - if so, reset active scenario
                    if ($null -ne $Script:PreviousIdAttributes) {
                        $idsChanged = $false
                        # Check if key elements changed
                        $prevHadUsername = $Script:PreviousIdAttributes -contains "i0116"
                        $prevHadPassword = $Script:PreviousIdAttributes -contains "i0118"
                        $nowHasUsername = $Script:IdAttributes -contains "i0116"
                        $nowHasPassword = $Script:IdAttributes -contains "i0118"

                        if ($prevHadUsername -ne $nowHasUsername -or $prevHadPassword -ne $nowHasPassword) {
                            $idsChanged = $true
                            "Page changed detected - resetting active scenario" | Write-Verbose
                        }

                        if ($idsChanged) {
                            $Script:ActiveScenario = $null
                            $Script:LoginSubState = $null
                        }
                    }

                    # Store current IDs for next comparison
                    $Script:PreviousIdAttributes = $Script:IdAttributes

                    # Move to processing scenarios
                    "Found $($Script:IdAttributes.Count) element IDs on page" | Write-Verbose
                    $Script:LoginState = "ProcessingScenarios"
                    $Script:LoginTask = $null
                    return $false  # Process scenarios on next tick
                }

                # Task still running, check again on next tick
                return $false
            }

            "ProcessingScenarios" {
                # Now we have IdAttributes, process all scenarios
                $IdAttributes = $Script:IdAttributes

                # Debug: Log what IDs we found
                "Page IDs found: $($IdAttributes -join ', ')" | Write-Verbose
                "Looking for username: $UserNameElementId, password: $PasswordElementId, submit: $SubmitButtonId" | Write-Verbose
                "Username exists: $($IdAttributes -contains $UserNameElementId)" | Write-Verbose
                "Password exists: $($IdAttributes -contains $PasswordElementId)" | Write-Verbose
                "CantAccessAccount exists: $($IdAttributes -contains $CantAccessAccountId)" | Write-Verbose
                "SubmitButton exists: $($IdAttributes -contains $SubmitButtonId)" | Write-Verbose
                "ButtonBack exists: $($IdAttributes -contains $ButtonBackId)" | Write-Verbose

                # Scenario 1: Username entry page
                # Check if username field exists - we'll verify visibility in the sub-state
                if ($IdAttributes -contains $UserNameElementId `
                        -and $IdAttributes -contains $SubmitButtonId `
                        -and ($null -eq $Script:ActiveScenario -or $Script:ActiveScenario -eq "Scenario1")) {
                    "Scenario 1: Username entry page" | Write-Verbose
                    # Sub-state machine for username entry
                    switch ($Script:LoginSubState) {
                        $null {
                            # First check for error messages
                            "Checking for error messages on page..." | Write-Verbose
                            $Script:LoginTask = $WebView2.CoreWebView2.ExecuteScriptAsync($checkForErrorScript)
                            $Script:LoginSubState = "CheckingForError"
                            return $false
                        }
                        "CheckingForError" {
                            if ($Script:LoginTask.IsCompleted) {
                                if (-not $Script:LoginTask.IsFaulted) {
                                    $errorMessage = $Script:LoginTask.Result -replace '"', ''
                                    if (-not [string]::IsNullOrWhiteSpace($errorMessage) -and $errorMessage -ne "null") {
                                        Write-Warning "Login error detected: $errorMessage"
                                        Write-Warning "Please verify your credentials and try again. Automatic login aborted."
                                        $Script:LoginFailed = $true
                                        $Script:LoginState = $null
                                        $Script:LoginSubState = $null
                                        $Script:IdAttributes = $null
                                        $Script:LoginTask = $null
                                        $Script:ActiveScenario = $null
                                        $Script:MicrosoftOnlineLogin = $false
                                        return $false
                                    }
                                }
                                # No error, proceed to check username field visibility
                                $Script:LoginTask = $WebView2.CoreWebView2.ExecuteScriptAsync("$isElementVisibleScript('$UserNameElementId')")
                                $Script:LoginSubState = "CheckingUsernameField"
                            }
                            return $false
                        }
                        "CheckingUsernameField" {
                            if ($Script:LoginTask.IsCompleted) {
                                if (-not $Script:LoginTask.IsFaulted) {
                                    $isVisible = $Script:LoginTask.Result
                                    "Username field visibility check result: $isVisible" | Write-Verbose
                                    if ($isVisible -eq "true") {
                                        "Matched Scenario 1: Username entry page" | Write-Verbose
                                        $Script:ActiveScenario = "Scenario1"
                                        "Username field is visible, entering username..." | Write-Verbose
                                        $usernameScript = "$setElementValueScript('$UserNameElementId', '$($Script:Credential.UserName)')"
                                        $Script:LoginTask = $WebView2.CoreWebView2.ExecuteScriptAsync($usernameScript)
                                        $Script:LoginSubState = "SettingUsername"
                                    }
                                    else {
                                        # Field not visible, not username page - reset to check other scenarios
                                        "Username field not visible, trying other scenarios..." | Write-Verbose
                                        $Script:LoginSubState = $null
                                        $Script:ActiveScenario = $null
                                        # Don't return - let other scenarios be checked
                                    }
                                }
                                else {
                                    # Task faulted, reset
                                    "Username field check faulted: $($Script:LoginTask.Exception.Message)" | Write-Verbose
                                    $Script:LoginSubState = $null
                                    $Script:ActiveScenario = $null
                                    $Script:MicrosoftOnlineLogin = $false

                                }
                            }
                            return $false
                        }
                        "SettingUsername" {
                            if ($Script:LoginTask.IsCompleted) {
                                if (-not $Script:LoginTask.IsFaulted) {
                                    "Username set, clicking submit..." | Write-Verbose
                                    Start-Sleep -Milliseconds 200
                                    $clickScript = "$clickElementScript('$SubmitButtonId')"
                                    $Script:LoginTask = $WebView2.CoreWebView2.ExecuteScriptAsync($clickScript)
                                    $Script:LoginSubState = "ClickingSubmit"
                                }
                                else {
                                    # Failed to set username, reset
                                    "Failed to set username: $($Script:LoginTask.Exception.Message)" | Write-Verbose
                                    $Script:LoginSubState = $null
                                    $Script:ActiveScenario = $null
                                    $Script:MicrosoftOnlineLogin = $false
                                }
                            }
                            return $false
                        }
                        "ClickingSubmit" {
                            if ($Script:LoginTask.IsCompleted) {
                                "Clicked submit, waiting for page change..." | Write-Verbose
                                # Reset state to detect next page
                                $Script:LoginState = "GettingIds"
                                $Script:LoginSubState = $null
                                $Script:IdAttributes = $null
                                $Script:LoginTask = $null
                                $Script:ActiveScenario = $null
                                return $true
                            }
                            return $false
                        }
                    }
                }

                # Scenario 2: Password entry page
                # Check if password field exists - we'll verify visibility in the sub-state
                if ($IdAttributes -contains $PasswordElementId `
                        -and $IdAttributes -contains $SubmitButtonId `
                        -and ($null -eq $Script:ActiveScenario -or $Script:ActiveScenario -eq "Scenario2")) {

                    "Scenario 2: Password entry page" | Write-Verbose

                    # Sub-state machine for password entry
                    switch ($Script:LoginSubState) {
                        $null {
                            # First check for error messages
                            "Checking for error messages on page..." | Write-Verbose
                            $Script:LoginTask = $WebView2.CoreWebView2.ExecuteScriptAsync($checkForErrorScript)
                            $Script:LoginSubState = "CheckingForError"
                            return $false
                        }
                        "CheckingForError" {
                            if ($Script:LoginTask.IsCompleted) {
                                if (-not $Script:LoginTask.IsFaulted) {
                                    $errorMessage = $Script:LoginTask.Result -replace '"', ''
                                    if (-not [string]::IsNullOrWhiteSpace($errorMessage) -and $errorMessage -ne "null") {
                                        "Login error detected: $errorMessage" | Write-Warning
                                        "Please verify your credentials and try again. Automatic login aborted." | Write-Warning
                                        $Script:LoginFailed = $true
                                        $Script:LoginState = $null
                                        $Script:LoginSubState = $null
                                        $Script:IdAttributes = $null
                                        $Script:LoginTask = $null
                                        $Script:ActiveScenario = $null
                                        $Script:MicrosoftOnlineLogin = $false
                                        return $false
                                    }
                                }
                                # No error, proceed to check password field visibility
                                $Script:LoginTask = $WebView2.CoreWebView2.ExecuteScriptAsync("$isElementVisibleScript('$PasswordElementId')")
                                $Script:LoginSubState = "CheckingPasswordField"
                            }
                            return $false
                        }
                        "CheckingPasswordField" {
                            if ($Script:LoginTask.IsCompleted) {
                                if (-not $Script:LoginTask.IsFaulted) {
                                    $isVisible = $Script:LoginTask.Result
                                    "Password field visibility check result: $isVisible" | Write-Verbose
                                    if ($isVisible -eq "true") {
                                        "Matched Scenario 2: Password entry page" | Write-Verbose
                                        $Script:ActiveScenario = "Scenario2"
                                        "Password field is visible, entering password..." | Write-Verbose
                                        $password = $Script:Credential.GetNetworkCredential().Password
                                        $passwordScript = "$setElementValueScript('$PasswordElementId', '$password')"
                                        $Script:LoginTask = $WebView2.CoreWebView2.ExecuteScriptAsync($passwordScript)
                                        $Script:LoginSubState = "SettingPassword"
                                    }
                                    else {
                                        # Field not visible, not password page - reset to check other scenarios
                                        "Password field not visible, trying other scenarios..." | Write-Verbose
                                        $Script:LoginSubState = $null
                                        $Script:ActiveScenario = $null
                                        # Don't return - let other scenarios be checked
                                    }
                                }
                                else {
                                    # Task faulted, reset
                                    "Password field check faulted: $($Script:LoginTask.Exception.Message)" | Write-Verbose
                                    $Script:LoginSubState = $null
                                    $Script:ActiveScenario = $null
                                }
                            }
                            return $false
                        }
                        "SettingPassword" {
                            if ($Script:LoginTask.IsCompleted) {
                                if (-not $Script:LoginTask.IsFaulted) {
                                    "Password set, clicking submit..." | Write-Verbose
                                    Start-Sleep -Milliseconds 200
                                    $clickScript = "$clickElementScript('$SubmitButtonId')"
                                    $Script:LoginTask = $WebView2.CoreWebView2.ExecuteScriptAsync($clickScript)
                                    $Script:LoginSubState = "ClickingSubmit"
                                }
                                else {
                                    # Failed to set password, reset
                                    "Failed to set password: $($Script:LoginTask.Exception.Message)" | Write-Verbose
                                    $Script:LoginSubState = $null
                                    $Script:ActiveScenario = $null
                                }
                            }
                            return $false
                        }
                        "ClickingSubmit" {
                            if ($Script:LoginTask.IsCompleted) {
                                "Clicked submit, waiting for page change..." | Write-Verbose
                                # Reset state to detect next page
                                $Script:LoginState = "GettingIds"
                                $Script:LoginSubState = $null
                                $Script:IdAttributes = $null
                                $Script:LoginTask = $null
                                $Script:ActiveScenario = $null
                                return $true
                            }
                            return $false
                        }
                    }
                }

                # Scenario 3: "Stay signed in?" page - Click "No"
                if ($IdAttributes -notcontains $UserNameElementId `
                        -and $IdAttributes -notcontains $PasswordElementId `
                        -and $IdAttributes -contains $ButtonBackId `
                        -and $IdAttributes -contains $SubmitButtonId) {

                    "Scenario 3: 'Stay signed in?' page" | Write-Verbose
                    # Sub-state machine for "Stay signed in?" prompt
                    switch ($Script:LoginSubState) {
                        $null {
                            # Start checking back button text
                            "Detected 'Stay signed in?' page, checking button labels..." | Write-Verbose
                            $Script:LoginTask = $WebView2.CoreWebView2.ExecuteScriptAsync("$getElementPropertyScript('$ButtonBackId', 'textContent')")
                            $Script:LoginSubState = "CheckingBackButton"
                            return $false
                        }
                        "CheckingBackButton" {
                            if ($Script:LoginTask.IsCompleted) {
                                if (-not $Script:LoginTask.IsFaulted) {
                                    $Script:BackButtonText = $Script:LoginTask.Result -replace '"', ''
                                    # Now check submit button
                                    $Script:LoginTask = $WebView2.CoreWebView2.ExecuteScriptAsync("$getElementPropertyScript('$SubmitButtonId', 'textContent')")
                                    $Script:LoginSubState = "CheckingSubmitButton"
                                }
                                else {
                                    $Script:LoginSubState = $null
                                }
                            }
                            return $false
                        }
                        "CheckingSubmitButton" {
                            if ($Script:LoginTask.IsCompleted) {
                                if (-not $Script:LoginTask.IsFaulted) {
                                    $submitText = $Script:LoginTask.Result -replace '"', ''
                                    if ($Script:BackButtonText -like "*No*" -and $submitText -like "*Yes*") {
                                        "Clicking 'No' to stay signed in prompt..." | Write-Verbose
                                        $clickScript = "$clickElementScript('$ButtonBackId')"
                                        $Script:LoginTask = $WebView2.CoreWebView2.ExecuteScriptAsync($clickScript)
                                        $Script:LoginSubState = "ClickingNo"
                                    }
                                    else {
                                        # Buttons don't match expected text, reset
                                        $Script:LoginSubState = $null
                                        $Script:BackButtonText = $null
                                    }
                                }
                                else {
                                    $Script:LoginSubState = $null
                                    $Script:BackButtonText = $null
                                }
                            }
                            return $false
                        }
                        "ClickingNo" {
                            if ($Script:LoginTask.IsCompleted) {
                                "Clicked No, waiting for page change..." | Write-Verbose
                                # Reset state to detect next page
                                $Script:LoginState = "GettingIds"
                                $Script:LoginSubState = $null
                                $Script:IdAttributes = $null
                                $Script:LoginTask = $null
                                $Script:BackButtonText = $null
                                return $true
                            }
                            return $false
                        }
                    }
                }

                # Scenario 4: Select account by data-test-id
                if ($IdAttributes -notcontains $UserNameElementId `
                        -and $IdAttributes -notcontains $PasswordElementId `
                        -and $IdAttributes -notcontains $ButtonBackId) {

                    "Scenario 4: Account selection page" | Write-Verbose
                    # Sub-state for account selection
                    switch ($Script:LoginSubState) {
                        $null {
                            # Try to click account with matching data-test-id
                            "Attempting to select account..." | Write-Verbose
                            $clickAccountScript = "$getElementByDataTestIdScript('$($Script:Credential.UserName)')"
                            $Script:LoginTask = $WebView2.CoreWebView2.ExecuteScriptAsync($clickAccountScript)
                            $Script:LoginSubState = "ClickingAccount"
                            $Script:AccountSelectionAttempted = $false
                            return $false
                        }
                        "ClickingAccount" {
                            if ($Script:LoginTask.IsCompleted) {
                                if (-not $Script:LoginTask.IsFaulted) {
                                    $result = $Script:LoginTask.Result
                                    if ($result -eq "true") {
                                        "Selected logged-in account" | Write-Verbose
                                        # Reset state to detect next page
                                        $Script:LoginState = "GettingIds"
                                        $Script:LoginSubState = $null
                                        $Script:IdAttributes = $null
                                        $Script:LoginTask = $null
                                        $Script:AccountSelectionAttempted = $false
                                        return $true
                                    }
                                    else {
                                        # Account not found - try "Use another account" if not already attempted
                                        if (-not $Script:AccountSelectionAttempted) {
                                            "Account not found in list, clicking 'Use another account'..." | Write-Verbose
                                            $Script:LoginTask = $WebView2.CoreWebView2.ExecuteScriptAsync($clickUseAnotherAccountScript)
                                            $Script:LoginSubState = "ClickingUseAnotherAccount"
                                            $Script:AccountSelectionAttempted = $true
                                        }
                                        else {
                                            # Already tried, reset and wait
                                            "Could not find 'Use another account' option" | Write-Verbose
                                            $Script:LoginSubState = $null
                                            $Script:AccountSelectionAttempted = $false
                                        }
                                    }
                                }
                                else {
                                    # Task faulted, reset
                                    $Script:LoginSubState = $null
                                    $Script:AccountSelectionAttempted = $false
                                }
                            }
                            return $false
                        }
                        "ClickingUseAnotherAccount" {
                            if ($Script:LoginTask.IsCompleted) {
                                if (-not $Script:LoginTask.IsFaulted) {
                                    $result = $Script:LoginTask.Result
                                    if ($result -eq "true") {
                                        "Clicked 'Use another account', going to username entry..." | Write-Verbose
                                        # Reset state to detect username page
                                        $Script:LoginState = "GettingIds"
                                        $Script:LoginSubState = $null
                                        $Script:IdAttributes = $null
                                        $Script:LoginTask = $null
                                        $Script:AccountSelectionAttempted = $false
                                        return $true
                                    }
                                    else {
                                        "'Use another account' option not found" | Write-Verbose
                                    }
                                }
                                # Failed or not found, reset
                                $Script:LoginSubState = $null
                                $Script:AccountSelectionAttempted = $false
                            }
                            return $false
                        }
                    }
                }

                # Scenario 5: MFA request
                if (-not $Script:MfaRequestDisplayed `
                        -and $IdAttributes -notcontains $UserNameElementId `
                        -and $IdAttributes -notcontains $PasswordElementId `
                        -and $IdAttributes -contains $MfaElementId `
                        -and $IdAttributes -notcontains $MfaRetryId1 `
                        -and $IdAttributes -notcontains $MfaRetryId2) {

                    "Scenario 5: MFA request page" | Write-Verbose
                    # Sub-state for MFA code retrieval
                    switch ($Script:LoginSubState) {
                        $null {
                            # Get MFA code
                            "Detected MFA page, retrieving code..." | Write-Verbose
                            $Script:LoginTask = $WebView2.CoreWebView2.ExecuteScriptAsync("$getElementPropertyScript('$MfaElementId', 'textContent')")
                            $Script:LoginSubState = "GettingMfaCode"
                            return $false
                        }
                        "GettingMfaCode" {
                            if ($Script:LoginTask.IsCompleted) {
                                if (-not $Script:LoginTask.IsFaulted) {
                                    $mfaText = $Script:LoginTask.Result -replace '"', ''

                                    if (-not [string]::IsNullOrWhiteSpace($mfaText)) {
                                        $Message = "`nWaiting for you to approve this sign-in request."

                                        # Check if PhoneLink is active
                                        $PhoneLinkActive = $false
                                        if ((Get-Process | Where-Object { $_.ProcessName -eq "PhoneExperienceHost" } | Measure-Object).Count -gt 0) {
                                            $PhoneLinkActive = $true
                                        }

                                        if ($PhoneLinkActive) {
                                            $Message = "{0} {1} (This value is now in your clipboard so you can paste it into your Authenticator app using PhoneLink)." -f $Message.TrimEnd("."), $mfaText
                                            $mfaText | Set-Clipboard
                                        }
                                        else {
                                            $Message = "{0} {1}" -f $Message.TrimEnd("."), $mfaText
                                        }

                                        $Message | Write-Host -ForegroundColor Yellow
                                        $Script:MfaRequestDisplayed = $true
                                        $Script:LoginSubState = $null
                                        return $true
                                    }
                                }
                                # Failed or empty MFA code, reset
                                $Script:LoginSubState = $null
                            }
                            return $false
                        }
                    }
                }

                # Scenario 6: MFA retry
                if ($Script:MfaRequestDisplayed `
                        -and $IdAttributes -notcontains $UserNameElementId `
                        -and $IdAttributes -notcontains $PasswordElementId `
                        -and $IdAttributes -notcontains $MfaElementId `
                        -and ($IdAttributes -contains $MfaRetryId1 -or $IdAttributes -contains $MfaRetryId2)) {

                    "Scenario 6: MFA retry page" | Write-Verbose
                    "`nMFA failed! Please retry!" | Write-Warning
                    $Script:MfaRequestDisplayed = $false
                    # Reset state to detect next page
                    $Script:LoginState = "GettingIds"
                    $Script:IdAttributes = $null
                    return $true
                }

                # No scenario matched, stay in this state and wait for next timer tick
                return $false
            }
        }

        # Shouldn't reach here, but return false just in case
        return $false
    }
    catch {
        [Console]::WriteLine("Error in Invoke-WebView2MicrosoftLogin: $_")
        # Reset state on error
        $Script:LoginState = "GettingIds"
        $Script:LoginTask = $null
        $Script:IdAttributes = $null
        $Script:LoginSubState = $null
        $Script:BackButtonText = $null
        return $false
    }
}
