function Invoke-WebView2MicrosoftLogin {
    [CmdletBinding()]
    param(    )

    try {
        # Check if we have credentials
        if (-not $Script:Credential -or [string]::IsNullOrWhiteSpace($Script:Credential.UserName)) {
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

        # Get all IDs on the page
        $Script:LoginTask = $WebView2.CoreWebView2.ExecuteScriptAsync($getAllIdsScript)

        $ScriptBlock = {
            if ($Script:LoginTask.IsFaulted) {
                return $null
            }
            elseif ($Script:LoginTask.IsCompleted) {
                [Console]::WriteLine("PipelineStoppedException")

                 $Script:LoginTask.Result | ConvertFrom-Json | Out-File ".\Result.json";
                 1/0
            }
            else {
                return $null
            }
        }
        if ($null -eq $Script:LoginTask) {
            return
        }
        $Result = $Script:LoginTask.GetAwaiter().OnCompleted($ScriptBlock)

        Write-Host "Hier"
        return

        if ($null -eq $IdAttributes) {
            return $false
        }

        # Scenario 1: Username entry page
        if ($IdAttributes -contains $UserNameElementId `
                -and $IdAttributes -contains $PasswordElementId `
                -and $IdAttributes -notcontains $ButtonBackId `
                -and $IdAttributes -contains $SubmitButtonId `
                -and $IdAttributes -contains $CantAccessAccountId) {

            # Check if button says "Next"
            $task = $WebView2.CoreWebView2.ExecuteScriptAsync("$getElementPropertyScript('$SubmitButtonId', 'textContent')")
            $task.Wait()
            $buttonText = $task.Result -replace '"', ''

            if ($buttonText -like "*Next*") {
                "Enter username" | Write-Verbose
                Start-Sleep -Milliseconds 500

                # Set username
                $usernameScript = "$setElementValueScript('$UserNameElementId', '$($Script:Credential.UserName)')"
                $task = $WebView2.CoreWebView2.ExecuteScriptAsync($usernameScript)
                $task.Wait()

                Start-Sleep -Milliseconds 200

                # Click submit
                $clickScript = "$clickElementScript('$SubmitButtonId')"
                $task = $WebView2.CoreWebView2.ExecuteScriptAsync($clickScript)
                $task.Wait()

                return $true
            }
        }

        # Scenario 2: Password entry page
        if ($IdAttributes -notcontains $UserNameElementId `
                -and $IdAttributes -contains $PasswordElementId `
                -and $IdAttributes -contains $SubmitButtonId `
                -and $IdAttributes -notcontains $CantAccessAccountId) {

            # Check if button says "Sign in"
            $task = $WebView2.CoreWebView2.ExecuteScriptAsync("$getElementPropertyScript('$SubmitButtonId', 'textContent')")
            $task.Wait()
            $buttonText = $task.Result -replace '"', ''

            if ($buttonText -like "*Sign in*") {
                "Enter password" | Write-Verbose
                Start-Sleep -Milliseconds 500

                # Set password
                $password = $Script:Credential.GetNetworkCredential().Password
                $passwordScript = "$setElementValueScript('$PasswordElementId', '$password')"
                $task = $WebView2.CoreWebView2.ExecuteScriptAsync($passwordScript)
                $task.Wait()

                Start-Sleep -Milliseconds 200

                # Click submit
                $clickScript = "$clickElementScript('$SubmitButtonId')"
                $task = $WebView2.CoreWebView2.ExecuteScriptAsync($clickScript)
                $task.Wait()

                return $true
            }
        }

        # Scenario 3: "Stay signed in?" page - Click "No"
        if ($IdAttributes -notcontains $UserNameElementId `
                -and $IdAttributes -notcontains $PasswordElementId `
                -and $IdAttributes -contains $ButtonBackId `
                -and $IdAttributes -contains $SubmitButtonId) {

            # Check button labels
            $task = $WebView2.CoreWebView2.ExecuteScriptAsync("$getElementPropertyScript('$ButtonBackId', 'textContent')")
            $task.Wait()
            $backText = $task.Result -replace '"', ''

            $task = $WebView2.CoreWebView2.ExecuteScriptAsync("$getElementPropertyScript('$SubmitButtonId', 'textContent')")
            $task.Wait()
            $submitText = $task.Result -replace '"', ''

            if ($backText -like "*No*" -and $submitText -like "*Yes*") {
                "Decline 'Stay signed in?'" | Write-Verbose

                # Click "No"
                $clickScript = "$clickElementScript('$ButtonBackId')"
                $task = $WebView2.CoreWebView2.ExecuteScriptAsync($clickScript)
                $task.Wait()

                return $true
            }
        }

        # Scenario 4: Select account by data-test-id
        if ($IdAttributes -notcontains $UserNameElementId `
                -and $IdAttributes -notcontains $PasswordElementId) {

            # Try to click account with matching data-test-id
            $clickAccountScript = "$getElementByDataTestIdScript('$($Script:Credential.UserName)')"
            $task = $WebView2.CoreWebView2.ExecuteScriptAsync($clickAccountScript)
            $task.Wait()
            $result = $task.Result

            if ($result -eq "true") {
                "Selected logged-in account" | Write-Verbose
                return $true
            }
        }

        # Scenario 5: MFA request
        if (-not $Script:MfaRequestDisplayed `
                -and $IdAttributes -notcontains $UserNameElementId `
                -and $IdAttributes -notcontains $PasswordElementId `
                -and $IdAttributes -contains $MfaElementId `
                -and $IdAttributes -notcontains $MfaRetryId1 `
                -and $IdAttributes -notcontains $MfaRetryId2) {

            # Get MFA code
            $task = $WebView2.CoreWebView2.ExecuteScriptAsync("$getElementPropertyScript('$MfaElementId', 'textContent')")
            $task.Wait()
            $mfaText = $task.Result -replace '"', ''

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
                return $true
            }
        }

        # Scenario 6: MFA retry
        if ($Script:MfaRequestDisplayed `
                -and $IdAttributes -notcontains $UserNameElementId `
                -and $IdAttributes -notcontains $PasswordElementId `
                -and $IdAttributes -notcontains $MfaElementId `
                -and ($IdAttributes -contains $MfaRetryId1 -or $IdAttributes -contains $MfaRetryId2)) {

            "`nMFA failed! Please retry!" | Write-Warning
            $Script:MfaRequestDisplayed = $false
            return $true
        }

        return $false
    }
    catch {
        [Console]::WriteLine("Error in Invoke-WebView2MicrosoftLogin: $_")
        return $false
    }
}
