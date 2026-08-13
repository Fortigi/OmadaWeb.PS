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
        [string]$Protection
    )

    $Exists = $false
    $ItemCount = 0
    $SizeBytes = 0

    if ($ItemType -eq "File" -and (Test-Path $Path -PathType Leaf)) {
        $Exists = $true
        $ItemCount = 1
        $SizeBytes = (Get-Item -Path $Path -Force).Length
    }
    elseif ($ItemType -eq "Directory" -and (Test-Path $Path -PathType Container)) {
        $Exists = $true
        $Files = @(Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue)
        $ItemCount = $Files.Count
        # Measure-Object returns $null for Sum over an empty collection, which would surface as a
        # blank column instead of a zero.
        $Measured = $Files | Measure-Object -Property Length -Sum
        if ($null -ne $Measured.Sum) {
            $SizeBytes = $Measured.Sum
        }
    }

    return [PSCustomObject]@{
        Scope      = $Scope
        Artefact   = $Artefact
        Path       = $Path
        ItemType   = $ItemType
        Protection = $Protection
        Exists     = $Exists
        ItemCount  = $ItemCount
        SizeBytes  = $SizeBytes
        Removed    = $false
    }
}
