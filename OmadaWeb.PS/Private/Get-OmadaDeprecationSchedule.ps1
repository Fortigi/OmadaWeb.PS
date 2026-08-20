function Get-OmadaDeprecationSchedule {
    <#
        The single place where deprecation dates live. Every dated deprecation in the module is one
        entry here, so moving a date later stays a one-line change instead of a hunt through the
        authentication code.

        Per entry:
        - WarnFrom     the first moment the warning is shown. A date in the past means "warn
                       immediately". Set it to the announcement date, not to the release date - the
                       warning is driven by the calendar, not by shipping something on the day.
        - RemovedAfter the last date on which the feature is supported. It is removed in the first
                       release published after this date, which is not necessarily on the date
                       itself, so both the message wording and the comparisons below treat it as
                       inclusive.
        - Replacement  what to use instead, phrased so it can be dropped into a sentence.
        - Reference    the issue carrying the full announcement.

        Both dates are constructed with an explicit DateTimeKind of Utc so the comparison in
        Write-OmadaDeprecationWarning cannot flip a day early or late on a machine in another
        timezone.
    #>
    [CmdletBinding()]
    param()

    return [ordered]@{
        SeleniumBrowserEngine = [ordered]@{
            DisplayName  = "The Selenium browser engine behind -AuthenticationType Browser"
            WarnFrom     = [datetime]::new(2026, 8, 19, 0, 0, 0, [System.DateTimeKind]::Utc)
            RemovedAfter = [datetime]::new(2027, 3, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
            Replacement  = "WebView2, which -AuthenticationType Browser will itself run on after the switch - so no script change is needed"
            Reference    = "https://github.com/Fortigi/OmadaWeb.PS/issues/50"
        }
    }
}
