param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop -Prefix Test

    # A dedicated, in-process fake Omada endpoint (HttpListener on a background thread via
    # Start-ThreadJob) that fails a configurable number of times before succeeding. A real HTTP
    # round trip is used instead of mocking Invoke-RestMethod, because Invoke-OmadaRequest resolves
    # the native cmdlet via 'Get-Command -FullyQualifiedModule', which bypasses Pester's
    # function-based mock shadow, and mocking Get-Command itself makes PowerShell's dynamic
    # parameter resolution recurse into itself (call depth overflow). It is the same harness shape
    # as Invoke-OmadaRestMethod.Paged.Tests.ps1.
    $Script:Port = Get-Random -Minimum 19000 -Maximum 21000
    $Script:BaseUrl = "http://127.0.0.1:$Script:Port"

    # $Shared is written by the test thread to arm each scenario and read/updated by the listener
    # thread, so it has to be a synchronized hashtable rather than a plain one.
    $Script:SharedServer = [hashtable]::Synchronized(@{
            Listener      = $null
            FailuresLeft  = 0
            RequestCount  = 0
            MethodsSeen   = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
            FailureMode   = 'None'
            RetryAfter    = $null
            FailureStatus = 503
        })

    $Script:ServerJob = Start-ThreadJob -ArgumentList $Script:Port, $Script:SharedServer -ScriptBlock {
        param($Port, $Shared)
        $Listener = [System.Net.HttpListener]::new()
        $Listener.Prefixes.Add("http://127.0.0.1:$Port/")
        $Listener.Start()
        $Shared.Listener = $Listener
        while ($Listener.IsListening) {
            try {
                $Ctx = $Listener.GetContext()
            }
            catch {
                break
            }

            # /ready is the startup probe, and '/' is the environment-suspension probe
            # Invoke-OmadaRequest makes against the site root the first time a base URL is seen.
            # Neither is the request under test, so neither may be counted or failed - otherwise the
            # probe would consume the failure budget the test just armed.
            if ($Ctx.Request.Url.AbsolutePath -in @('/ready', '/')) {
                $Bytes = [Text.Encoding]::UTF8.GetBytes('{"value":"ready"}')
                $Ctx.Response.ContentType = 'application/json'
                $Ctx.Response.StatusCode = 200
                $Ctx.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
                $Ctx.Response.Close()
                continue
            }

            $Shared.RequestCount++
            $null = $Shared.MethodsSeen.Add($Ctx.Request.HttpMethod)

            if ($Shared.FailuresLeft -gt 0) {
                $Shared.FailuresLeft--

                if ($Shared.FailureMode -eq 'Socket') {
                    # Abort drops the connection without a response, which surfaces on the client as
                    # a socket-level failure rather than as an HTTP status code.
                    $Ctx.Response.Abort()
                    continue
                }

                $Ctx.Response.StatusCode = $Shared.FailureStatus
                if ($null -ne $Shared.RetryAfter) {
                    $Ctx.Response.Headers.Add('Retry-After', [string]$Shared.RetryAfter)
                }
                $Bytes = [Text.Encoding]::UTF8.GetBytes('{"error":"transient"}')
                $Ctx.Response.ContentType = 'application/json'
                $Ctx.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
                $Ctx.Response.Close()
                continue
            }

            $Bytes = [Text.Encoding]::UTF8.GetBytes('{"value":"served"}')
            $Ctx.Response.ContentType = 'application/json'
            $Ctx.Response.StatusCode = 200
            $Ctx.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
            $Ctx.Response.Close()
        }
    }

    $Ready = $false
    1..30 | ForEach-Object {
        if (-not $Ready) {
            try {
                $ProbeParameters = @{ Uri = "$Script:BaseUrl/ready"; TimeoutSec = 1 }
                if ($PSVersionTable.PSVersion.Major -lt 6) { $ProbeParameters.UseBasicParsing = $true }
                $null = Invoke-WebRequest @ProbeParameters
                $Ready = $true
            }
            catch [System.Net.WebException], [System.Net.Http.HttpRequestException] {
                Start-Sleep -Milliseconds 200
            }
            catch {
                $Ready = $true
            }
        }
    }
    if (-not $Ready) {
        throw "Failed to start the fake Omada endpoint on $Script:BaseUrl"
    }

    function Reset-FakeServer {
        param(
            [int]$Failures = 0,
            [string]$Mode = 'Status',
            [int]$Status = 503,
            $RetryAfter = $null
        )
        $Script:SharedServer.FailuresLeft = $Failures
        $Script:SharedServer.FailureMode = $Mode
        $Script:SharedServer.FailureStatus = $Status
        $Script:SharedServer.RetryAfter = $RetryAfter
        $Script:SharedServer.RequestCount = 0
        $Script:SharedServer.MethodsSeen.Clear()
    }
}

