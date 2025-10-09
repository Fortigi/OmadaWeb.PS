function Invoke-DataFromWebView2 {
    [CmdletBinding()]
    param(
        [string]$EdgeProfile = "Default",
        [switch]$InPrivate
    )

    "{0} - Opening WebView2 to retrieve authentication cookie" -f $MyInvocation.MyCommand | Write-Host

    if (!(Install-WebView2)) {
        "WebView2 Runtime could not be installed! Cannot continue." | Write-Error -ErrorAction "Stop"
    }
    $Script:LoginRetryCount = 0

    Add-ReflectionAssembly -Object $Script:WebView2CorePath
    Add-ReflectionAssembly -Object $Script:WebView2WinFormsPath
    Add-ReflectionAssembly -Object "System.Drawing" -Type LoadWithPartialName
    Add-ReflectionAssembly -Object "System.Windows.Forms" -Type LoadWithPartialName
    do {
        try {

            if ($null -eq $Script:OmadaWebAuthCookie -or ($Script:OmadaWebAuthCookie -is [PSCustomObject] -and ($Script:OmadaWebAuthCookie.PsObject.Properties | Measure-Object).Count -eq 0)) {
                if ($Script:LoginRetryCount -eq 0) {
                    try {
                        Start-WebView2Login -EdgeProfile $EdgeProfile -InPrivate:$InPrivate
                    }
                    catch {
                        throw $_
                    }
                }
                elseif ($Script:LoginRetryCount -gt 3) {
                    "`nLogin retry count exceeded! Please check your credentials as no cookie could be retrieved!" | Write-Error -ErrorAction "Stop" -Category AuthenticationError
                }
                else {
                    "WebView2 window seems to be closed before authentication was completed. Re-open WebView2!" | Write-Host -ForegroundColor Yellow
                    "`n{0} - Login retry count: {1}" -f $MyInvocation.MyCommand, $Script:LoginRetryCount | Write-Verbose
                    try {
                        Start-WebView2Login -EdgeProfile $EdgeProfile -InPrivate:$InPrivate
                    }
                    catch {
                        throw $_
                    }
                }
            }
        }
        catch {
            throw $_
        }
    }
    until(($null -ne $Script:OmadaWebAuthCookie -and ($Script:OmadaWebAuthCookie -is [PSCustomObject] -and ($Script:OmadaWebAuthCookie.PsObject.Properties | Measure-Object).Count -gt 0)) -or $Script:LoginRetryCount -gt 3)

    if ($null -ne $Script:OmadaWebAuthCookie -and ($Script:OmadaWebAuthCookie -is [PSCustomObject] -and ($Script:OmadaWebAuthCookie.PsObject.Properties | Measure-Object).Count -gt 0)) {
        $Script:LoginRetryCount = 0
    }
    else {
        "Could not authenticate to '{0}" -f $Script:OmadaWebBaseUrl | Write-Error -ErrorAction "Stop"
    }
}