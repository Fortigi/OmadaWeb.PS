function Clear-OmadaWebCache {
    <#
    .SYNOPSIS
        Reports and removes the data OmadaWeb.PS stores on this machine.

    .DESCRIPTION
        OmadaWeb.PS keeps state between commands so you do not have to sign in again for every
        call. All of it lives under %LOCALAPPDATA%\OmadaWeb.PS:

        - Cookies: the Omada session cookie of each session, encrypted with DPAPI for the current
          user. Caches left in %TEMP% by an earlier version of the module are included.
        - BrowserProfiles: the per-session Edge user profiles used by WebView2 and by Selenium.
          These hold the Entra ID cookies and tokens that make re-authentication silent, so they
          are the artefacts to remove when you want to sign out completely or switch user.
        - Binaries: Selenium, WebView2, msedgedriver.exe and their dependencies, downloaded on
          first use. Removing them only costs a fresh download next time.
        - Sessions: the authentication state held in memory by the current PowerShell session.

        Run with -ListOnly to see what is stored without changing anything. Without -ListOnly the
        artefacts are removed, after confirmation; use -WhatIf to preview and -Force to skip the
        prompt.

        In both cases one object per artefact is returned, reporting the path, how many items it
        holds, how large it is, how it is protected and whether it was removed.

        A binary that is already loaded into the running PowerShell session is locked by Windows
        and cannot be removed. The command reports which ones it could not remove and continues;
        close that PowerShell session and run it again to remove them.

        Files written by -CookiePath are not touched, because their location is chosen by the
        caller and is not known to the module. Remove those yourself.

    .PARAMETER Scope
        Which artefacts to report and remove: All (the default), Cookies, BrowserProfiles,
        Binaries or Sessions. More than one value can be given.

    .PARAMETER ListOnly
        Report what is stored without removing anything.

    .PARAMETER Force
        Remove without asking for confirmation. -WhatIf still takes precedence.

    .INPUTS
        None. This command does not accept pipeline input.

    .OUTPUTS
        PSCustomObject. One object per artefact, with the Scope, Artefact, Path, ItemType,
        Protection, Exists, ItemCount, SizeBytes and Removed properties.

    .EXAMPLE
        Clear-OmadaWebCache -ListOnly | Format-Table Scope, Artefact, Path, ItemCount, SizeBytes

        Shows everything the module has stored on this machine without removing any of it.

    .EXAMPLE
        Clear-OmadaWebCache -WhatIf

        Reports exactly what would be removed, and removes nothing.

    .EXAMPLE
        Clear-OmadaWebCache -Scope Cookies, BrowserProfiles

        Signs out everywhere by dropping the cached session cookies and the Edge profiles holding
        the Entra ID tokens, while keeping the downloaded binaries so the next command does not
        have to download them again. Asks for confirmation first.

    .EXAMPLE
        Clear-OmadaWebCache -Force

        Removes everything the module stores, without prompting. Useful when handing a machine
        over, or as a cleanup step at the end of an automated run.

    .LINK
        https://github.com/Fortigi/OmadaWeb.PS#local-data-footprint

    .LINK
        Invoke-OmadaRestMethod

    .LINK
        Invoke-OmadaWebRequest
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet("All", "Cookies", "BrowserProfiles", "Binaries", "Sessions")]
        [string[]]$Scope = "All",

        [Parameter()]
        [switch]$ListOnly,

        [Parameter()]
        [switch]$Force
    )

    process {
        try {
            "{0}" -f $MyInvocation.MyCommand | Write-Verbose

            $Items = @(Get-OmadaWebCacheItem -Scope $Scope)

            if ($ListOnly) {
                return $Items
            }

            # -Force suppresses the confirmation prompt without disabling -WhatIf, which must keep
            # reporting rather than removing.
            if ($Force -and -not $WhatIfPreference) {
                $ConfirmPreference = "None"
            }

            foreach ($Item in $Items) {
                if (-not $Item.Exists) {
                    "{0} - Nothing to remove for '{1}' ({2})" -f $MyInvocation.MyCommand, $Item.Artefact, $Item.Path | Write-Verbose
                    continue
                }

                if ($Item.ItemType -eq "Memory") {
                    $Action = "Remove {0} ({1} session(s))" -f $Item.Artefact, $Item.ItemCount
                    if ($PSCmdlet.ShouldProcess("Authentication sessions in this PowerShell session", $Action)) {
                        $Script:OmadaSessions = @{}
                        $Script:CurrentWebView2Session = $null
                        $Script:OmadaWebAuthCookie = $null
                        Set-Variable -Name "OmadaWebPSCurrentBaseUrl" -Scope Global -Value $null -Force
                        $Item.Removed = $true
                    }
                    continue
                }

                $Action = "Remove {0} ({1} item(s), {2:N0} bytes)" -f $Item.Artefact, $Item.ItemCount, $Item.SizeBytes
                if ($PSCmdlet.ShouldProcess($Item.Path, $Action)) {
                    try {
                        Remove-Item -Path $Item.Path -Recurse -Force -ErrorAction Stop
                        $Item.Removed = $true
                        "{0} - Removed '{1}'" -f $MyInvocation.MyCommand, $Item.Path | Write-Verbose
                    }
                    catch {
                        # A binary that is already loaded into this process is locked until the
                        # session ends, so a failure here is expected rather than exceptional: report
                        # it and carry on with the remaining artefacts.
                        "Could not remove '{0}': {1} Close this PowerShell session and try again if the files are still in use." -f $Item.Path, $_.Exception.Message | Write-Warning
                    }
                }
            }

            return $Items
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
    }
}