Describe 'Invoke-TestOmadaRestMethod retry policy' -Tag 'Integration' {
    Context 'HTTP 429 with Retry-After' {
        It 'Should retry a throttled request and return the eventual response' {
            Reset-FakeServer -Failures 2 -Status 429 -RetryAfter 1

            $Result = Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType None

            $Result.value | Should -Be 'served'
            $Script:SharedServer.RequestCount | Should -Be 3
        }

        It 'Should honour a Retry-After given as an HTTP-date' {
            Reset-FakeServer -Failures 1 -Status 429 -RetryAfter ([datetime]::UtcNow.AddSeconds(1).ToString('r'))

            $Result = Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType None

            $Result.value | Should -Be 'served'
            $Script:SharedServer.RequestCount | Should -Be 2
        }

        It 'Should wait roughly as long as Retry-After asks for' {
            Reset-FakeServer -Failures 1 -Status 429 -RetryAfter 3

            # -RetryIntervalSec 0 removes the module's own backoff entirely, so anything the call
            # waits here can only have come from the Retry-After header.
            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $Result = Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType None -RetryIntervalSec 0
            $Stopwatch.Stop()

            $Result.value | Should -Be 'served'
            $Stopwatch.Elapsed.TotalSeconds | Should -BeGreaterThan 2.5
        }
    }

    Context 'HTTP 503' {
        It 'Should retry a 503 and return the eventual response' {
            Reset-FakeServer -Failures 3 -Status 503

            $Result = Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType None -RetryIntervalSec 0

            $Result.value | Should -Be 'served'
            $Script:SharedServer.RequestCount | Should -Be 4
        }

        It 'Should give up after MaximumRetryCount retries and surface the error' {
            Reset-FakeServer -Failures 99 -Status 503

            { Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType None -MaximumRetryCount 2 -RetryIntervalSec 0 -ErrorAction Stop } | Should -Throw

            # One initial attempt plus two retries, and no more.
            $Script:SharedServer.RequestCount | Should -Be 3
        }

        It 'Should not retry when the retry policy is switched off with -MaximumRetryCount 0' {
            Reset-FakeServer -Failures 99 -Status 503

            { Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType None -MaximumRetryCount 0 -ErrorAction Stop } | Should -Throw

            $Script:SharedServer.RequestCount | Should -Be 1
        }

        It 'Should accept -MaxRetryCount as an alias of -MaximumRetryCount' {
            Reset-FakeServer -Failures 99 -Status 503

            { Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType None -MaxRetryCount 1 -RetryIntervalSec 0 -ErrorAction Stop } | Should -Throw

            $Script:SharedServer.RequestCount | Should -Be 2
        }

        It 'Should log every retry at verbose with the status code and the delay' {
            Reset-FakeServer -Failures 2 -Status 503

            $VerboseOutput = @(Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType None -RetryIntervalSec 0 -Verbose 4>&1 |
                    Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match 'Transient failure' })

            $VerboseOutput.Count | Should -Be 2
            $VerboseOutput[0].Message | Should -Match 'HTTP 503'
            $VerboseOutput[0].Message | Should -Match 'retry 1 of 3'
        }
    }

    Context 'Parameter validation' {
        It 'Should reject a negative -<Parameter> before making any request' -ForEach @(
            @{ Parameter = 'MaximumRetryCount' }
            @{ Parameter = 'RetryIntervalSec' }
        ) {
            Reset-FakeServer

            $Arguments = @{
                Uri                = "$Script:BaseUrl/data"
                AuthenticationType = 'None'
                $Parameter         = -1
            }

            { Invoke-TestOmadaRestMethod @Arguments -ErrorAction Stop } | Should -Throw

            # Rejected at parameter binding, so the server is never contacted at all.
            $Script:SharedServer.RequestCount | Should -Be 0
        }
    }

    Context 'Socket-level failure' {
        It 'Should retry a dropped connection and return the eventual response' {
            Reset-FakeServer -Failures 1 -Mode 'Socket'

            $Result = Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType None -RetryIntervalSec 0

            $Result.value | Should -Be 'served'
            $Script:SharedServer.RequestCount | Should -Be 2
        }
    }

    Context 'Non-idempotent requests' {
        It 'Should not retry a POST, even on a status code that would be retried for a GET' {
            Reset-FakeServer -Failures 99 -Status 503

            { Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType None -Method POST -Body @{ foo = 'bar' } -RetryIntervalSec 0 -ErrorAction Stop } | Should -Throw

            $Script:SharedServer.RequestCount | Should -Be 1
            $Script:SharedServer.MethodsSeen[0] | Should -Be 'POST'
        }

        It 'Should not retry a PUT' {
            Reset-FakeServer -Failures 99 -Status 429 -RetryAfter 1

            { Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType None -Method PUT -Body @{ foo = 'bar' } -RetryIntervalSec 0 -ErrorAction Stop } | Should -Throw

            $Script:SharedServer.RequestCount | Should -Be 1
        }
    }

    Context 'Non-retryable responses' {
        It 'Should not retry an HTTP <Status>' -ForEach @(
            @{ Status = 400 }
            @{ Status = 404 }
            @{ Status = 500 }
        ) {
            Reset-FakeServer -Failures 99 -Status $Status

            { Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType None -RetryIntervalSec 0 -ErrorAction Stop } | Should -Throw

            $Script:SharedServer.RequestCount | Should -Be 1
        }

        It 'Should not retry an HTTP 401, which is left to the re-authentication path instead' {
            # -AuthenticationType None means the 401 re-authentication branch does not apply, so this
            # asserts the half that matters here: the retry policy itself never touches a 401, which
            # is what keeps a retry storm from compounding on top of the re-authentication recursion.
            Reset-FakeServer -Failures 99 -Status 401

            { Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType None -RetryIntervalSec 0 -ErrorAction Stop } | Should -Throw

            $Script:SharedServer.RequestCount | Should -Be 1
        }
    }
}

AfterAll {
    if ($Script:SharedServer.Listener) {
        $Script:SharedServer.Listener.Stop()
        $Script:SharedServer.Listener.Close()
    }
    if ($Script:ServerJob) {
        $Script:ServerJob | Stop-Job -PassThru | Remove-Job
    }
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
