param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    # A real exception type rather than a PSCustomObject with added members: 'throw' only preserves
    # the object as $_.Exception when it actually derives from System.Exception, and the retry logic
    # reads .Response/.StatusCode/.Headers off exactly that object.
    if (-not ('OmadaWebPSTests.FakeHttpException' -as [type])) {
        Add-Type -TypeDefinition @"
namespace OmadaWebPSTests
{
    public class FakeResponse
    {
        public int StatusCode { get; set; }
        public System.Collections.Generic.Dictionary<string, string> Headers { get; set; }
    }

    public class FakeHttpException : System.Exception
    {
        public FakeResponse Response { get; set; }
        public FakeHttpException(string message) : base(message) { }
    }
}
"@
    }
}

Describe 'Invoke-OmadaRetryableRequest' -Tag 'Unit' {
    # -CommandInfo is invoked with the call operator and splatted parameters, so any script block
    # accepting the same parameters stands in for the resolved Invoke-RestMethod/Invoke-WebRequest
    # command. That keeps these tests on the retry decision itself; the real HTTP round trips are
    # covered by Tests/Integration/Invoke-OmadaRestMethod.Retry.Tests.ps1.

    Context 'Successful requests' {
        It 'Should return the result and call the command once when the request succeeds' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:RetryTestCalls = 0
                $Command = { param($Uri) $Script:RetryTestCalls++; return 'ok' }

                $Result = Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud' } -RetryIntervalSec 0

                $Result | Should -Be 'ok'
                $Script:RetryTestCalls | Should -Be 1
            }
        }
    }

    Context 'Parameter validation' {
        It 'Should reject a negative <Parameter>' -ForEach @(
            @{ Parameter = 'MaximumRetryCount' }
            @{ Parameter = 'RetryIntervalSec' }
            @{ Parameter = 'MaximumRetryDelaySec' }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Parameter = $Parameter } {
                param($Parameter)
                # A negative interval would make every computed backoff fall to zero and turn the
                # retry loop into a hot loop against a server that is already struggling.
                $Arguments = @{
                    CommandInfo = { param($Uri) 'ok' }
                    Parameters  = @{ Uri = 'https://example.omada.cloud' }
                    $Parameter  = -1
                }

                { Invoke-OmadaRetryableRequest @Arguments } | Should -Throw
            }
        }

        It 'Should accept zero for <Parameter>' -ForEach @(
            @{ Parameter = 'MaximumRetryCount' }
            @{ Parameter = 'RetryIntervalSec' }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Parameter = $Parameter } {
                param($Parameter)
                # Zero stays valid: it is how retrying is switched off, and how the tests ask for no wait.
                $Arguments = @{
                    CommandInfo = { param($Uri) 'ok' }
                    Parameters  = @{ Uri = 'https://example.omada.cloud' }
                    $Parameter  = 0
                }

                Invoke-OmadaRetryableRequest @Arguments | Should -Be 'ok'
            }
        }
    }

    Context 'Retryable HTTP status codes' {
        It 'Should retry HTTP <StatusCode> and return the result of the successful attempt' -ForEach @(
            @{ StatusCode = 429 }
            @{ StatusCode = 502 }
            @{ StatusCode = 503 }
            @{ StatusCode = 504 }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ StatusCode = $StatusCode } {
                param($StatusCode)
                $Script:RetryTestCalls = 0
                $Command = {
                    param($Uri)
                    $Script:RetryTestCalls++
                    if ($Script:RetryTestCalls -lt 3) {
                        $Exception = [OmadaWebPSTests.FakeHttpException]::new('transient')
                        $Exception.Response = [OmadaWebPSTests.FakeResponse]::new()
                        $Exception.Response.StatusCode = $StatusCode
                        throw $Exception
                    }
                    return 'recovered'
                }

                $Result = Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud' } -MaximumRetryCount 3 -RetryIntervalSec 0

                $Result | Should -Be 'recovered'
                $Script:RetryTestCalls | Should -Be 3
            }
        }

        It 'Should stop after MaximumRetryCount retries and rethrow the last error' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:RetryTestCalls = 0
                $Command = {
                    param($Uri)
                    $Script:RetryTestCalls++
                    $Exception = [OmadaWebPSTests.FakeHttpException]::new('always throttled')
                    $Exception.Response = [OmadaWebPSTests.FakeResponse]::new()
                    $Exception.Response.StatusCode = 429
                    throw $Exception
                }

                { Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud' } -MaximumRetryCount 2 -RetryIntervalSec 0 } |
                    Should -Throw -ExpectedMessage 'always throttled'

                # One initial attempt plus two retries.
                $Script:RetryTestCalls | Should -Be 3
            }
        }

        It 'Should not retry at all when MaximumRetryCount is 0' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:RetryTestCalls = 0
                $Command = {
                    param($Uri)
                    $Script:RetryTestCalls++
                    $Exception = [OmadaWebPSTests.FakeHttpException]::new('throttled')
                    $Exception.Response = [OmadaWebPSTests.FakeResponse]::new()
                    $Exception.Response.StatusCode = 429
                    throw $Exception
                }

                { Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud' } -MaximumRetryCount 0 -RetryIntervalSec 0 } | Should -Throw

                $Script:RetryTestCalls | Should -Be 1
            }
        }
    }

    Context 'Non-retryable failures' {
        It 'Should not retry HTTP <StatusCode>' -ForEach @(
            @{ StatusCode = 400 }
            @{ StatusCode = 401 }
            @{ StatusCode = 403 }
            @{ StatusCode = 404 }
            @{ StatusCode = 500 }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ StatusCode = $StatusCode } {
                param($StatusCode)
                $Script:RetryTestCalls = 0
                $Command = {
                    param($Uri)
                    $Script:RetryTestCalls++
                    $Exception = [OmadaWebPSTests.FakeHttpException]::new('failed')
                    $Exception.Response = [OmadaWebPSTests.FakeResponse]::new()
                    $Exception.Response.StatusCode = $StatusCode
                    throw $Exception
                }

                { Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud' } -MaximumRetryCount 3 -RetryIntervalSec 0 } | Should -Throw

                $Script:RetryTestCalls | Should -Be 1
            }
        }

        It 'Should not retry the re-authentication signal, which carries no response at all' {
            InModuleScope 'OmadaWeb.PS' {
                # This is the shape of the $CustomErrorTrigger Invoke-OmadaRequest throws at itself
                # to force re-authentication. Retrying it here as well is what would compound into a
                # retry storm, so it has to fall straight through to the caller's catch block.
                $Script:RetryTestCalls = 0
                $Command = { param($Uri) $Script:RetryTestCalls++; throw 'Login failed - 0f8b2a2c-1111-2222-3333-444455556666' }

                { Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud' } -MaximumRetryCount 3 -RetryIntervalSec 0 } | Should -Throw

                $Script:RetryTestCalls | Should -Be 1
            }
        }

        It 'Should not retry a client-side timeout' {
            InModuleScope 'OmadaWeb.PS' {
                # Retrying a timeout would multiply the wall-clock time -TimeoutSec already bounded.
                $Script:RetryTestCalls = 0
                $Command = { param($Uri) $Script:RetryTestCalls++; throw ([System.Threading.Tasks.TaskCanceledException]::new('The operation was canceled.')) }

                { Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud' } -MaximumRetryCount 3 -RetryIntervalSec 0 } | Should -Throw

                $Script:RetryTestCalls | Should -Be 1
            }
        }
    }

    Context 'Socket-level failures' {
        It 'Should retry a WebException that carries no response' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:RetryTestCalls = 0
                $Command = {
                    param($Uri)
                    $Script:RetryTestCalls++
                    if ($Script:RetryTestCalls -lt 2) {
                        throw ([System.Net.WebException]::new('The remote name could not be resolved.'))
                    }
                    return 'recovered'
                }

                Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud' } -MaximumRetryCount 3 -RetryIntervalSec 0 |
                    Should -Be 'recovered'

                $Script:RetryTestCalls | Should -Be 2
            }
        }

        It 'Should retry a socket exception wrapped in an outer exception' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:RetryTestCalls = 0
                $Command = {
                    param($Uri)
                    $Script:RetryTestCalls++
                    if ($Script:RetryTestCalls -lt 2) {
                        $Inner = [System.Net.Sockets.SocketException]::new(10054)
                        throw ([System.Exception]::new('An error occurred while sending the request.', $Inner))
                    }
                    return 'recovered'
                }

                Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud' } -MaximumRetryCount 3 -RetryIntervalSec 0 |
                    Should -Be 'recovered'

                $Script:RetryTestCalls | Should -Be 2
            }
        }
    }

    Context 'Idempotency' {
        It 'Should not retry a <Method> request even on a retryable status code' -ForEach @(
            @{ Method = 'POST' }
            @{ Method = 'PUT' }
            @{ Method = 'PATCH' }
            @{ Method = 'DELETE' }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Method = $Method } {
                param($Method)
                $Script:RetryTestCalls = 0
                $Command = {
                    param($Uri, $Method)
                    $Script:RetryTestCalls++
                    $Exception = [OmadaWebPSTests.FakeHttpException]::new('throttled')
                    $Exception.Response = [OmadaWebPSTests.FakeResponse]::new()
                    $Exception.Response.StatusCode = 503
                    throw $Exception
                }

                { Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud'; Method = $Method } -MaximumRetryCount 3 -RetryIntervalSec 0 } | Should -Throw

                $Script:RetryTestCalls | Should -Be 1
            }
        }

        It 'Should retry a <Method> request' -ForEach @(
            @{ Method = 'GET' }
            @{ Method = 'HEAD' }
            @{ Method = 'get' }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Method = $Method } {
                param($Method)
                $Script:RetryTestCalls = 0
                $Command = {
                    param($Uri, $Method)
                    $Script:RetryTestCalls++
                    if ($Script:RetryTestCalls -lt 2) {
                        $Exception = [OmadaWebPSTests.FakeHttpException]::new('throttled')
                        $Exception.Response = [OmadaWebPSTests.FakeResponse]::new()
                        $Exception.Response.StatusCode = 503
                        throw $Exception
                    }
                    return 'recovered'
                }

                Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud'; Method = $Method } -MaximumRetryCount 3 -RetryIntervalSec 0 |
                    Should -Be 'recovered'

                $Script:RetryTestCalls | Should -Be 2
            }
        }

        It 'Should not retry -CustomMethod <Method>, which carries no Method parameter at all' -ForEach @(
            @{ Method = 'DELETE' }
            @{ Method = 'PURGE' }
            @{ Method = 'POST' }
        ) {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ Method = $Method } {
                param($Method)
                # The native cmdlets put -Method and -CustomMethod in different parameter sets, so a
                # -CustomMethod call arrives here with no Method key. Reading only Method would fall
                # back to the GET default and replay a request that deletes something.
                $Script:RetryTestCalls = 0
                $Command = {
                    param($Uri, $CustomMethod)
                    $Script:RetryTestCalls++
                    $Exception = [OmadaWebPSTests.FakeHttpException]::new('throttled')
                    $Exception.Response = [OmadaWebPSTests.FakeResponse]::new()
                    $Exception.Response.StatusCode = 503
                    throw $Exception
                }

                { Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud'; CustomMethod = $Method } -MaximumRetryCount 3 -RetryIntervalSec 0 } | Should -Throw

                $Script:RetryTestCalls | Should -Be 1
            }
        }

        It 'Should still retry -CustomMethod GET' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:RetryTestCalls = 0
                $Command = {
                    param($Uri, $CustomMethod)
                    $Script:RetryTestCalls++
                    if ($Script:RetryTestCalls -lt 2) {
                        $Exception = [OmadaWebPSTests.FakeHttpException]::new('throttled')
                        $Exception.Response = [OmadaWebPSTests.FakeResponse]::new()
                        $Exception.Response.StatusCode = 503
                        throw $Exception
                    }
                    return 'recovered'
                }

                Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud'; CustomMethod = 'GET' } -MaximumRetryCount 3 -RetryIntervalSec 0 |
                    Should -Be 'recovered'

                $Script:RetryTestCalls | Should -Be 2
            }
        }

        It 'Should treat a request without an explicit method as GET and retry it' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:RetryTestCalls = 0
                $Command = {
                    param($Uri)
                    $Script:RetryTestCalls++
                    if ($Script:RetryTestCalls -lt 2) {
                        $Exception = [OmadaWebPSTests.FakeHttpException]::new('throttled')
                        $Exception.Response = [OmadaWebPSTests.FakeResponse]::new()
                        $Exception.Response.StatusCode = 429
                        throw $Exception
                    }
                    return 'recovered'
                }

                Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud' } -MaximumRetryCount 3 -RetryIntervalSec 0 |
                    Should -Be 'recovered'

                $Script:RetryTestCalls | Should -Be 2
            }
        }
    }

    Context 'Verbose logging' {
        It 'Should log each retry with the status code, the attempt and the delay' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:RetryTestCalls = 0
                $Command = {
                    param($Uri)
                    $Script:RetryTestCalls++
                    if ($Script:RetryTestCalls -lt 3) {
                        $Exception = [OmadaWebPSTests.FakeHttpException]::new('throttled')
                        $Exception.Response = [OmadaWebPSTests.FakeResponse]::new()
                        $Exception.Response.StatusCode = 429
                        throw $Exception
                    }
                    return 'recovered'
                }

                $VerboseOutput = @(Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud' } -MaximumRetryCount 3 -RetryIntervalSec 0 -Verbose 4>&1 |
                        Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })

                $VerboseOutput.Count | Should -Be 2
                $VerboseOutput[0].Message | Should -Match 'HTTP 429'
                $VerboseOutput[0].Message | Should -Match 'retry 1 of 3'
                $VerboseOutput[0].Message | Should -Match '\d+\.\d+s'
                $VerboseOutput[1].Message | Should -Match 'retry 2 of 3'
            }
        }

        It 'Should format the delay the same way under a culture that uses a decimal comma' {
            InModuleScope 'OmadaWeb.PS' {
                $OriginalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
                try {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('nl-NL')
                    $Script:RetryTestCalls = 0
                    $Command = {
                        param($Uri)
                        $Script:RetryTestCalls++
                        if ($Script:RetryTestCalls -lt 2) {
                            $Exception = [OmadaWebPSTests.FakeHttpException]::new('throttled')
                            $Exception.Response = [OmadaWebPSTests.FakeResponse]::new()
                            $Exception.Response.StatusCode = 503
                            throw $Exception
                        }
                        return 'recovered'
                    }

                    $VerboseOutput = @(Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud' } -MaximumRetryCount 3 -RetryIntervalSec 0 -Verbose 4>&1 |
                            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })

                    $VerboseOutput[0].Message | Should -Match '\d+\.\d+s'
                }
                finally {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = $OriginalCulture
                }
            }
        }

        It 'Should report that the delay came from Retry-After when the server sent one' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:RetryTestCalls = 0
                $Command = {
                    param($Uri)
                    $Script:RetryTestCalls++
                    if ($Script:RetryTestCalls -lt 2) {
                        $Exception = [OmadaWebPSTests.FakeHttpException]::new('throttled')
                        $Exception.Response = [OmadaWebPSTests.FakeResponse]::new()
                        $Exception.Response.StatusCode = 429
                        $Exception.Response.Headers = [System.Collections.Generic.Dictionary[string, string]]::new()
                        $Exception.Response.Headers.Add('Retry-After', '0')
                        throw $Exception
                    }
                    return 'recovered'
                }

                $VerboseOutput = @(Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud' } -MaximumRetryCount 3 -RetryIntervalSec 0 -Verbose 4>&1 |
                        Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })

                $VerboseOutput[0].Message | Should -Match 'Retry-After'
            }
        }
    }

    Context 'Backoff' {
        It 'Should honour Retry-After over the computed backoff' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:RetryTestCalls = 0
                $Command = {
                    param($Uri)
                    $Script:RetryTestCalls++
                    if ($Script:RetryTestCalls -lt 2) {
                        $Exception = [OmadaWebPSTests.FakeHttpException]::new('throttled')
                        $Exception.Response = [OmadaWebPSTests.FakeResponse]::new()
                        $Exception.Response.StatusCode = 429
                        $Exception.Response.Headers = [System.Collections.Generic.Dictionary[string, string]]::new()
                        $Exception.Response.Headers.Add('Retry-After', '0')
                        throw $Exception
                    }
                    return 'recovered'
                }

                # A -RetryIntervalSec of 30 would make the first backoff at least 15 seconds. The
                # server asked for 0, so the call has to come back essentially immediately.
                $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud' } -MaximumRetryCount 3 -RetryIntervalSec 30 |
                    Should -Be 'recovered'
                $Stopwatch.Stop()

                $Stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 5
            }
        }

        It 'Should not overflow when the maximum delay exceeds what Start-Sleep can express in milliseconds' {
            InModuleScope 'OmadaWeb.PS' {
                # A Retry-After is capped at -MaximumRetryDelaySec, which accepts any non-negative
                # double. Converting a delay that large to milliseconds overflows Int32, and an
                # unclamped cast would throw - turning a transient failure into an immediate hard
                # one. Start-Sleep is mocked so the clamped value can be asserted without the test
                # waiting out the delay it is checking.
                Mock Start-Sleep { }

                $Script:RetryTestCalls = 0
                $Command = {
                    param($Uri)
                    $Script:RetryTestCalls++
                    if ($Script:RetryTestCalls -lt 2) {
                        $Exception = [OmadaWebPSTests.FakeHttpException]::new('throttled')
                        $Exception.Response = [OmadaWebPSTests.FakeResponse]::new()
                        $Exception.Response.StatusCode = 429
                        $Exception.Response.Headers = [System.Collections.Generic.Dictionary[string, string]]::new()
                        $Exception.Response.Headers.Add('Retry-After', '999999999999')
                        throw $Exception
                    }
                    return 'recovered'
                }

                Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud' } -MaximumRetryCount 3 -RetryIntervalSec 0 -MaximumRetryDelaySec ([double]::MaxValue) |
                    Should -Be 'recovered'

                $Script:RetryTestCalls | Should -Be 2
                Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -eq [int]::MaxValue }
            }
        }

        It 'Should back off exponentially, waiting longer before the second retry than before the first' {
            InModuleScope 'OmadaWeb.PS' {
                $Script:RetryTestTimestamps = [System.Collections.Generic.List[datetime]]::new()
                $Command = {
                    param($Uri)
                    $Script:RetryTestTimestamps.Add([datetime]::UtcNow)
                    if ($Script:RetryTestTimestamps.Count -lt 3) {
                        $Exception = [OmadaWebPSTests.FakeHttpException]::new('throttled')
                        $Exception.Response = [OmadaWebPSTests.FakeResponse]::new()
                        $Exception.Response.StatusCode = 503
                        throw $Exception
                    }
                    return 'recovered'
                }

                Invoke-OmadaRetryableRequest -CommandInfo $Command -Parameters @{ Uri = 'https://example.omada.cloud' } -MaximumRetryCount 3 -RetryIntervalSec 1 |
                    Should -Be 'recovered'

                # Equal jitter bounds the first delay to [0.5s, 1.0s] and the second to [1.0s, 2.0s],
                # so the two ranges cannot overlap however the jitter falls.
                $FirstDelay = ($Script:RetryTestTimestamps[1] - $Script:RetryTestTimestamps[0]).TotalSeconds
                $SecondDelay = ($Script:RetryTestTimestamps[2] - $Script:RetryTestTimestamps[1]).TotalSeconds

                $FirstDelay | Should -BeGreaterThan 0.4
                $SecondDelay | Should -BeGreaterThan $FirstDelay
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
