# OmadaWebView2Helper

A C# helper application that provides reliable WebView2 functionality for the OmadaWeb.PS PowerShell module.

## Purpose

This helper application solves the WebView2 controller creation timeout issues that occur in PowerShell environments by providing:

- Proper STA (Single Thread Apartment) threading for WebView2
- Reliable async/await pattern handling
- Windows message pump processing
- JSON-based communication with PowerShell

## Architecture

```
PowerShell Module (OmadaWeb.PS)
    ↓ JSON Commands via stdin/stdout
OmadaWebView2Helper.exe (C# Application)
    ↓ WebView2 APIs
Microsoft Edge WebView2 Runtime
```

## Commands Supported

- `initialize`: Create WebView2 environment and controller
- `navigate`: Navigate to URL
- `waitfornavigation`: Wait for navigation completion
- `executescript`: Execute JavaScript
- `getcookies`: Extract cookies from current page
- `getpageinfo`: Get page URL, title, and navigation state
- `close`: Clean up WebView2 resources

## Communication Protocol

All communication uses JSON messages over stdin/stdout:

### Command Format
```json
{
  "action": "navigate",
  "parameters": {
    "url": "https://example.com"
  }
}
```

### Response Format
```json
{
  "success": true,
  "error": null,
  "data": {
    "navigated": true,
    "url": "https://example.com"
  }
}
```

## Building

```bash
dotnet build --configuration Release
```

## Usage

This application is designed to be called by the PowerShell module and should not be run directly by users.