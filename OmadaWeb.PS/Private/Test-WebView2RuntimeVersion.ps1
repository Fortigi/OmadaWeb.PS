function Test-WebView2RuntimeVersion {
    [CmdletBinding()]
    param(
        [switch]$IncludeWpf
    )
    try {
        try {
            if ($null -eq $Script:WebView2LatestVersion) {
                # The expected version is the one pinned in the lock file, not whatever nuget.org
                # currently calls latest: an unpinned version could not be hash-verified before being
                # loaded. A newer WebView2 therefore arrives with a module update.
                [System.Version]$Script:WebView2LatestVersion = (Get-LockedArtifact -Id "Microsoft.Web.WebView2").Version
            }
            "Pinned WebView2 version is {0}" -f $Script:WebView2LatestVersion | Write-Verbose
        }
        catch {
            "Could not determine the pinned WebView2 version because of an error: {0}" -f $_ | Write-Warning
            $Script:WebView2UpdateChecked = $true
        }

        if ($Script:WebView2UpdateChecked) {
            return $false
        }

        $ReturnValue = $false
        if ((Test-Path $Script:WebView2WinFormsPath -PathType Leaf) -and (Test-Path $Script:WebView2CorePath -PathType Leaf) -and (Test-Path $Script:WebView2LoaderPath -PathType Leaf)) {

            try {

                [System.Version]$WebView2CoreVersion = (Get-Item $Script:WebView2CorePath).VersionInfo.ProductVersion
                "Current WebView2 Core version is {0}" -f $WebView2CoreVersion | Write-Verbose
                [System.Version]$WebView2WinFormsVersion = (Get-Item $Script:WebView2WinFormsPath).VersionInfo.ProductVersion
                "Current WebView2 WinForms version is {0}" -f $WebView2WinFormsVersion | Write-Verbose
                [System.Version]$Webview2LoaderVersion = (Get-Item $Script:WebView2LoaderPath).VersionInfo.ProductVersion
                "Current WebView2 Loader version is {0}" -f $Webview2LoaderVersion | Write-Verbose

                if ($IncludeWpf.IsPresent) {
                    [System.Version]$Webview2WpfVersion = (Get-Item $Script:WebView2WpfPath).VersionInfo.ProductVersion
                    "Current WebView2 Wpf version is {0}" -f $Webview2WpfVersion | Write-Verbose
                }
                else {
                    $Webview2WpfVersion = [System.Version]"9999.9999.9999.9999"
                }

                if ($Script:WebView2LatestVersion -gt $WebView2CoreVersion -or $Script:WebView2LatestVersion -gt $WebView2WinFormsVersion -or $Script:WebView2LatestVersion -gt $Webview2LoaderVersion -or $Script:WebView2LatestVersion -gt $Webview2WpfVersion ) {
                    "One or more WebView2 assemblies are not up to date! Will try to update WebView2!" | Write-Warning
                    $ReturnValue = $true
                }
                else {
                    "WebView2 assemblies are up to date!" | Write-Verbose
                }
            }
            catch {
                "Unable to compare the installed WebView2 assemblies against the pinned version. An update check will be attempted again when the module is reloaded." | Write-Warning
                $ReturnValue = $false
            }
        }
        $Script:WebView2UpdateChecked = $true
        return $ReturnValue

    }
    catch {
        Write-Host "Error in Get-WebView2RuntimeVersion: $_" -ForegroundColor Red
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
