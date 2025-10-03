# Simple WebView2 test with timeout handling
param()

# Import the module
Import-Module ".\OmadaWeb.PS\OmadaWeb.PS.psm1" -Force

# Dot-source required functions
. ".\OmadaWeb.PS\Private\Install-WebView2.ps1"
. ".\OmadaWeb.PS\Private\Initialize-WebView2Assemblies.ps1"
. ".\OmadaWeb.PS\Private\Close-WebView2.ps1"

Write-Host "Simple WebView2 Test with Timeout Handling..." -ForegroundColor Yellow

# Test 1: Assembly initialization with timeout
Write-Host "1. Testing assembly initialization..." -NoNewline
try {
    $timeoutSeconds = 30
    $job = Start-Job -ScriptBlock {
        param($ModulePath)
        Import-Module $ModulePath -Force
        . "$ModulePath\Private\Install-WebView2.ps1"
        . "$ModulePath\Private\Initialize-WebView2Assemblies.ps1"
        Initialize-WebView2Assemblies -Verbose
    } -ArgumentList (Get-Item ".\OmadaWeb.PS\OmadaWeb.PS.psm1").FullName

    $result = Wait-Job $job -Timeout $timeoutSeconds
    if ($result) {
        $output = Receive-Job $job
        Remove-Job $job
        if ($output) {
            Write-Host " ✓ PASSED" -ForegroundColor Green
        } else {
            Write-Host " ✗ FAILED - No output" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host " ✗ TIMEOUT - Assembly initialization took too long" -ForegroundColor Red
        Remove-Job $job -Force
        exit 1
    }
}
catch {
    Write-Host " ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 2: Basic WebView2 environment creation with timeout
Write-Host "2. Testing WebView2 environment creation..." -NoNewline
try {
    $timeoutSeconds = 30
    $job = Start-Job -ScriptBlock {
        param($ModulePath)
        Import-Module $ModulePath -Force
        . "$ModulePath\Private\Install-WebView2.ps1"
        . "$ModulePath\Private\Initialize-WebView2Assemblies.ps1"

        # Initialize assemblies
        $init = Initialize-WebView2Assemblies
        if (-not $init) {
            throw "Assembly initialization failed"
        }

        # Try to create environment with timeout
        $userDataFolder = Join-Path $env:TEMP "OmadaWeb.PS\WebView2Test\$(Get-Random)"
        New-Item -Path $userDataFolder -ItemType Directory -Force | Out-Null

        try {
            $createTask = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $userDataFolder)

            # Wait for completion with a reasonable timeout
            $completed = $createTask.Wait(15000) # 15 seconds
            if ($completed) {
                $null = $createTask.Result  # Just verify it worked
                return $true
            } else {
                throw "Environment creation timed out"
            }
        }
        catch {
            throw "Environment creation failed: $($_.Exception.Message)"
        }
    } -ArgumentList (Get-Item ".\OmadaWeb.PS\OmadaWeb.PS.psm1").FullName

    $result = Wait-Job $job -Timeout $timeoutSeconds
    if ($result) {
        $output = Receive-Job $job
        $jobErrors = Receive-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job

        if ($jobErrors) {
            Write-Host " ✗ FAILED: $jobErrors" -ForegroundColor Red
            exit 1
        } elseif ($output) {
            Write-Host " ✓ PASSED" -ForegroundColor Green
        } else {
            Write-Host " ✗ FAILED - No output" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host " ✗ TIMEOUT - Environment creation took too long" -ForegroundColor Red
        Remove-Job $job -Force
        exit 1
    }
}
catch {
    Write-Host " ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Basic WebView2 tests passed!" -ForegroundColor Green