function ConvertTo-ModuleVersionInfo {
    [CmdletBinding()]
    param(
        [string]$Version
    )

    # The obvious type for this job would be [System.Management.Automation.SemanticVersion], and it
    # is the wrong one: SemVer allows at most three numeric components, while this module ships four
    # component builds such as 2026.7.9.9. SemanticVersion::TryParse rejects exactly the versions
    # that are already installed on people's machines, so the parse is done by hand instead: split
    # the string where SemVer says the prerelease tag begins, and hand the numeric part to
    # [System.Version], which takes two to four components and behaves the same on Windows
    # PowerShell 5.1 and PowerShell 7.
    if ([string]::IsNullOrWhiteSpace($Version)) {
        return $null
    }

    $RemainingVersion = $Version.Trim()

    # Build metadata carries no precedence at all under SemVer, so it is removed before anything
    # else and never influences a comparison.
    $BuildMetadataIndex = $RemainingVersion.IndexOf("+")
    if ($BuildMetadataIndex -ge 0) {
        $RemainingVersion = $RemainingVersion.Substring(0, $BuildMetadataIndex)
    }

    $PrereleaseIndex = $RemainingVersion.IndexOf("-")
    if ($PrereleaseIndex -ge 0) {
        $NumericPart = $RemainingVersion.Substring(0, $PrereleaseIndex)
        $PrereleaseTag = $RemainingVersion.Substring($PrereleaseIndex + 1)
    }
    else {
        $NumericPart = $RemainingVersion
        $PrereleaseTag = $null
    }

    $ParsedVersion = $null
    if (-not [System.Version]::TryParse($NumericPart, [ref]$ParsedVersion)) {
        "{0} - '{1}' is not a version this module can compare." -f $MyInvocation.MyCommand, $Version | Write-Verbose
        return $null
    }

    return [PSCustomObject]@{
        Version       = $ParsedVersion
        PrereleaseTag = $PrereleaseTag
        IsPrerelease  = -not [string]::IsNullOrEmpty($PrereleaseTag)
        Original      = $Version
    }
}
