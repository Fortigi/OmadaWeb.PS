function ConvertFrom-JavaScriptResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]$Result
    )

    # CoreWebView2.ExecuteScriptAsync hands back the script result JSON encoded, so a string comes
    # in quoted and with its quotes, backslashes and control characters escaped. Stripping the
    # quotes textually would corrupt any value that legitimately contains one, so decode it.
    # A script that returned undefined or nothing at all yields the literal "null" or an empty
    # string, neither of which is a value the callers can use.
    if ([System.String]::IsNullOrWhiteSpace($Result)) {
        return $null
    }

    try {
        return ($Result | ConvertFrom-Json)
    }
    catch {
        "ConvertFrom-JavaScriptResult - Could not decode script result: {0}" -f $PSItem.Exception.Message | Write-Verbose
        return $null
    }
}
