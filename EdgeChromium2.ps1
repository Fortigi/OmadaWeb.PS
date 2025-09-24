<#!
Omada WebView2 Cookie Grabber — Native PowerShell (no C#)
Fixed: Removed reference to ContextMenus (System.Windows.Forms.ContextMenu conflict). Now uses property assignment safely.
#>

param(
  [string]$StartUrl = 'https://omada.omada.cloud/',
  [string]$DomainFilter = 'omada.omada.cloud'
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Find-WebView2Assemblies {
  # Prefer assemblies that match the current runtime to avoid System.Windows.Forms type load issues
  $base = Join-Path $env:USERPROFILE '.nuget\packages\microsoft.web.webview2'
  if (-not (Test-Path $base)) { return $null }
  $candidates = Get-ChildItem -Path $base -Recurse -Include 'Microsoft.Web.WebView2.WinForms.dll' -ErrorAction SilentlyContinue
  $candidates = Get-Item "C:\Users\mark\Desktop\webviewtest\Microsoft.Web.WebView2.WinForms.dll"
  if (-not $candidates) { return $null }

  # Determine preferred TFMs by current host
  $isPS5 = ($PSVersionTable.PSEdition -eq 'Desktop')
  $preferred = @()
  if ($isPS5) {
    $preferred = @('lib\net48', 'lib\net472', 'lib\net462', '.')
  }
  else {
    # PS7+ — try to match .NET version; prioritize net8, then net7, net6, net5, then netcoreapp3.0
    $preferred = @('lib\net8.0-windows', 'lib\net7.0-windows', 'lib\net6.0-windows', 'lib\net5.0-windows', 'lib\netcoreapp3.0', '.')
  }
  # Fallback search order if exact folders aren’t present
  $fallback = @('lib_manual\net8.0-windows', 'lib_manual\net7.0-windows', 'lib_manual\net5.0-windows10.0.17763.0', 'lib\net5.0-windows10.0.17763.0', 'lib\net45', 'lib\net461', 'lib\net462', '.')

  $ordered = @()
  foreach ($p in $preferred + $fallback) {
    $ordered += $candidates | Where-Object { $_.FullName -like "*${p}*" }
  }
  if (-not $ordered) { $ordered = $candidates }

  foreach ($wf in $ordered) {
    #$corePeer = Join-Path $wf.DirectoryName 'Microsoft.Web.WebView2.Core.dll'
    $corePeer = Join-Path "C:\Users\mark\Desktop\webviewtest" 'Microsoft.Web.WebView2.Core.dll'
    if (Test-Path $corePeer) { return [pscustomobject]@{ WinForms = $wf.FullName; Core = $corePeer } }
  }
  return $null
}

$wv2 = Find-WebView2Assemblies
if (-not $wv2) { throw "WebView2 assemblies not found" }

[void][Reflection.Assembly]::LoadFrom($wv2.Core)
[void][Reflection.Assembly]::LoadFrom($wv2.WinForms)

$WebView2Type = [Microsoft.Web.WebView2.WinForms.WebView2]

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Omada Cookie Grabber (WebView2, PowerShell)'
$form.Width = 1100
$form.Height = 800
$form.StartPosition = 'CenterScreen'

$panel = New-Object System.Windows.Forms.Panel
$panel.Dock = 'Top'
$panel.Height = 44

$lblUrl = New-Object System.Windows.Forms.Label
$lblUrl.Text = 'URL:'
$lblUrl.AutoSize = $true
$lblUrl.Top = 14
$lblUrl.Left = 8

$txtUrl = New-Object System.Windows.Forms.TextBox
$txtUrl.Text = $StartUrl
$txtUrl.Left = 45
$txtUrl.Top = 40
$txtUrl.Width = 200
$txtUrl.AutoSize = $false
$txtUrl.Anchor = 'Top, Left'

$lblDom = New-Object System.Windows.Forms.Label
$lblDom.Text = 'Domain filter:'
$lblDom.AutoSize = $true
$lblDom.Top = 14
$lblDom.Left = 635

$txtDom = New-Object System.Windows.Forms.TextBox
$txtDom.Text = $DomainFilter
$txtDom.Left = 720
$txtDom.Top = 10
$txtDom.Width = 200
$txtDom.Anchor = 'Top, Left'

$btnGo = New-Object System.Windows.Forms.Button
$btnGo.Text = 'Go'
$btnGo.Left = 925
$btnGo.Top = 8
$btnGo.Width = 60
$btnGo.Anchor = 'Top, Left'

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = 'Export Cookies'
$btnExport.Left = 990
$btnExport.Top = 8
$btnExport.Width = 120
$btnExport.Anchor = 'Top, Left'

$panel.Controls.AddRange([System.Windows.Forms.Control[]] @($lblUrl, $txtUrl, $lblDom, $txtDom, $btnGo, $btnExport))

$wv = New-Object Microsoft.Web.WebView2.WinForms.WebView2
$wv.Dock = 'Fill'

$status = New-Object System.Windows.Forms.StatusStrip
$lblStatus = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblStatus.Text = 'Ready.'
$status.Items.Add($lblStatus) | Out-Null

$form.Controls.Add($wv)
$form.Controls.Add($panel)
$form.Controls.Add($status)

function Initialize-WebView2 {
  param([Microsoft.Web.WebView2.WinForms.WebView2]$Control, [scriptblock]$OnReady)

  if ($Control.CoreWebView2 -ne $null) { & $OnReady; return }
  $userDataFolder = Join-Path $env:TEMP 'OmadaWebView2Profile'
  if (-not (Test-Path $userDataFolder)) { New-Item -ItemType Directory -Force -Path $userDataFolder | Out-Null }
  # Use CreationProperties to set UserDataFolder before async init (best practice for WinForms)
  $props = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
  $props.UserDataFolder = $userDataFolder
  $Control.CreationProperties = $props
  $Control.add_CoreWebView2InitializationCompleted({
      param($sender, $e)
      if ($e.IsSuccess) {
        # $Control.CoreWebView2.Settings.IsStatusBarEnabled = $true
        # $Control.CoreWebView2.Settings.AreDevToolsEnabled = $true
        # $Control.CoreWebView2.Settings.AreDefaultContextMenusEnabled = $true
        # [Microsoft.Web.WebView2.Core.CoreWebView2Settings]$Settings = $Control.CoreWebView2.Settings
        # $Settings.AreDefaultContextMenusEnabled  = $true
        # $Settings.AreDefaultScriptDialogsEnabled = $true
        # $Settings.AreDevToolsEnabled             = $FALSE
        # $Settings.AreHostObjectsAllowed          = $FALSE
        # $Settings.IsBuiltInErrorPageEnabled      = $FALSE
        # $Settings.IsScriptEnabled                = $TRUE
        # $Settings.IsStatusBarEnabled             = $true
        # $Settings.IsWebMessageEnabled            = $TRUE
        # $Settings.IsZoomControlEnabled           = $FALSE
        if ($OnReady) { & $OnReady }
      }
      else {
        [System.Windows.Forms.MessageBox]::Show("WebView2 init failed: $($e.InitializationException.Message)")
      }
    })
  $null = $Control.EnsureCoreWebView2Async()
}

function Set-Status { param([string]$t) $lblStatus.Text = $t }

$btnGo.Add_Click({
    Initialize-WebView2 -Control $wv -OnReady {
      $uriText = $txtUrl.Text.Trim()
      if (-not [Uri]::IsWellFormedUriString($uriText, [UriKind]::Absolute)) { [System.Windows.Forms.MessageBox]::Show('Invalid URL'); return }
      $wv.Source = [Uri]$uriText
      Set-Status "Navigating to $uriText ..."
    }
  })

function Invoke-ExecuteScriptAsync {
  [CmdLetBinding()]
  param(
    $ScriptToExecute  ,
    $OnCompletedScriptBlock
  )
  try {
    #$Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName), $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
    #if ($null -ne $Script:Webview.Object) {
    #if ($Script:Webview.Object.IsLoaded) {

    $Script:Task = $wv.CoreWebView2.CookieManager.GetCookiesAsync($null)
    $Script:Task.GetAwaiter().OnCompleted({
        if ($Script:Task.IsFaulted) {
          #$timer.Stop()
          $msg = $Script:Task.Exception.InnerException?.Message
          if (-not $msg) { $msg = $Script:Task.Exception.ToString() }
          [System.Windows.Forms.MessageBox]::Show($msg, 'Cookie retrieval failed')
          Set-Status 'Error'
          $btnExport.Enabled = $true
        }
        elseif ($Script:Task.IsCanceled) {
          #$timer.Stop()
          Set-Status 'Canceled'
          $btnExport.Enabled = $true
        }
        elseif ($Script:Task.IsCompleted) {
          #$timer.Stop()
          $cookies = $Script:Task.Result

          $filter = ($txtDom.Text.Trim()).ToLowerInvariant()
          $match = $cookies | Where-Object { ($_.Domain) -and $_.Domain.ToLowerInvariant().EndsWith($filter) }
          if (-not $match -or $match.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No cookies for '*.$filter' found.")
            Set-Status 'No matching cookies'
            $btnExport.Enabled = $true
            return
          }

          $outDir = Split-Path -Parent $PSCommandPath; if (-not $outDir) { $outDir = (Get-Location).Path }
          $cookiesPath = Join-Path $outDir 'cookies.json'
          $headerPath = Join-Path $outDir 'cookie-header.txt'

          $cookieHeader = ($match | ForEach-Object { "{0}={1}" -f $_.Name, $_.Value }) -join '; '
          $json = $match | ForEach-Object {
            #$exp = $null; if ($_.Expires -gt 0) { $exp = [DateTimeOffset]::FromUnixTimeSeconds([long]$_.Expires).ToString('o') }
            $exp = $_.Expires
            [pscustomobject]@{
              name = $_.Name; value = $_.Value; domain = $_.Domain; path = $_.Path; expires = $exp
              httpOnly = $_.IsHttpOnly; secure = $_.IsSecure; sameSite = $_.SameSite.ToString()
            }
          }

          $json | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $cookiesPath
          $cookieHeader | Set-Content -Encoding UTF8 $headerPath
          Set-Status "Exported $($match.Count) cookies -> $cookiesPath, $headerPath"
          $btnExport.Enabled = $true
        }
      }

				)
    #}
    #else {
    #Write-LogOutput -Message "WebView2 is not loaded yet." -LogType DEBUG
    #}
    #}
    #else {
    #    #Write-LogOutput -Message "WebView2 is not initialized." -LogType ERROR
    #}
  }
  catch {
    $_.Exception.Message | Write-LogOutput -LogType ERROR
  }
}

$btnExport.Add_Click({
    Initialize-WebView2 -Control $wv -OnReady {
      try {
        $btnExport.Enabled = $false
        Set-Status 'Collecting cookies…'
        Wait-Debugger
        Invoke-ExecuteScriptAsync
        # Start async cookie retrieval without blocking the UI thread
        # $task  = $wv.CoreWebView2.CookieManager.GetCookiesAsync($null)
        # $awaiter=$task.GetAwaiter()
        # $timer = New-Object System.Windows.Forms.Timer
        # $timer.Interval = 150
        # $timer.Add_Tick({
        # try {
        # if ($awaiter.IsFaulted) {
        # $timer.Stop()
        # $msg = $awaiter.Exception.InnerException?.Message
        # if (-not $msg) { $msg = $awaiter.Exception.ToString() }
        # [System.Windows.Forms.MessageBox]::Show($msg, 'Cookie retrieval failed')
        # Set-Status 'Error'
        # $btnExport.Enabled = $true
        # } elseif ($awaiter.IsCanceled) {
        # $timer.Stop()
        # Set-Status 'Canceled'
        # $btnExport.Enabled = $true
        # } elseif ($awaiter.IsCompleted) {
        # $timer.Stop()
        # $cookies = $awaiter.Result

        # $filter = ($txtDom.Text.Trim()).ToLowerInvariant()
        # $match = $cookies | Where-Object { ($_.Domain) -and $_.Domain.ToLowerInvariant().EndsWith($filter) }
        # if (-not $match -or $match.Count -eq 0) {
        # [System.Windows.Forms.MessageBox]::Show("No cookies for '*.$filter' found.")
        # Set-Status 'No matching cookies'
        # $btnExport.Enabled = $true
        # return
        # }

        # $outDir = Split-Path -Parent $PSCommandPath; if (-not $outDir) { $outDir = (Get-Location).Path }
        # $cookiesPath = Join-Path $outDir 'cookies.json'
        # $headerPath  = Join-Path $outDir 'cookie-header.txt'

        # $cookieHeader = ($match | ForEach-Object { "{0}={1}" -f $_.Name, $_.Value }) -join '; '
        # $json = $match | ForEach-Object {
        # $exp = $null; if ($_.Expires -gt 0) { $exp = [DateTimeOffset]::FromUnixTimeSeconds([long]$_.Expires).ToString('o') }
        # [pscustomobject]@{
        # name=$_.Name; value=$_.Value; domain=$_.Domain; path=$_.Path; expires=$exp;
        # httpOnly=$_.IsHttpOnly; secure=$_.IsSecure; sameSite=$_.SameSite.ToString()
        # }
        # }

        # $json | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $cookiesPath
        # $cookieHeader | Set-Content -Encoding UTF8 $headerPath
        # Set-Status "Exported $($match.Count) cookies -> $cookiesPath, $headerPath"
        # $btnExport.Enabled = $true
        # }
        # } catch {
        # $timer.Stop()
        # [System.Windows.Forms.MessageBox]::Show($_.ToString(), 'Export error')
        # Set-Status 'Export failed'
        # $btnExport.Enabled = $true
        # }
        # })
        # $timer.Start()

      }
      catch {
        [System.Windows.Forms.MessageBox]::Show($_.ToString(), 'Start async error')
        $btnExport.Enabled = $true
        Set-Status 'Error'
      }
    }
  })

$form.Add_Shown({
    Initialize-WebView2 -Control $wv -OnReady {
      $uriText = $txtUrl.Text.Trim()
      if ([string]::IsNullOrWhiteSpace($uriText)) { $uriText = $StartUrl }
      if (-not [Uri]::IsWellFormedUriString($uriText, [UriKind]::Absolute)) { return }
      $wv.Source = [Uri]$uriText
      Set-Status "Navigating to $uriText ..."
    }
  })
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
c