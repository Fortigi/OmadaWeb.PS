# Test the fixed WebView2 headless implementation
param()

Write-Host "Testing Fixed WebView2 Headless Implementation..." -ForegroundColor Yellow

try {
    # Dot-source required functions
    . ".\OmadaWeb.PS\Private\Install-WebView2.ps1"
    . ".\OmadaWeb.PS\Private\Initialize-WebView2Assemblies.ps1"
    . ".\OmadaWeb.PS\Private\Start-WebView2Headless-Fixed.ps1"
    . ".\OmadaWeb.PS\Private\Close-WebView2.ps1"

    Write-Host "1. Initializing assemblies..." -NoNewline
    $result = Initialize-WebView2Assemblies
    if ($result) {
        Write-Host " ✓" -ForegroundColor Green
    } else {
        Write-Host " ✗" -ForegroundColor Red
        exit 1
    }

    Write-Host "2. Creating headless WebView2..." -NoNewline
    $Script:WebViewCore = Start-WebView2Headless -Verbose
    if ($Script:WebViewCore) {
        Write-Host " ✓" -ForegroundColor Green

        Write-Host "3. Testing navigation..." -NoNewline
        $Script:WebViewCore.Navigate("https://www.microsoft.com")
        Start-Sleep -Seconds 3
        Write-Host " ✓" -ForegroundColor Green

        Write-Host "4. Getting page title..." -NoNewline
        Start-Sleep -Seconds 2
        $title = $Script:WebViewCore.DocumentTitle
        if ($title) {
            Write-Host " ✓ Title: $title" -ForegroundColor Green
        } else {
            Write-Host " ! No title yet" -ForegroundColor Yellow
        }

        Write-Host "5. Cleaning up..." -NoNewline
        Close-WebView2
        Write-Host " ✓" -ForegroundColor Green

    } else {
        Write-Host " ✗" -ForegroundColor Red
        exit 1
    }

    Write-Host "Fixed WebView2 test completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host " ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    Close-WebView2
    exit 1
}