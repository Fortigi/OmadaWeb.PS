function Get-OmadaLegacyCookieCacheFile {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($Script:LegacyCookieCachePath) -or -not (Test-Path $Script:LegacyCookieCachePath -PathType Container)) {
        return @()
    }

    # Legacy cookie caches are named after an MD5 hash of the session key, with no extension, and sit
    # among everything else in %TEMP%. Matching on the name alone is not enough to be sure a file is
    # ours, so the contents are checked as well before it is reported (and possibly removed).
    return @(Get-ChildItem -Path $Script:LegacyCookieCachePath -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "^[0-9a-f]{32}$" } |
            Where-Object { Test-OmadaCookieCacheFile -Path $_.FullName })
}
