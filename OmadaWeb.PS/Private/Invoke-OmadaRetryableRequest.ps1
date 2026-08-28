function Invoke-OmadaRetryableRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $CommandInfo,
        [Parameter(Mandatory)]
        [hashtable]$Parameters,
        # Negative values are rejected rather than clamped. A negative interval would make every
        # computed backoff fall to zero and turn this loop into a hot retry loop against a server
        # that is already struggling, and a negative count would silently disable retrying while
        # reading as if it enabled it. Zero stays valid for both: it is how retrying is switched off.
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaximumRetryCount = 3,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$RetryIntervalSec = 2,
        [ValidateRange(0, [double]::MaxValue)]
        [double]$MaximumRetryDelaySec = 300
    )

    # Omada Identity Cloud is multi-tenant SaaS, so throttling and short-lived gateway faults are a
    # matter of when rather than if. Every call to the native cmdlet goes through here so a blip
    # does not surface to the caller - or to OmadaSqlTroubleshooter - as a hard error.
    #
    # Deliberately absent from the retryable set is 401. Re-authentication is handled by the caller's
    # own catch block, which resolves a new cookie and recurses; retrying a 401 here as well would
    # multiply that recursion by the attempt cap and turn one expired cookie into a retry storm.
    $RetryableStatusCodes = @(429, 502, 503, 504)

    # Only idempotent requests are retried. A POST/PUT/PATCH/DELETE that timed out or hit a gateway
    # error may well have been applied server-side already, so replaying it silently could duplicate
    # a write. Paging continuations reach this function with the same GET method as the first page,
    # so they are covered by the same check.
    $Method = "GET"
    if ($Parameters.ContainsKey("Method") -and -not [string]::IsNullOrWhiteSpace($Parameters.Method)) {
        $Method = [string]$Parameters.Method
    }
    $Idempotent = $Method.ToUpperInvariant() -in @("GET", "HEAD")

    $Attempt = 0
    while ($true) {
        try {
            return (& $CommandInfo @Parameters)
        }
        catch {
            $ErrorRecord = $PSItem

            if (-not $Idempotent -or $Attempt -ge $MaximumRetryCount) {
                throw $ErrorRecord
            }

            $StatusCode = Get-OmadaResponseStatusCode -Exception $ErrorRecord.Exception
            if ($null -ne $StatusCode) {
                $Retryable = ([int]$StatusCode) -in $RetryableStatusCodes
                $Reason = "HTTP {0}" -f [int]$StatusCode
            }
            else {
                $Retryable = Test-OmadaTransientFailure -Exception $ErrorRecord.Exception
                $Reason = "network failure"
            }

            if (-not $Retryable) {
                throw $ErrorRecord
            }

            # Exponential backoff from the configured interval, capped so a long chain of retries
            # cannot grow without bound. Equal jitter (half the delay fixed, half random) spreads
            # concurrent clients out without ever collapsing the wait to zero, which pure full
            # jitter would allow and which would defeat the point of backing off under throttling.
            $BackoffSec = [math]::Min($RetryIntervalSec * [math]::Pow(2, $Attempt), $MaximumRetryDelaySec)
            $DelaySec = 0.0
            if ($BackoffSec -gt 0) {
                # Get-Random rejects an empty range, so the zero interval used by the tests - and by
                # anyone who wants retries without a wait - is handled above rather than here.
                $DelaySec = ($BackoffSec / 2) + (Get-Random -Minimum 0.0 -Maximum ($BackoffSec / 2))
            }

            # A Retry-After the server actually sent overrides the computed backoff outright: it is
            # an instruction, not a hint, and guessing shorter is how a throttled client stays
            # throttled.
            $RetryAfterSec = Get-RetryAfterDelay -Exception $ErrorRecord.Exception -MaximumDelaySec $MaximumRetryDelaySec
            if ($null -ne $RetryAfterSec) {
                $DelaySec = $RetryAfterSec
                $Reason = "{0}, Retry-After" -f $Reason
            }

            $Attempt++
            # The delay is formatted with the invariant culture rather than left to -f, so a
            # diagnostic line reads the same whatever locale the operator's session runs under.
            $DelayText = $DelaySec.ToString("N1", [System.Globalization.CultureInfo]::InvariantCulture)
            "{0} - Transient failure ({1}); retry {2} of {3} in {4}s." -f $MyInvocation.MyCommand, $Reason, $Attempt, $MaximumRetryCount, $DelayText | Write-Verbose

            if ($DelaySec -gt 0) {
                Start-Sleep -Milliseconds ([int][math]::Round($DelaySec * 1000))
            }
        }
    }
}
