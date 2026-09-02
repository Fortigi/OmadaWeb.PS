function Test-OmadaConsoleControl {
    <#
    .SYNOPSIS
        Whether this process has a console whose Ctrl+C handling can be changed.

    .DESCRIPTION
        Start-WebView2Login takes Ctrl+C over while its modal sign-in window is open, so that pressing
        it closes the window instead of killing the caller's session. Console.TreatControlCAsInput is
        how that is done - and on Windows both its getter and its setter throw

            System.IO.IOException: The handle is invalid.

        when the process has no console attached to standard input. That is not an exotic state: it
        is what a scheduled task, a Windows service, a CI job, and any script whose output is piped
        to a file all look like.

        Because the read sat near the top of Start-WebView2Login, it threw before the browser window
        was ever created, so -AuthenticationType WebView2 failed instantly and non-interactively with
        a message about a handle and nothing about signing in. The scheduled sign-in canary found it
        on its first real run against a tenant (issue #79), and reported it as a changed Microsoft
        sign-in page, which it was not.

        The answer is probed rather than inferred from [Console]::IsInputRedirected. Redirection is
        the common reason a console cannot be driven, but it is not the only one, and a predicate
        that is right about the usual case and wrong about the rest just re-introduces the crash
        somewhere harder to find. Reading the property is cheap, and it is the very operation that
        has to succeed later - so this cannot come to disagree with reality.

    .OUTPUTS
        System.Boolean. True when Console.TreatControlCAsInput can be read and written.

    .EXAMPLE
        if (Test-OmadaConsoleControl) { $Original = [Console]::TreatControlCAsInput }

        The shape every caller uses: nothing is read from the console until this has said it is safe.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param()

    try {
        $null = [Console]::TreatControlCAsInput
        return $true
    }
    catch {
        # Verbose rather than a warning. There is nothing for the user to do about it, nothing is
        # degraded that they would notice - a host with no console has nobody at a keyboard to press
        # Ctrl+C - and this runs on every browser sign-in.
        "{0} - No console is attached, so Ctrl+C handling is left alone: {1}" -f $MyInvocation.MyCommand, $_.Exception.Message | Write-Verbose
        return $false
    }
}
