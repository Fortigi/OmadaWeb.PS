function Write-OmadaDeprecationWarning {
    <#
        Emits the deprecation warning for one entry of Get-OmadaDeprecationSchedule, in one of three
        states derived from that entry's two dates:

        - before WarnFrom                  silent
        - WarnFrom .. RemovedAfter         "will be removed after <date>"
        - after RemovedAfter               "has been removed in newer releases; this version still
                                            supports it" - which keeps the message honest for anyone
                                            running an old version, instead of promising a removal
                                            that has already happened.

        Suppression to once per session lives here rather than at the call sites, so a feature warned
        about from several places still produces a single warning.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Feature,

        # The current time. Injectable on purpose: code gated on a date years away is otherwise code
        # that nobody has ever seen execute - it runs for the first time on users' machines, and if
        # the condition is wrong it is wrong for everyone at once. With this parameter, Pester pins
        # both sides of every boundary today. Production callers omit it.
        [datetime]$UtcNow
    )

    # Resolved in three steps rather than as a parameter default so the fallback chain stays
    # readable: an explicit argument wins, then the script-scoped override (used by tests that
    # cannot pass the parameter because the call is several frames down), then the real clock.
    $Now = $UtcNow
    if (-not $PSBoundParameters.ContainsKey("UtcNow")) {
        $Now = $Script:DeprecationUtcNow
    }

    if ($null -eq $Now) {
        $Now = [datetime]::UtcNow
    }

    if ($Now.Kind -ne [System.DateTimeKind]::Utc) {
        # A Local or Unspecified value is interpreted as local time and converted, so a machine in
        # another timezone compares against the same instant as one running in UTC.
        $Now = $Now.ToUniversalTime()
    }

    $Schedule = Get-OmadaDeprecationSchedule
    if (-not $Schedule.Contains($Feature)) {
        # A typo in a feature name must fail loudly. Silently emitting nothing would look exactly
        # like a correctly suppressed warning.
        "Unknown deprecation feature '{0}'. Add it to Get-OmadaDeprecationSchedule.ps1." -f $Feature | Write-Error -ErrorAction "Stop"
    }

    $Entry = $Schedule[$Feature]

    # Both schedule dates are calendar dates, not instants, and are stored at midnight. Comparing
    # the date components rather than the raw values keeps a whole day on the side it belongs to:
    # the feature is supported for all of its RemovedAfter day, not just its first second, and the
    # warning starts at the beginning of the WarnFrom day.
    $Today = $Now.Date

    if ($Today -lt $Entry.WarnFrom.Date) {
        "{0} - Deprecation '{1}' is not announced yet, staying silent until {2:yyyy-MM-dd}" -f $MyInvocation.MyCommand, $Feature, $Entry.WarnFrom | Write-Verbose
        return
    }

    if ($Script:DeprecationWarningsShown.Contains($Feature)) {
        "{0} - Deprecation '{1}' already warned about in this session" -f $MyInvocation.MyCommand, $Feature | Write-Verbose
        return
    }

    $Script:DeprecationWarningsShown[$Feature] = $true

    if ($Today -gt $Entry.RemovedAfter.Date) {
        $Message = "{0} has been removed in newer releases of OmadaWeb.PS. This version still supports it. Use {1}. See {2}" -f $Entry.DisplayName, $Entry.Replacement, $Entry.Reference
    }
    else {
        $Message = "{0} is deprecated and will be removed after {1:yyyy-MM-dd} (UTC). Use {2}. See {3}" -f $Entry.DisplayName, $Entry.RemovedAfter, $Entry.Replacement, $Entry.Reference
    }

    $Message | Write-Warning
}
