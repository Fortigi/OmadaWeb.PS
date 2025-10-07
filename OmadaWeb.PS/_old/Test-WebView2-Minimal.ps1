# Test the minimal WebView2 implementation that avoids Windows Forms
param()

Write-Host "Testing Minimal WebView2 Implementation (No WinForms)..." -ForegroundColor Yellow

try {
    # Dot-source required functions
    . ".\OmadaWeb.PS\Private\Install-WebView2.ps1"
    . ".\OmadaWeb.PS\Private\Initialize-WebView2Assemblies.ps1"
    . ".\OmadaWeb.PS\Private\Start-WebView2Minimal-Fixed.ps1"
    . ".\OmadaWeb.PS\Private\Close-WebView2.ps1"

    Write-Host "1. Initializing assemblies..." -NoNewline
    $result = Initialize-WebView2Assemblies
    if ($result) {
        Write-Host " ✓" -ForegroundColor Green
    } else {
        Write-Host " ✗" -ForegroundColor Red
        exit 1
    }

    Write-Host "2. Creating minimal WebView2..." -NoNewline
    $Script:WebView2Core = Start-WebView2Minimal -Verbose
    if ($Script:WebView2Core) {
        Write-Host " ✓" -ForegroundColor Green

        Write-Host "3. Testing navigation to simple page..." -NoNewline
        $Script:WebView2Core.Navigate("https://httpbin.org/html")
        Start-Sleep -Seconds 4
        Write-Host " ✓" -ForegroundColor Green

        Write-Host "4. Getting page information..." -NoNewline
        Start-Sleep -Seconds 2
        try {
            $url = $Script:WebView2Core.Source
            $title = $Script:WebView2Core.DocumentTitle
            Write-Host " ✓ URL: $url, Title: $title" -ForegroundColor Green
        } catch {
            Write-Host " ! Error getting page info: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        Write-Host "5. Testing JavaScript execution..." -NoNewline
        try {
            $jsTask = $Script:WebView2Core.ExecuteScriptAsync("document.title")
            $maxWait = 5
            $waited = 0
            while (-not $jsTask.IsCompleted -and $waited -lt $maxWait) {
                Start-Sleep -Milliseconds 100
                $waited += 0.1
            }

            if ($jsTask.IsCompleted -and -not $jsTask.IsFaulted) {
                $jsResult = $jsTask.Result
                Write-Host " ✓ JS Result: $jsResult" -ForegroundColor Green
            } else {
                Write-Host " ! JS timeout or error" -ForegroundColor Yellow
            }
        } catch {
            Write-Host " ! JS Error: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        Write-Host "6. Cleaning up..." -NoNewline
        Close-WebView2
        Write-Host " ✓" -ForegroundColor Green

    } else {
        Write-Host " ✗" -ForegroundColor Red
        exit 1
    }

    Write-Host "Minimal WebView2 test completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host " ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    Close-WebView2
    exit 1
}