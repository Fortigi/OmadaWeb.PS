function Test-OmadaCookieCacheFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        $Item = Get-Item -Path $Path -Force -ErrorAction Stop
        # A cache holds one serialized SecureString; anything substantially larger is not ours and is
        # not worth reading into memory just to find that out.
        if ($Item.Length -gt 1MB) {
            return $false
        }

        $Content = Get-Content -Path $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return $false
        }

        # Export-Clixml of a SecureString produces an <Objs> document with a single <SS> element.
        return ($Content -match "<Objs\b" -and $Content -match "<SS>")
    }
    catch {
        return $false
    }
}
