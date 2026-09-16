[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingAllowUnencryptedAuthentication', '', Justification = 'Exercises the module against an in-process http:// fake endpoint; the switch is required to get past Invoke-RestMethod''s own credential-over-http validator in this test-only scenario.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ModulePath', Justification = 'Used inside the BeforeAll script block, a scope the analyzer does not cross.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseUsingScopeModifierInNewRunspaces', '', Justification = 'Start-ThreadJob -ArgumentList already passes these in explicitly, received via the script block''s own param() - the analyzer does not associate the two.')]
param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop -Prefix Test

    # A real HTTP round trip, not mocked Invoke-RestMethod: Invoke-OmadaRequest resolves the native
    # cmdlet via 'Get-Command -FullyQualifiedModule', which bypasses Pester's function-based mock
    # shadow (see Invoke-OmadaRestMethod.Retry.Tests.ps1). Same harness shape as that file: a
    # dedicated in-process fake endpoint on a background thread, recording what it actually
    # received so the assertions can tell the module's own copy of -Headers apart from whatever
    # the caller still holds.
    #
    # -OAuthUri is pointed at this same http:// listener for the OAuth scenario below. Issue #102
    # will require -OAuthUri to be https; until that lands, http is the only way to exercise the
    # OAuth authentication path against an in-process fake endpoint.
    $Script:Port = Get-Random -Minimum 19000 -Maximum 21000
    $Script:BaseUrl = "http://127.0.0.1:$Script:Port"

    $Script:SharedServer = [hashtable]::Synchronized(@{
            Listener          = $null
            RequestCount      = 0
            LastAuthorization = $null
            LastContentType   = $null
            ContentTypeCount  = 0
            MarkerCount       = 0
            LastMarker        = $null
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

            $Path = $Ctx.Request.Url.AbsolutePath

            if ($Path -in @('/ready', '/')) {
                $Bytes = [Text.Encoding]::UTF8.GetBytes('{"value":"ready"}')
                $Ctx.Response.ContentType = 'application/json'
                $Ctx.Response.StatusCode = 200
                $Ctx.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
                $Ctx.Response.Close()
                continue
            }

            if ($Path -eq '/token') {
                $Bytes = [Text.Encoding]::UTF8.GetBytes('{"access_token":"fake-oauth-token","token_type":"Bearer","expires_in":3600}')
                $Ctx.Response.ContentType = 'application/json'
                $Ctx.Response.StatusCode = 200
                $Ctx.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
                $Ctx.Response.Close()
                continue
            }

            if ($Path -eq '/data') {
                $Shared.RequestCount++
                $Shared.LastAuthorization = $Ctx.Request.Headers['Authorization']
                $Shared.LastContentType = $Ctx.Request.ContentType
                $HeaderNames = @($Ctx.Request.Headers.AllKeys)
                $Shared.ContentTypeCount = @($HeaderNames | Where-Object { $_ -eq 'Content-Type' }).Count
                $Shared.MarkerCount = @($HeaderNames | Where-Object { $_ -eq 'X-Marker' }).Count
                $Shared.LastMarker = $Ctx.Request.Headers['X-Marker']

                $Bytes = [Text.Encoding]::UTF8.GetBytes('{"value":"served"}')
                $Ctx.Response.ContentType = 'application/json'
                $Ctx.Response.StatusCode = 200
                $Ctx.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
                $Ctx.Response.Close()
                continue
            }

            $Ctx.Response.StatusCode = 404
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
        $Script:SharedServer.RequestCount = 0
        $Script:SharedServer.LastAuthorization = $null
        $Script:SharedServer.LastContentType = $null
        $Script:SharedServer.ContentTypeCount = 0
        $Script:SharedServer.MarkerCount = 0
        $Script:SharedServer.LastMarker = $null
    }
}

Describe 'Invoke-TestOmadaRestMethod does not mutate the caller''s -Headers' -Tag 'Integration' {
    Context 'OAuth authentication' {
        It 'Leaves the caller''s Headers hashtable unchanged and lets it be reused for a second call' {
            Reset-FakeServer

            $Credential = New-Object System.Management.Automation.PSCredential('test-client', (ConvertTo-SecureString 'test-secret' -AsPlainText -Force))
            $CallerHeaders = @{ 'X-Caller' = 'present' }

            $Result1 = Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType OAuth -OAuthUri "$Script:BaseUrl/token" -ClientId 'test-client' -Credential $Credential -Headers $CallerHeaders -AllowUnencryptedAuthentication

            $Result1.value | Should -Be 'served'
            $CallerHeaders.Count | Should -Be 1
            $CallerHeaders.Keys | Should -Not -Contain 'Authorization'
            $Script:SharedServer.LastAuthorization | Should -Be 'Bearer fake-oauth-token'

            # Reused for a second call - this is exactly what threw "Item has already been added.
            # Key in dictionary: 'Authorization'" before the fix, because the first call had added
            # the token straight into the caller's own hashtable.
            Reset-FakeServer
            { Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType OAuth -OAuthUri "$Script:BaseUrl/token" -ClientId 'test-client' -Credential $Credential -Headers $CallerHeaders -AllowUnencryptedAuthentication -ErrorAction Stop } | Should -Not -Throw

            $CallerHeaders.Count | Should -Be 1
            $CallerHeaders.Keys | Should -Not -Contain 'Authorization'
        }
    }

    Context 'Basic authentication' {
        It 'Leaves the caller''s Headers hashtable unchanged, holds no Base64 credential, and can be reused' {
            Reset-FakeServer

            $Credential = New-Object System.Management.Automation.PSCredential('basic-user', (ConvertTo-SecureString 'basic-pass' -AsPlainText -Force))
            $CallerHeaders = @{ 'X-Caller' = 'present' }
            $ExpectedBasic = 'Basic {0}' -f [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes('basic-user:basic-pass'))

            $Result1 = Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType Basic -Credential $Credential -Headers $CallerHeaders -AllowUnencryptedAuthentication

            $Result1.value | Should -Be 'served'
            $CallerHeaders.Count | Should -Be 1
            $CallerHeaders.Keys | Should -Not -Contain 'Authorization'
            ($CallerHeaders.Values -join ',') | Should -Not -Match 'basic-user:basic-pass' -Because 'the Base64 credential must never land in the caller''s own hashtable'
            $Script:SharedServer.LastAuthorization | Should -Be $ExpectedBasic

            Reset-FakeServer
            { Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType Basic -Credential $Credential -Headers $CallerHeaders -AllowUnencryptedAuthentication -ErrorAction Stop } | Should -Not -Throw

            $CallerHeaders.Count | Should -Be 1
            $Script:SharedServer.LastAuthorization | Should -Be $ExpectedBasic
        }
    }

    Context 'Caller-supplied Authorization header' {
        It 'Does not throw, and the module''s own authentication value is what is sent' {
            Reset-FakeServer

            $Credential = New-Object System.Management.Automation.PSCredential('basic-user2', (ConvertTo-SecureString 'basic-pass2' -AsPlainText -Force))
            $CallerHeaders = @{ 'Authorization' = 'Bearer caller-supplied-value' }
            $ExpectedBasic = 'Basic {0}' -f [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes('basic-user2:basic-pass2'))

            { Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType Basic -Credential $Credential -Headers $CallerHeaders -AllowUnencryptedAuthentication -ErrorAction Stop } | Should -Not -Throw

            $Script:SharedServer.LastAuthorization | Should -Be $ExpectedBasic
            $CallerHeaders['Authorization'] | Should -Be 'Bearer caller-supplied-value' -Because 'the caller''s own hashtable is never mutated'
        }
    }

    Context '-ContentType together with a Content-Type header' {
        It 'Does not throw, and the -ContentType parameter value is what is sent' {
            Reset-FakeServer

            $CallerHeaders = @{ 'Content-Type' = 'text/plain' }

            { Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType None -Method POST -Body '{"a":1}' -ContentType 'application/xml' -Headers $CallerHeaders -ErrorAction Stop } | Should -Not -Throw

            $Script:SharedServer.LastContentType | Should -Be 'application/xml'
            $Script:SharedServer.ContentTypeCount | Should -Be 1
            $CallerHeaders['Content-Type'] | Should -Be 'text/plain' -Because 'the caller''s own hashtable is never mutated'
        }
    }

    Context 'Case-insensitive header lookup in the copy' {
        It 'Coalesces differently-cased Content-Type keys from a case-sensitive caller dictionary into a single header' {
            Reset-FakeServer

            # A case-sensitive .NET dictionary (unlike a PowerShell hashtable literal) can legally
            # hold both of these as distinct keys - exactly the shape the copy step has to fold into
            # one case-insensitive entry rather than throwing or sending two Content-Type headers.
            # A GET carries no request content, so a Content-Type header would never reach the wire
            # to prove the coalescing happened - a POST with a body is used purely so the header is
            # observable on the fake server, the same as the -ContentType scenario above.
            $CallerHeaders = [System.Collections.Generic.Dictionary[string, string]]::new()
            $CallerHeaders['x-marker'] = 'one'
            $CallerHeaders['X-Marker'] = 'two'

            { Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType None -Method POST -Body '{"a":1}' -Headers $CallerHeaders -ErrorAction Stop } | Should -Not -Throw

            $Script:SharedServer.MarkerCount | Should -Be 1 -Because 'the copy step must fold the two case-differing keys into one'
            $Script:SharedServer.LastMarker | Should -BeIn @('one', 'two') -Because 'one of the source values must win - which one is an enumeration-order detail, not asserted here'
            $CallerHeaders.Count | Should -Be 2 -Because 'the caller''s own dictionary is never mutated, so both of its original keys remain'
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
