param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

# Issue #82. The acceptance criterion this file exists for: "Round-trip covered by a test that
# asserts the seeded runspace makes its request without authenticating."
#
# It is asserted in a real second runspace rather than by re-importing the module here, because the
# thing that broke was specifically that a background runspace gets its own module instance with its
# own empty session table. A test that only cleared a hashtable and put it back would pass just as
# happily against the bug.

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop -Prefix Test

    $Script:ModuleUnderTest = $ModulePath

    # The same in-process fake Omada endpoint the retry and -NoInteractiveAuthentication tests use
    # (HttpListener on a background thread via Start-ThreadJob). A real HTTP round trip rather than
    # a mocked Invoke-RestMethod, because Invoke-OmadaRequest resolves the native cmdlet through
    # 'Get-Command -FullyQualifiedModule', which bypasses Pester's function-based mock shadow - and
    # because the worker runspace is outside Pester's reach for mocking anyway.
    $Script:Port = Get-Random -Minimum 23100 -Maximum 24900
    $Script:BaseUrl = "http://127.0.0.1:$Script:Port"

    $Script:SharedServer = [hashtable]::Synchronized(@{
            Listener       = $null
            RequestCount   = 0
            CookiesSeen    = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
            ResponseStatus = 200
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

            # /ready is the startup probe and '/' is the environment-suspension probe
            # Invoke-OmadaRequest makes against the site root the first time a base URL is seen.
            # Neither is the request under test, and the worker runspace makes its own suspension
            # probe as well, so counting them would make the request count meaningless.
            if ($Ctx.Request.Url.AbsolutePath -in @('/ready', '/')) {
                $Bytes = [Text.Encoding]::UTF8.GetBytes('{"value":"ready"}')
                $Ctx.Response.ContentType = 'application/json'
                $Ctx.Response.StatusCode = 200
                $Ctx.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
                $Ctx.Response.Close()
                continue
            }

            $Shared.RequestCount++
            $null = $Shared.CookiesSeen.Add([string]$Ctx.Request.Headers['Cookie'])

            $Ctx.Response.StatusCode = $Shared.ResponseStatus
            $Body = if ($Shared.ResponseStatus -eq 200) { '{"value":"served"}' } else { '{"error":"unauthorized"}' }
            $Bytes = [Text.Encoding]::UTF8.GetBytes($Body)
            $Ctx.Response.ContentType = 'application/json'
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

    # Stands in for the application that signed in: an authenticated session on this runspace's
    # module instance, placed there directly so the test never opens a browser.
    $Script:TokenValue = 'seeded-across-runspaces'
    function Set-SeededSession {
        param(
            [Parameter(Mandatory)]
            [string]$SessionKey
        )

        $Key = "{0}::webview2::{1}" -f "127.0.0.1:$Script:Port", $SessionKey
        InModuleScope 'OmadaWeb.PS' -Parameters @{ Key = $Key; BaseUrl = $Script:BaseUrl; TokenValue = $Script:TokenValue } {
            param($Key, $BaseUrl, $TokenValue)
            $SessionContext = Get-OmadaSessionContext -Key $Key -AuthorityHost '127.0.0.1'
            $SessionContext.BaseUrl = $BaseUrl
            $SessionContext.WebView2Used = $true
            $SessionContext.AuthCookie = [PSCustomObject]@{
                name   = 'oisauthtoken'
                value  = $TokenValue
                domain = '127.0.0.1'
            }
        }
    }

    # Runs a script on a genuinely separate runspace, which imports its own instance of the module -
    # the situation the issue describes. Everything the worker learns comes back in the returned
    # hashtable, because nothing inside it can be reached from here.
    function Invoke-InWorkerRunspace {
        param(
            [Parameter(Mandatory)]
            [scriptblock]$ScriptBlock,

            [Parameter(Mandatory)]
            [AllowNull()]
            $State,

            [Parameter(Mandatory)]
            [string]$Uri,

            [Parameter(Mandatory)]
            [string]$SessionKey,

            [switch]$NoInteractiveAuthentication
        )

        $PowerShell = [powershell]::Create()
        try {
            $null = $PowerShell.AddScript($ScriptBlock).
                AddArgument($Script:ModuleUnderTest).
                AddArgument($State).
                AddArgument($Uri).
                AddArgument($SessionKey).
                AddArgument([bool]$NoInteractiveAuthentication)

            $Output = $PowerShell.Invoke()
            return [PSCustomObject]@{
                Output = @($Output)
                Errors = @($PowerShell.Streams.Error)
            }
        }
        finally {
            $PowerShell.Dispose()
        }
    }

    # One worker body for every scenario, so what differs between them is only what is handed in.
    # It reports what happened rather than throwing, because an exception on a remote runspace
    # arrives here stripped of the error id the assertions are about.
    $Script:WorkerScript = {
        param($ModulePath, $State, $Uri, $SessionKey, $NoInteractiveAuthentication)

        Import-Module $ModulePath -Force -ErrorAction Stop

        $Result = @{
            SessionsBeforeImport = (& (Get-Module OmadaWeb.PS) { $Script:OmadaSessions.Count })
            Imported             = $false
            Value                = $null
            ErrorId              = $null
            ErrorType            = $null
        }

        $RequestParameters = @{
            Uri                = $Uri
            AuthenticationType = 'WebView2'
            SessionKey         = $SessionKey
            SkipCookieCache    = $true
            ErrorAction        = 'Stop'
        }

        # Only the control case - the worker that was handed no session - passes the switch, and it
        # has to: with no session and no switch, that call is exactly the one that opens a sign-in
        # window, which must never happen on the machine running this suite.
        #
        # The cases that matter here leave it off on purpose. A seeded session carries the refusal
        # itself, so nothing a worker does can open a window even when the worker never thought to
        # ask - which is the guarantee issue #82 is about.
        if ($NoInteractiveAuthentication) {
            $RequestParameters['NoInteractiveAuthentication'] = $true
        }

        try {
            if ($null -ne $State) {
                Import-OmadaSession -State $State -ErrorAction Stop
                $Result.Imported = $true
            }

            $Response = Invoke-OmadaRestMethod @RequestParameters
            $Result.Value = $Response.value
        }
        catch {
            $Result.ErrorId = $PSItem.FullyQualifiedErrorId
            $Result.ErrorType = $PSItem.Exception.GetType().FullName
        }

        return [PSCustomObject]$Result
    }

    function Reset-FakeServer {
        param(
            [int]$Status = 200
        )
        $Script:SharedServer.ResponseStatus = $Status
        $Script:SharedServer.RequestCount = 0
        $Script:SharedServer.CookiesSeen.Clear()
    }
}

Describe 'Export-OmadaSession / Import-OmadaSession across runspaces' -Tag 'Integration' {
    Context 'A session handed to a worker runspace' {
        It 'Should make its request on the exported session, without authenticating' {
            Reset-FakeServer -Status 200
            Set-SeededSession -SessionKey 'runspace-live'

            $State = Export-TestOmadaSession -Uri $Script:BaseUrl -SessionKey 'runspace-live'
            $Worker = Invoke-InWorkerRunspace -ScriptBlock $Script:WorkerScript -State $State -Uri "$Script:BaseUrl/data" -SessionKey 'runspace-live'

            $Result = $Worker.Output | Select-Object -Last 1
            $Result | Should -Not -BeNullOrEmpty

            # The worker really did start from nothing: its own module instance, its own empty
            # session table. This is the assertion that makes the rest of the test mean something.
            $Result.SessionsBeforeImport | Should -Be 0
            $Result.Imported | Should -BeTrue

            $Result.ErrorId | Should -BeNullOrEmpty
            $Result.Value | Should -Be 'served'

            # The request went out on the cookie that was exported here, not on one the worker
            # acquired for itself - it had no way to acquire one.
            $Script:SharedServer.RequestCount | Should -Be 1
            $Script:SharedServer.CookiesSeen[0] | Should -BeLike ("*oisauthtoken={0}*" -f $Script:TokenValue)
        }
    }

    Context 'A worker that was handed nothing' {
        It 'Should fail rather than sign in, which is what the seeding avoids' {
            # The control for the test above. Same worker, same call, no state: the only difference
            # is the session it was given, so a pass here is what proves the import did the work
            # rather than the request succeeding for some reason of its own.
            #
            # This one call does pass -NoInteractiveAuthentication, because without a session and
            # without the switch it is the call that opens a sign-in window.
            Reset-FakeServer -Status 200

            $Worker = Invoke-InWorkerRunspace -ScriptBlock $Script:WorkerScript -State $null -Uri "$Script:BaseUrl/data" -SessionKey 'runspace-none' -NoInteractiveAuthentication

            $Result = $Worker.Output | Select-Object -Last 1
            $Result.Imported | Should -BeFalse
            $Result.Value | Should -BeNullOrEmpty
            $Result.ErrorId | Should -BeLike 'OmadaSessionExpired*'
            $Script:SharedServer.RequestCount | Should -Be 0
        }
    }

    Context 'A session that dies after it was handed over' {
        It 'Should report the session as gone instead of opening a sign-in' {
            # An Omada session cookie lives about ten minutes, so this is the ordinary end of a
            # seeded session rather than a corner case: the state was good when it was exported and
            # the server rejects it by the time the worker uses it.
            Reset-FakeServer -Status 401
            Set-SeededSession -SessionKey 'runspace-expired'

            $State = Export-TestOmadaSession -Uri $Script:BaseUrl -SessionKey 'runspace-expired'
            $Worker = Invoke-InWorkerRunspace -ScriptBlock $Script:WorkerScript -State $State -Uri "$Script:BaseUrl/data" -SessionKey 'runspace-expired'

            $Result = $Worker.Output | Select-Object -Last 1
            $Result.Imported | Should -BeTrue
            $Result.ErrorId | Should -BeLike 'OmadaSessionExpired*'
            $Result.ErrorType | Should -Be 'System.Security.Authentication.AuthenticationException'

            # One request and no more: the 401 was not followed by a re-authentication and a replay.
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
