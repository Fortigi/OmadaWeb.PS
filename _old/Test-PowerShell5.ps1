# Simple test for Windows PowerShell compatibility
param()

Write-Host "Testing WebView2 in Windows PowerShell..." -ForegroundColor Yellow

try {
    # Load functions
    . ".\OmadaWeb.PS\Private\Install-WebView2.ps1"
    . ".\OmadaWeb.PS\Private\Initialize-WebView2Assemblies.ps1"

    Write-Host "1. Initializing assemblies..." -NoNewline
    $result = Initialize-WebView2Assemblies
    if ($result) {
        Write-Host " PASS" -ForegroundColor Green
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        exit 1
    }

    Write-Host "2. Creating environment..." -NoNewline
    $userDataFolder = Join-Path $env:TEMP "WebView2Test\$(Get-Random)"
    New-Item -Path $userDataFolder -ItemType Directory -Force | Out-Null

    $environmentTask = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $userDataFolder)

    # Wait for environment
    $waited = 0
    while (-not $environmentTask.IsCompleted -and $waited -lt 10) {
        Start-Sleep -Milliseconds 500
        $waited += 0.5
    }

    if ($environmentTask.IsCompleted -and -not $environmentTask.IsFaulted) {
        $environment = $environmentTask.Result
        Write-Host " PASS" -ForegroundColor Green
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        exit 1
    }

    Write-Host "3. Testing controller with desktop window..." -NoNewline

    # Simple desktop window approach
    Add-Type @'
        using System;
        using System.Runtime.InteropServices;
        public class Win32 {
            [DllImport("user32.dll")]
            public static extern IntPtr GetDesktopWindow();
        }
'@

    $hwnd = [Win32]::GetDesktopWindow()
    $controllerTask = $environment.CreateCoreWebView2ControllerAsync($hwnd)

    # Wait for controller with timeout
    $waited = 0
    while (-not $controllerTask.IsCompleted -and $waited -lt 10) {
        Start-Sleep -Milliseconds 500
        $waited += 0.5
    }

    if ($controllerTask.IsCompleted -and -not $controllerTask.IsFaulted) {
        $controller = $controllerTask.Result
        Write-Host " PASS" -ForegroundColor Green

        # Quick test
        $Script:WebView2 = $controller.CoreWebView2
        $Script:WebView2.Navigate("about:blank")

        Write-Host "4. WebView2 ready for use!" -ForegroundColor Green

        # Cleanup
        $controller.Close()
    } else {
        Write-Host " FAIL - Controller creation timed out" -ForegroundColor Red
        if ($controllerTask.IsFaulted) {
            Write-Host "Error: $($controllerTask.Exception.InnerException.Message)" -ForegroundColor Red
        }
    }

} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}