param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop -Prefix Test

    # A dedicated, in-process fake OData server (HttpListener on a background thread via
    # Start-ThreadJob) that serves paginated '@odata.nextLink' responses based on request path.
    # A real HTTP round trip is used instead of mocking Invoke-RestMethod, because
    # Invoke-OmadaRequest resolves the native cmdlet via 'Get-Command -FullyQualifiedModule',
    # which bypasses Pester's function-based mock shadow for Invoke-RestMethod, and mocking
    # Get-Command itself to work around that causes PowerShell's dynamic parameter resolution to
    # recurse into itself (call depth overflow).
    $Script:Port = Get-Random -Minimum 17000 -Maximum 19000
    $Script:BaseUrl = "http://127.0.0.1:$Script:Port"
    $Script:SharedServer = [hashtable]::Synchronized(@{ Listener = $null })

    $Script:ServerJob = Start-ThreadJob -ArgumentList $Script:Port, $Script:SharedServer -ScriptBlock {
        param($Port, $Shared)
        $Listener = [System.Net.HttpListener]::new()
        $Listener.Prefixes.Add("http://127.0.0.1:$Port/")
        $Listener.Start()
        $Shared.Listener = $Listener
        $BaseUrl = "http://127.0.0.1:$Port"
        while ($Listener.IsListening) {
            try {
                $Ctx = $Listener.GetContext()
            }
            catch {
                break
            }
            $Body = switch ($Ctx.Request.Url.AbsolutePath) {
                '/page1' { '{{"value":["item1","item2"],"@odata.nextLink":"{0}/page2"}}' -f $BaseUrl }
                '/page2' { '{{"value":["item3","item4"],"@odata.nextLink":"{0}/page3"}}' -f $BaseUrl }
                '/page3' { '{"value":["item5"]}' }
                '/nonextlink' { '{"value":["only"]}' }
                '/emptynextlink' { '{"value":["only"],"@odata.nextLink":"   "}' }
                default { '{"value":[]}' }
            }
            $Bytes = [Text.Encoding]::UTF8.GetBytes($Body)
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
                $iwParams = @{ Uri = "$Script:BaseUrl/page1"; TimeoutSec = 1 }
                if ($PSVersionTable.PSVersion.Major -lt 6) { $iwParams.UseBasicParsing = $true }
                $null = Invoke-WebRequest @iwParams
                $Ready = $true
            }
            catch [System.Net.Http.HttpRequestException] {
                Start-Sleep -Milliseconds 200
            }
            catch {
                $Ready = $true
            }
        }
    }
    if (-not $Ready) {
        throw "Failed to start the fake OData server on $Script:BaseUrl"
    }
}

Describe 'Invoke-TestOmadaRestMethod -Paged' -Tag 'Integration' {
    Context 'Paging disabled' {
        It 'Should make a single request when -Paged is not supplied' {
            $Result = Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/page1" -AuthenticationType None

            $Result.value | Should -Be @('item1', 'item2')
            $Result.'@odata.nextLink' | Should -Be "$Script:BaseUrl/page2"
        }

        It 'Should make a single request when -Paged:$false is explicitly supplied' {
            $Result = Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/page1" -AuthenticationType None -Paged:$false

            $Result.value | Should -Be @('item1', 'item2')
            $Result.'@odata.nextLink' | Should -Be "$Script:BaseUrl/page2"
        }

        It 'Should make a single request when -Paged is used but the response has no @odata.nextLink property' {
            $Result = Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/nonextlink" -AuthenticationType None -Paged

            $Result.value | Should -Be @('only')
        }

        It 'Should make a single request when -Paged is used but @odata.nextLink is empty/whitespace' {
            $Result = Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/emptynextlink" -AuthenticationType None -Paged

            $Result.value | Should -Be @('only')
        }
    }

    Context 'Paging enabled' {
        It 'Should follow @odata.nextLink across all pages and flatten the values' {
            $Result = Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/page1" -AuthenticationType None -Paged

            $Result.value | Should -Be @('item1', 'item2', 'item3', 'item4', 'item5')
            ($Result.PSObject.Properties.Name -contains '@odata.nextLink') | Should -Be $false
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
