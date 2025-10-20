param(
    [parameter(Mandatory = $true)]
    [ValidateSet("Start", "Stop")]
    $Action,
    [parameter(Mandatory = $false)]
    [int]$Port = 9080,
    [switch]$NoNewWindow,
    [switch]$Force
)

try {

    function KillWebServerProcess {
        param(
            [switch]$Force
        )

        "Checking for existing web server web server processes" | Write-Verbose
        if ($null -eq $Global:WebServerPid -or $Global:WebServerPid -eq 0) {
            "No existing web server processes found" | Write-Verbose
            return $true
        }
        $ProcessObject = Get-Process | Where-Object { $_.Id -eq $Global:WebServerPid }
        "ProcessObject: {0}" -f ($ProcessObject | ConvertTo-Json)
        if ($Force -and $null -ne $ProcessObject) {
            $ProcessObject | Stop-Process -ErrorAction Stop
            "Web server process (PID: {0}) stopped" -f $Global:WebServerPid | Write-Host
        }
        elseif ($null -ne $ProcessObject) {
            "Web server process (PID: {0}) cannot be stopped, use -Force to stop!" -f $Global:WebServerPid | Write-Host
        }
        else {
            "Web server process (PID: {0}) not active anymore" -f $Global:WebServerPid | Write-Host
        }
        $ProcessObject = Get-Process | Where-Object { $_.Id -eq $Global:WebServerPid }
        if ($null -eq $ProcessObject) {
            "Process killend" | Write-Verbose
            $Global:WebServerPid = $null
            return $true
        }
        else {
            "Process not killend" | Write-Verbose
            return $false
        }
    }

    $Url = "http://127.0.0.1:{0}/" -f $Port
    $TempScript = Join-Path $env:TEMP ("WebServer-{0}.ps1" -f $Port)
    switch ($Action) {
        "Start" {

            if (KillWebServerProcess -Force:$Force) {
                @'
PARAM(
    [string]$Url = "{0}"
)
try{{

    # --- Cookie config ---
    $Name       = "oisauthtoken"
    $Value      = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("test-cookie-value"))
    $Domain     = $null            # Host-only cookie (recommended for localhost/IP). Set to "localhost" if you really want Domain.
    $Path       = "/"
    $Expires    = $null #[DateTime]::UtcNow.AddHours(1)  # RFC1123 format required
    $HttpOnly   = $true
    $Secure     = $false          # For HTTP: false. For HTTPS: true + SameSite=None.
    $SameSite   = "Lax"           # For HTTP: Lax. For HTTPS: None.

    function New-SetCookieHeader {{
        param(
            [string]$Name,
            [string]$Value,
            [string]$Domain,
            [string]$Path,
            $ExpiresUtc,
            [bool]$HttpOnly,
            [bool]$Secure,
            [string]$SameSite # Lax|Strict|None
        )
        $Parts = @()
        $Parts += "$Name=$Value"
        if ($Domain) {{ $Parts += "Domain=$Domain" }}      # omit for host-only
        if ($Path) {{ $Parts += "Path=$Path" }}
        if ($ExpiresUtc) {{ $Parts += "Expires=" + $ExpiresUtc.ToString("R") }}  # GMT string
        if ($HttpOnly) {{ $Parts += "HttpOnly" }}
        if ($Secure) {{ $Parts += "Secure" }}
        if ($SameSite) {{ $Parts += "SameSite=$SameSite" }}
        ($Parts -join "; ")
    }}

    Write-Host "Url: $Url"
    $Listener = [System.Net.HttpListener]::new()
    $Listener.Prefixes.Add($Url)
    $Listener.Start()
    Write-Host "Listening on $Url - Press Ctrl+C to stop"
    while ($true) {{
        $Ctx = $Listener.GetContext()
        $Bytes = [Text.Encoding]::UTF8.GetBytes("OK")
        $SetCookie = New-SetCookieHeader -Name $Name -Value $Value -Domain $Domain -Path $Path -ExpiresUtc $Expires -HttpOnly:$HttpOnly -Secure:$Secure -SameSite $SameSite
        $Ctx.Response.Headers.Add("Set-Cookie", $SetCookie)
        $Ctx.Response.StatusCode = 200
        $Ctx.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
        $Ctx.Response.Close()
        }}
}}
catch{{
    Throw
}}
'@ -f $Url | Out-File $TempScript -Force -Encoding UTF8

                "Script contents:`n{0}" -f (Get-Content $TempScript) | Write-Verbose

                $Arguments = "-NoLogo -NoProfile -ExecutionPolicy Unrestricted -File `"$TempScript`""
                "Starting web server process: {0} {1}" -f (Get-Command pwsh.exe).Source, $Arguments | Write-Verbose
                $Global:WebServerPid = (Start-Process (Get-Command pwsh.exe).Source -ArgumentList $Arguments -PassThru -NoNewWindow:$NoNewWindow.IsPresent).Id
                "Process started with PID: {0}" -f $Global:WebServerPid | Write-Verbose

                1..30 | ForEach-Object {
                    try {
                        "Test web server processes" | Write-Verbose
                        if ($Null -eq $Result) {
                            $Result = Invoke-WebRequest $Url  -UseBasicParsing -TimeoutSec 1
                        }

                    }
                    catch {
                        Start-Sleep 1
                    }
                }
                if ($Result.StatusCode -ne 200) {
                    throw "Failed to start web server job"
                }
                else {
                    "Web server job started: '{0}' (PID: {1})" -f $Url, $Global:WebServerPid | Write-Host
                }
            }
        }
        "Stop" {
            "Try to kill existing web server processes" | Write-Verbose
            KillWebServerProcess -Force:$true | Out-Null
            try { Get-Item $TempScript -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
            catch {}
        }
        default {
            "Invalid action" | Write-Verbose
            throw "Invalid action: $Action"
        }
    }
}
catch {
    $PSCmdlet.ThrowTerminatingError($PSItem)
}