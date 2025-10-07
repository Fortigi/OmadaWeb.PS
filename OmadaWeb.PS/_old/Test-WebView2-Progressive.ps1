# Test with aggressive timeout and progress reporting
param()

Write-Host "Testing WebView2 with Progress Reporting..." -ForegroundColor Yellow

try {
    # Dot-source required functions
    . ".\OmadaWeb.PS\Private\Install-WebView2.ps1"
    . ".\OmadaWeb.PS\Private\Initialize-WebView2Assemblies.ps1"
    . ".\OmadaWeb.PS\Private\Close-WebView2.ps1"

    Write-Host "1. Initializing assemblies..." -NoNewline
    $result = Initialize-WebView2Assemblies
    if ($result) {
        Write-Host " ✓" -ForegroundColor Green
    } else {
        Write-Host " ✗" -ForegroundColor Red
        exit 1
    }

    Write-Host "2. Creating WebView2 environment..." -NoNewline
    $userDataFolder = Join-Path $env:TEMP "OmadaWeb.PS\WebView2Test\$(Get-Random)"
    New-Item -Path $userDataFolder -ItemType Directory -Force | Out-Null

    $environmentTask = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $userDataFolder)

    $maxWait = 10 # seconds
    $waited = 0
    while (-not $environmentTask.IsCompleted -and $waited -lt $maxWait) {
        Write-Host "." -NoNewline -ForegroundColor Gray
        Start-Sleep -Milliseconds 500
        $waited += 0.5
    }

    if ($environmentTask.IsCompleted) {
        if ($environmentTask.IsFaulted) {
            Write-Host " ✗ Environment creation failed: $($environmentTask.Exception.InnerException.Message)" -ForegroundColor Red
            exit 1
        }
        $environment = $environmentTask.Result
        Write-Host " ✓" -ForegroundColor Green
    } else {
        Write-Host " ✗ Environment creation timed out" -ForegroundColor Red
        exit 1
    }

    Write-Host "3. Creating message window..." -NoNewline

    # Create a simplified message window
    Add-Type -TypeDefinition @'
        using System;
        using System.Runtime.InteropServices;

        public class SimpleWindow {
            [DllImport("user32.dll")]
            public static extern IntPtr GetDesktopWindow();
        }
'@

    # Use desktop window as parent - this is simpler and more reliable
    $desktopWindow = [SimpleWindow]::GetDesktopWindow()
    Write-Host (" ✓ Using desktop window: 0x{0:X}" -f $desktopWindow.ToInt64()) -ForegroundColor Green

    Write-Host "4. Creating controller (with timeout)..." -NoNewline

    $controllerTask = $environment.CreateCoreWebView2ControllerAsync($desktopWindow)

    $maxWait = 15 # seconds for controller
    $waited = 0
    while (-not $controllerTask.IsCompleted -and $waited -lt $maxWait) {
        Write-Host "." -NoNewline -ForegroundColor Gray
        Start-Sleep -Milliseconds 500
        $waited += 0.5
    }

    if ($controllerTask.IsCompleted) {
        if ($controllerTask.IsFaulted) {
            Write-Host " ✗ Controller creation failed: $($controllerTask.Exception.InnerException.Message)" -ForegroundColor Red
            Write-Host "Exception details: $($controllerTask.Exception)" -ForegroundColor Red
            exit 1
        }
        $controller = $controllerTask.Result
        $Script:WebView2Core = $controller.CoreWebView2
        Write-Host " ✓" -ForegroundColor Green

        Write-Host "5. Testing basic functionality..." -NoNewline
        try {
            $Script:WebView2Core.Navigate("about:blank")
            Start-Sleep -Seconds 1
            Write-Host " ✓" -ForegroundColor Green

            # Clean up
            $controller.Close()
        } catch {
            Write-Host " ! Error: $($_.Exception.Message)" -ForegroundColor Yellow
        }

    } else {
        Write-Host " ✗ Controller creation timed out after $maxWait seconds" -ForegroundColor Red
        Write-Host "This suggests WebView2 runtime compatibility issues" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "WebView2 test completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host " ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}