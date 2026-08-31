#Requires -Version 7.0

<#
.SYNOPSIS
    Answers one question about a machine: can it host the WebView2 window the sign-in needs?
.DESCRIPTION
    The canary rests on an assumption that is invisible until it fails: that the runner can create a
    WinForms window and initialize a CoreWebView2 inside it. If it cannot, every canary assertion
    fails at once and the diagnostic says the sign-in page was not recognized - which is true, and
    which points at exactly the wrong thing. A maintainer would go looking at Microsoft's markup while
    the real answer was that no browser ever opened.

    So this is kept separate and deliberately knows nothing about Entra ID, credentials or the module's
    sign-in flow. It opens a window, navigates to about:blank, waits for the runtime to report itself
    initialized, and closes. Green means the host is capable and any canary failure is about the
    sign-in page; red means the canary cannot run here at all.

    Run it on a new runner image before trusting a red canary, and after any change to how the
    WebView2 assemblies are bundled.
.PARAMETER ModulePath
    The built module to take the WebView2 assemblies and their resolved paths from. Defaults to the
    build output, because that is what the canary itself loads.

    Must be the .psm1 and not the .psd1: importing the manifest returns a module of type Manifest,
    whose session state holds only the three exported commands, so the private functions this needs
    are invisible from it. The PR Validation workflow imports the .psm1 for the same reason.
.PARAMETER TimeoutSeconds
    How long to wait for CoreWebView2 to report initialization before giving up.
.EXAMPLE
    ./Tests/E2E/Test-CanaryBrowserHost.ps1

    Exits 0 when the machine can host a WebView2 window, and 1 with a reason when it cannot.
#>
[CmdletBinding()]
param(
    [string]$ModulePath = (Join-Path (Split-Path (Split-Path $PSScriptRoot)) -ChildPath "buildoutput/OmadaWeb.PS/OmadaWeb.PS.psm1"),

    [ValidateRange(10, 600)]
    [int]$TimeoutSeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try {
    "Apartment state : {0}" -f [System.Threading.Thread]::CurrentThread.GetApartmentState() | Write-Host
    "Session name    : {0}" -f [System.Environment]::GetEnvironmentVariable("SESSIONNAME") | Write-Host
    "Module          : {0}" -f $ModulePath | Write-Host

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne "STA") {
        # PowerShell 7 is STA by default on Windows, so this only fires when something has gone out of
        # its way to change it - and a WinForms dialog on an MTA thread fails in ways that look like a
        # hung sign-in rather than like a configuration mistake.
        "This process is not running in a single-threaded apartment. WinForms needs STA; start PowerShell without -MTA." | Write-Error -ErrorAction "Stop"
    }

    if (-not (Test-Path $ModulePath)) {
        "The module was not found at '{0}'. Build it first with ./Build/build.ps1 -Task Build." -f $ModulePath | Write-Error -ErrorAction "Stop"
    }

    $Module = Import-Module $ModulePath -Force -PassThru -ErrorAction Stop

    # Run inside the module's own session state, which is the only place the bundled assembly paths
    # ($Script:WebView2CorePath and friends) are resolved. Reproducing that resolution here would be a
    # second implementation of it, and a smoke test that passes against a copy of the real paths is
    # not a smoke test.
    $Result = & $Module {
        param($TimeoutSeconds)

        if (-not (Install-WebView2)) {
            return [pscustomobject]@{
                Success = $false
                Reason  = "The WebView2 runtime is not available and could not be installed."
            }
        }

        Add-ReflectionAssembly -Object $Script:WebView2CorePath
        Add-ReflectionAssembly -Object $Script:WebView2WinFormsPath
        Add-ReflectionAssembly -Object "System.Drawing" -Type LoadWithPartialName
        Add-ReflectionAssembly -Object "System.Windows.Forms" -Type LoadWithPartialName

        $Outcome = [hashtable]::Synchronized(@{
                Initialized = $false
                Reason      = "The initialization event never fired."
            })

        $Form = New-Object System.Windows.Forms.Form
        try {
            $Form.Text = "OmadaWeb.PS canary browser host check"
            $Form.Width = 800
            $Form.Height = 600
            # Off-screen and unlisted: nothing here is for a human to look at, and a window that steals
            # focus on a shared machine is a nuisance.
            $Form.ShowInTaskbar = $false
            $Form.StartPosition = "Manual"
            $Form.Location = New-Object System.Drawing.Point(-4000, -4000)

            $WebView2 = New-Object Microsoft.Web.WebView2.WinForms.WebView2
            $WebView2.CreationProperties = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
            $WebView2.CreationProperties.UserDataFolder = (New-Item -ItemType Directory -Force -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("OmadaWebCanaryHostCheck_{0}" -f [guid]::NewGuid().ToString("N")))).FullName
            $WebView2.Dock = "Fill"
            $WebView2.Source = [System.Uri]::new("about:blank")

            $WebView2.add_CoreWebView2InitializationCompleted({
                    param($EventSender, $EventArgs)

                    if ($EventArgs.IsSuccess) {
                        $Outcome.Initialized = $true
                        $Outcome.Reason = ""
                    }
                    else {
                        $Outcome.Reason = "CoreWebView2 initialization failed: {0}" -f $EventArgs.InitializationException.Message
                    }

                    $EventSender.FindForm().Close()
                })

            $Form.Controls.Add($WebView2)

            # A hard stop, so a runner that can create the window but never finishes initializing the
            # runtime fails with this message instead of holding the job until the job timeout.
            $Timer = New-Object System.Windows.Forms.Timer
            $Timer.Interval = $TimeoutSeconds * 1000
            $Timer.Add_Tick({
                    $Timer.Stop()
                    $Form.Close()
                })
            $Timer.Start()

            $null = $Form.ShowDialog()
            $Timer.Stop()
            $Timer.Dispose()
        }
        finally {
            $Form.Dispose()
        }

        return [pscustomobject]@{
            Success = $Outcome.Initialized
            Reason  = $Outcome.Reason
        }
    } $TimeoutSeconds

    if ($Result.Success) {
        "This machine can host a WebView2 window. A canary failure here is about the sign-in page, not the runner." | Write-Host -ForegroundColor Green
        exit 0
    }

    "This machine cannot host a WebView2 window, so the canary cannot run on it. {0}" -f $Result.Reason | Write-Error -ErrorAction "Continue"
    exit 1
}
catch {
    "The browser host check failed: {0}" -f $_.Exception.Message | Write-Error -ErrorAction "Continue"
    exit 1
}
