function Compare-ModuleVersion {
    [CmdletBinding()]
    param(
        [string]$ReferenceVersion,
        [string]$DifferenceVersion
    )

    # Returns -1, 0 or 1 the way a comparer does, and $null when either side cannot be parsed. The
    # $null is the point: the caller that cannot compare has to say so on the verbose stream and
    # move on, rather than throw the way the [System.Version] cast this replaces did.
    $Reference = ConvertTo-ModuleVersionInfo -Version $ReferenceVersion
    $Difference = ConvertTo-ModuleVersionInfo -Version $DifferenceVersion

    if ($null -eq $Reference -or $null -eq $Difference) {
        return $null
    }

    if ($Reference.Version -lt $Difference.Version) {
        return -1
    }

    if ($Reference.Version -gt $Difference.Version) {
        return 1
    }

    # Same numeric version, so SemVer precedence decides: a tagged version sorts below the untagged
    # release of the same number. 2026.9.1-nightly74 is what comes before 2026.9.1, never after it.
    if ($Reference.PrereleaseTag -eq $Difference.PrereleaseTag) {
        return 0
    }

    if (-not $Reference.IsPrerelease) {
        return 1
    }

    if (-not $Difference.IsPrerelease) {
        return -1
    }

    # Two tags on the same version. Strict SemVer would compare "nightly9" and "nightly74" as text,
    # because neither is a purely numeric identifier, and would then declare nightly9 the newer of
    # the two. This module's tags are a word followed by a build counter, so text order is the wrong
    # answer for every nightly user it would reach. When both tags share a prefix and differ only in
    # a trailing run of digits, those digits are compared as numbers; anything else falls back to
    # the ordinal comparison SemVer prescribes.
    $TagPattern = "^(?<Prefix>.*?)(?<Number>\d+)$"
    $ReferenceMatch = [regex]::Match($Reference.PrereleaseTag, $TagPattern)
    $DifferenceMatch = [regex]::Match($Difference.PrereleaseTag, $TagPattern)

    if ($ReferenceMatch.Success -and $DifferenceMatch.Success -and $ReferenceMatch.Groups["Prefix"].Value -eq $DifferenceMatch.Groups["Prefix"].Value) {
        $ReferenceNumber = [System.Numerics.BigInteger]::Parse($ReferenceMatch.Groups["Number"].Value)
        $DifferenceNumber = [System.Numerics.BigInteger]::Parse($DifferenceMatch.Groups["Number"].Value)

        if ($ReferenceNumber -lt $DifferenceNumber) {
            return -1
        }

        if ($ReferenceNumber -gt $DifferenceNumber) {
            return 1
        }

        return 0
    }

    $OrdinalResult = [string]::CompareOrdinal($Reference.PrereleaseTag, $Difference.PrereleaseTag)
    if ($OrdinalResult -lt 0) {
        return -1
    }

    if ($OrdinalResult -gt 0) {
        return 1
    }

    return 0
}
