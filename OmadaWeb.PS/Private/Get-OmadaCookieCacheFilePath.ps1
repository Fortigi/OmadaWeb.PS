function Get-OmadaCookieCacheFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SessionKey
    )

    $FileName = Get-OmadaShortHash -Value $SessionKey
    $CacheFilePath = Join-Path $Script:CookieCachePath -ChildPath $FileName

    if (-not (Test-Path $Script:CookieCachePath -PathType Container)) {
        $null = New-Item -Path $Script:CookieCachePath -ItemType Directory -Force
    }

    # The encrypted cookie cache used to be written straight into %TEMP%, which is a surprising home
    # for long-lived authentication material and is outside the documented %LOCALAPPDATA%\OmadaWeb.PS
    # root. A cache left there by an earlier module version is moved across on first use, so upgrading
    # neither forces everyone to re-authenticate nor leaves a usable session cookie behind in %TEMP%.
    if (-not (Test-Path $CacheFilePath -PathType Leaf) -and -not [string]::IsNullOrWhiteSpace($Script:LegacyCookieCachePath)) {
        $LegacyFilePath = Join-Path $Script:LegacyCookieCachePath -ChildPath $FileName
        if ((Test-Path $LegacyFilePath -PathType Leaf) -and $LegacyFilePath -ne $CacheFilePath) {
            try {
                Move-Item -Path $LegacyFilePath -Destination $CacheFilePath -Force -ErrorAction Stop
                "{0} - Migrated cookie cache '{1}' to '{2}'" -f $MyInvocation.MyCommand, $LegacyFilePath, $CacheFilePath | Write-Verbose
            }
            catch {
                # Fall back to a clean cache (the caller simply re-authenticates) rather than keep
                # reading from %TEMP%, and make a best-effort attempt not to leave the old copy behind.
                "{0} - Could not migrate cookie cache '{1}': {2}" -f $MyInvocation.MyCommand, $LegacyFilePath, $_.Exception.Message | Write-Verbose
                Remove-Item -Path $LegacyFilePath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return $CacheFilePath
}
