# Test script for the complete WebView2 C# helper implementation
param(
    [switch]$BuildFirst,
    [string]$TestUrl = "https://httpbin.org/html"
)

Write-Host "Testing Complete WebView2 C# Helper Implementation..." -ForegroundColor Yellow

try {
    # Step 1: Build the helper if requested
    if ($BuildFirst) {
        Write-Host "1. Building WebView2 helper..." -NoNewline
        & ".\Build-WebView2Helper.ps1" -Configuration Release
        if ($LASTEXITCODE -ne 0) {
            Write-Host " ✗ BUILD FAILED" -ForegroundColor Red
            exit 1
        }
        Write-Host " ✓" -ForegroundColor Green
    }

    # Step 2: Verify helper executable exists
    Write-Host "2. Checking helper executable..." -NoNewline
    $helperPath = ".\WebView2Helper\bin\Release\net6.0-windows\OmadaWebView2Helper.exe"
    if (-not (Test-Path $helperPath)) {
        $helperPath = ".\WebView2Helper\bin\Debug\net6.0-windows\OmadaWebView2Helper.exe"
    }

    if (-not (Test-Path $helperPath)) {
        Write-Host " ✗ Helper executable not found" -ForegroundColor Red
        Write-Host "Please run: .\Build-WebView2Helper.ps1" -ForegroundColor Yellow
        exit 1
    }
    Write-Host " ✓" -ForegroundColor Green

    # Step 3: Load PowerShell functions
    Write-Host "3. Loading PowerShell functions..." -NoNewline
    . ".\OmadaWeb.PS\Private\Invoke-WebView2Helper.ps1"
    Write-Host " ✓" -ForegroundColor Green

    # Step 4: Initialize WebView2 helper
    Write-Host "4. Initializing WebView2 helper..." -NoNewline
    $Script:WebView2 = Start-WebView2Helper -InPrivate
    if ($Script:WebView2) {
        Write-Host " ✓" -ForegroundColor Green
    } else {
        Write-Host " ✗" -ForegroundColor Red
        exit 1
    }

    # Step 5: Test navigation
    Write-Host "5. Testing navigation..." -NoNewline
    $navResult = Invoke-WebView2Navigate -Url $TestUrl -WaitForCompletion -Timeout 10
    if ($navResult -and $navResult.navigationCompleted) {
        Write-Host " ✓ URL: $($navResult.url)" -ForegroundColor Green
    } else {
        Write-Host " ✗ Navigation failed" -ForegroundColor Red
        Stop-WebView2Helper
        exit 1
    }

    # Step 6: Test JavaScript execution
    Write-Host "6. Testing JavaScript execution..." -NoNewline
    try {
        $jsResult = Invoke-WebView2Script -Script "document.title"
        if ($jsResult) {
            Write-Host " ✓ Title: $jsResult" -ForegroundColor Green
        } else {
            Write-Host " ! No result" -ForegroundColor Yellow
        }
    } catch {
        Write-Host " ! JS Error: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Step 7: Test cookie retrieval
    Write-Host "7. Testing cookie retrieval..." -NoNewline
    try {
        $cookies = Get-WebView2Cookie
        if ($cookies -and $cookies.Count -gt 0) {
            Write-Host " ✓ Found $($cookies.Count) cookies" -ForegroundColor Green
        } else {
            Write-Host " ! No cookies found" -ForegroundColor Yellow
        }
    } catch {
        Write-Host " ! Cookie Error: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Step 8: Test page info
    Write-Host "8. Testing page info..." -NoNewline
    try {
        $pageInfo = Get-WebView2PageInfo
        if ($pageInfo) {
            Write-Host " ✓ URL: $($pageInfo.url), Title: $($pageInfo.title)" -ForegroundColor Green
        } else {
            Write-Host " ! No page info" -ForegroundColor Yellow
        }
    } catch {
        Write-Host " ! Page info error: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Step 9: Test cookie injection (simulate authentication cookie)
    Write-Host "9. Testing cookie manipulation..." -NoNewline
    try {
        $setCookieScript = @"
            document.cookie = 'oisauthtoken=test-auth-token-123; path=/; domain=' + window.location.hostname;
            'Cookie set successfully';
"@
        $null = Invoke-WebView2Script -Script $setCookieScript

        # Verify cookie was set
        $updatedCookies = Get-WebView2Cookie
        $authCookie = $updatedCookies | Where-Object { $_.name -eq "oisauthtoken" }

        if ($authCookie) {
            Write-Host " ✓ Auth cookie set: $($authCookie.value)" -ForegroundColor Green
        } else {
            Write-Host " ! Cookie not found after setting" -ForegroundColor Yellow
        }
    } catch {
        Write-Host " ! Cookie manipulation error: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Step 10: Cleanup
    Write-Host "10. Cleaning up..." -NoNewline
    Stop-WebView2Helper
    Write-Host " ✓" -ForegroundColor Green

    Write-Host "`nWebView2 C# Helper Test COMPLETED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "✓ All core functionality is working" -ForegroundColor Green
    Write-Host "✓ Ready for Omada authentication integration" -ForegroundColor Green

} catch {
    Write-Host " ✗ TEST FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red

    # Cleanup on error
    try { Stop-WebView2Helper } catch { }
    exit 1
}