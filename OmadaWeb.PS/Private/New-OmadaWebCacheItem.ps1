function New-OmadaWebCacheItem {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingVerbs', '', Justification = 'Creates an in-memory descriptor object, it does not change any state')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Scope,

        [Parameter(Mandatory)]
        [string]$Artefact,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet("Directory", "File", "Memory")]
        [string]$ItemType,

        [Parameter(Mandatory)]
        [string]$Protection,

        # A set of individual files that together make up one artefact, used for the loose cookie
        # caches left in %TEMP%: they are reported as a single artefact living in $Path, rather than
        # one row per file, so the output stays readable when a machine has collected a lot of them.
        # Only these files are removed - never the folder they sit in, which is not ours.
        [System.IO.FileInfo[]]$File
    )

    $Exists = $false
    $ItemCount = 0
    $SizeBytes = 0
    # What removal actually operates on, which is not always the displayed path.
    $TargetPath = @($Path)

    if ($PSBoundParameters.ContainsKey("File")) {
        $Files = @($File)
        $TargetPath = @($Files | ForEach-Object { $_.FullName })
        $Exists = $Files.Count -gt 0
        $ItemCount = $Files.Count
    }
    elseif ($ItemType -eq "File" -and (Test-Path $Path -PathType Leaf)) {
        $Exists = $true
        $ItemCount = 1
        $Files = @(Get-Item -Path $Path -Force)
    }
    elseif ($ItemType -eq "Directory" -and (Test-Path $Path -PathType Container)) {
        $Exists = $true
        $Files = @(Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue)
        $ItemCount = $Files.Count
    }
    else {
        $Files = @()
    }

    # Over an empty collection Measure-Object emits nothing at all rather than an object whose Sum is
    # $null, so $Measured itself has to be tested before its Sum is read - otherwise the empty-cache
    # case, which is the one this guard exists for, faults instead of reporting a zero.
    $Measured = $Files | Measure-Object -Property Length -Sum
    if ($null -ne $Measured -and $null -ne $Measured.Sum) {
        $SizeBytes = $Measured.Sum
    }

    return [PSCustomObject]@{
        Scope      = $Scope
        Artefact   = $Artefact
        Path       = $Path
        TargetPath = $TargetPath
        ItemType   = $ItemType
        Protection = $Protection
        Exists     = $Exists
        ItemCount  = $ItemCount
        SizeBytes  = $SizeBytes
        Removed    = $false
    }
}
