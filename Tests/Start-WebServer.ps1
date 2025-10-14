param(
    [parameter(Mandatory = $true)]
    [ValidateSet("Start", "Stop")]
    $Action,
    [parameter(Mandatory = $false)]
    [int]$Port = 9080,
    [switch]$Force
)

function KillJobs {
    param(
        [switch]$Force
    )

    if ($null -eq $Global:WebServerPid -or $Global:WebServerPid -eq 0) {
        return $true
    }
    $ProcessObject = Get-Process | Where-Object { $_.Id -eq $Global:WebServerPid }
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
        $Global:WebServerPid = $null
        return $true
    }
    else {
        return $false
    }
}

$Url = "http://127.0.0.1:{0}/" -f $Port
switch ($Action) {
    "Start" {

        if (KillJobs -Force:$Force) {
            $TempScript = Join-Path $env:TEMP "WebServer-$Port.ps1"
            @'
PARAM(
    [string]$Url = "{0}"
)
    try{{
        Write-Host "Url: $Url"
        $Listener = [System.Net.HttpListener]::new()
        $Listener.Prefixes.Add($Url)
        $Listener.Start()
        Write-Host "Listening on $Url - Press Ctrl+C to stop"
        while ($true) {{
            $Ctx = $Listener.GetContext()
            $Bytes = [Text.Encoding]::UTF8.GetBytes("OK")
            $Ctx.Response.StatusCode = 200
            $Ctx.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
            $Ctx.Response.Close()
            }}
    }}
    catch{{
        Throw
    }}
'@ -f $Url | Out-File $TempScript -Force -Encoding UTF8

            $Arguments = "-NoLogo -NoProfile -File `"$TempScript`""
            $Global:WebServerPid = (Start-Process (Get-Command pwsh.exe).Source -ArgumentList $Arguments -PassThru).Id

            1..30 | ForEach-Object {
                try {
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
        KillJobs -Force:$true | Out-Null
    }
    default {
        throw "Invalid action: $Action"
    }
}
