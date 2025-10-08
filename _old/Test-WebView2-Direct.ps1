# Direct WebView2 test without jobs
param()

Write-Host "Direct WebView2 Test..." -ForegroundColor Yellow

# Test 1: Assembly initialization
Write-Host "1. Testing assembly initialization..." -NoNewline
try {
    # Dot-source required functions
    . ".\OmadaWeb.PS\Private\Install-WebView2.ps1"
    . ".\OmadaWeb.PS\Private\Initialize-WebView2Assemblies.ps1"

    $result = Initialize-WebView2Assemblies -Verbose
    if ($result) {
        Write-Host " ✓ PASSED" -ForegroundColor Green
    } else {
        Write-Host " ✗ FAILED - Function returned false" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host " ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}

# Test 2: Basic WebView2 environment creation
Write-Host "2. Testing WebView2 environment creation..." -NoNewline
try {
    $userDataFolder = Join-Path $env:TEMP "OmadaWeb.PS\WebView2Test\$(Get-Random)"
    New-Item -Path $userDataFolder -ItemType Directory -Force | Out-Null

    # Test with a very short timeout first
    Write-Host "(creating environment)..." -NoNewline -ForegroundColor Gray

    $createTask = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $userDataFolder)

    # Use a shorter timeout to see if it's hanging
    $completed = $createTask.Wait(5000) # 5 seconds
    if ($completed) {
        $environment = $createTask.Result
        Write-Host " ✓ PASSED" -ForegroundColor Green

        # Try to create a controller quickly
        Write-Host "3. Testing controller creation..." -NoNewline

        # Create minimal form for HWND
        Add-Type -AssemblyName System.Windows.Forms
        $form = New-Object System.Windows.Forms.Form
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
        $form.ShowInTaskbar = $false
        $form.Size = New-Object System.Drawing.Size(1, 1)
        $hwnd = $form.Handle

        $controllerTask = $environment.CreateCoreWebView2ControllerAsync($hwnd)
        $controllerCompleted = $controllerTask.Wait(5000) # 5 seconds

        if ($controllerCompleted) {
            Write-Host " ✓ PASSED" -ForegroundColor Green
            $controller = $controllerTask.Result
            $controller.Close()
        } else {
            Write-Host " ✗ TIMEOUT" -ForegroundColor Yellow
        }

        $form.Dispose()

    } else {
        Write-Host " ✗ TIMEOUT" -ForegroundColor Yellow
        Write-Host "Environment creation is hanging - this suggests WebView2 runtime issues" -ForegroundColor Yellow
    }
}
catch {
    Write-Host " ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
}

Write-Host "Test completed." -ForegroundColor Green