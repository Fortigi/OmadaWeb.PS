function Get-WebView2Cookies {
    <#
    .SYNOPSIS
    Gets cookies from the WebView2 browser.

    .PARAMETER Url
    The URL to get cookies for (defaults to current page).
    #>

    [CmdletBinding()]
    param(
        [string]$Url,
        $Cookies
    )

    try {
        $Uri = [System.Uri]::new($Url)
        $Output = [pscustomobject]@{}

        $Match = $cookies | Where-Object { $null -ne $_.Domain -and [System.Uri]::new($_.Domain).Host.ToLower() -eq $Uri.Host.ToLower() }
        if (-not $Match -or $Match.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No cookies for '$($Uri.Host)' found.", "No cookies", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            Set-WebView2Status 'No matching cookies'
            return $Output
        }

        $Exported = $false
        $Match | ForEach-Object {

            if ($_.name -eq 'oisauthtoken') {
                Write-Host "Found oisauthtoken" -ForegroundColor Green

                $exp = $_.Expires
                $Output = [pscustomobject]@{
                    name     = $_.Name
                    value    = $_.Value
                    domain   = $_.Domain
                    path     = $_.Path
                    expires  = $exp
                    httpOnly = $_.IsHttpOnly
                    secure   = $_.IsSecure
                    sameSite = $_.SameSite.ToString()
                }
                Set-WebView2Status "Cookie retrieved"
                $Exported = $true
                break
            }
        }
        if ($Exported) {
            "Cookie export complete. Exiting in 2 seconds..." | Write-Host -ForegroundColor Green
            Start-Sleep -Seconds 2
            $form.Close()
        }
        return $Output
    }
    catch {
        "Failed to get WebView2 cookies: {0}" -f $_.Exception.Message | Write-Error
        throw
    }
}