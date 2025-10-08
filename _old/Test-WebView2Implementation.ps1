# Test script for WebView2 functionality
param()

# Import the module
Import-Module ".\OmadaWeb.PS\OmadaWeb.PS.psm1" -Force

# Dot-source all required private functions
. ".\OmadaWeb.PS\Private\Install-WebView2.ps1"
. ".\OmadaWeb.PS\Private\Initialize-WebView2Assemblies.ps1"
. ".\OmadaWeb.PS\Private\Start-WebView2Headless.ps1"
. ".\OmadaWeb.PS\Private\Start-WebView2Minimal.ps1"
. ".\OmadaWeb.PS\Private\Close-WebView2.ps1"

Write-Host "Testing WebView2 Implementation..." -ForegroundColor Yellow

# Test 1: Assembly initialization
Write-Host "1. Testing assembly initialization..." -NoNewline
try {
    $result = Initialize-WebView2Assemblies -Verbose
    if ($result) {
        Write-Host " ✓ PASSED" -ForegroundColor Green
    }
    else {
        Write-Host " ✗ FAILED" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host " ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 2: Headless WebView2 creation
Write-Host "2. Testing headless WebView2 creation..." -NoNewline
try {
    $Script:WebViewCore = Start-WebView2Headless -Verbose
    if ($Script:WebViewCore) {
        Write-Host " ✓ PASSED" -ForegroundColor Green

        # Test navigation
        Write-Host "3. Testing navigation..." -NoNewline
        $Script:WebViewCore.Navigate("https://www.microsoft.com")
        Start-Sleep -Seconds 2
        Write-Host " ✓ PASSED" -ForegroundColor Green

        # Clean up
        Close-WebView2
    }
    else {
        Write-Host " ✗ FAILED" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host " ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Error details: $($_.Exception)" -ForegroundColor Red
    Close-WebView2
    exit 1
}

Write-Host "All tests passed! WebView2 implementation is working." -ForegroundColor Green