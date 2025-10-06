function Test-WebView2Functionality {
    <#
    .SYNOPSIS
    Tests basic WebView2 functionality without requiring full authentication.

    .DESCRIPTION
    This function performs a basic test of WebView2 initialization and cleanup
    to verify that the implementation works correctly.

    .EXAMPLE
    Test-WebView2Functionality
    #>

    [CmdletBinding()]
    param()

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        Write-Host "Testing WebView2 functionality..." -ForegroundColor Yellow

        # Test 1: Assembly initialization
        Write-Host "1. Testing assembly initialization..." -NoNewline
        if (Initialize-WebView2Assemblies) {
            Write-Host " ✓ PASSED" -ForegroundColor Green
        }
        else {
            Write-Host " ✗ FAILED" -ForegroundColor Red
            return $false
        }

        # Test 2: WebView2 installation check
        Write-Host "2. Testing WebView2 installation..." -NoNewline
        if (Install-WebView2) {
            Write-Host " ✓ PASSED" -ForegroundColor Green
        }
        else {
            Write-Host " ✗ FAILED" -ForegroundColor Red
            return $false
        }

        # Test 3: Simple WebView2 control creation (without showing UI)
        Write-Host "3. Testing WebView2 control creation..." -NoNewline
        try {
            # Create environment
            $userDataFolder = Join-Path $env:TEMP "OmadaWeb.PS\WebView2Test"
            New-Item -Path $userDataFolder -ItemType Directory -Force | Out-Null

            $environmentOptions = New-Object Microsoft.Web.WebView2.Core.CoreWebView2EnvironmentOptions
            $environment = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $userDataFolder, $environmentOptions).GetAwaiter().GetResult()

            # Create control (but don't show it)
            $webView2Control = New-Object Microsoft.Web.WebView2.WinForms.WebView2

            # Initialize (this is the critical test)
            $webView2Control.EnsureCoreWebView2Async($environment).GetAwaiter().GetResult()

            # Clean up
            $webView2Control.Dispose()
            $environment.Dispose()

            # Clean up temp folder
            Remove-Item -Path $userDataFolder -Recurse -Force -ErrorAction SilentlyContinue

            Write-Host " ✓ PASSED" -ForegroundColor Green
        }
        catch {
            Write-Host " ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }

        Write-Host "All WebView2 functionality tests passed! ✓" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "WebView2 functionality test failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}