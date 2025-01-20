
function Get-NuGetPackage {
    [CmdletBinding(DefaultParameterSetName = 'RequiredVersion')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'Matches', Justification = 'It is only cleared to avoid using the same variable from a previous loop run')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Dependency', Justification = 'It is left there to be used in a later release, it is an private function so no issue for the end user.')]
    PARAM(
        [parameter(Mandatory = $true, ParameterSetName = 'RequiredVersion')]
        [parameter(Mandatory = $true, ParameterSetName = 'VersionRange')]
        [string]$PackageName,
        [parameter(Mandatory = $false, ParameterSetName = 'RequiredVersion')]
        [parameter(Mandatory = $false, ParameterSetName = 'VersionRange')]
        [string]$TargetFramework = '.NETFramework4.6.2',
        [parameter(Mandatory = $false, ParameterSetName = 'RequiredVersion')]
        [System.Version]$RequiredVersion,
        [parameter(Mandatory = $false, ParameterSetName = 'VersionRange')]
        [System.Version]$MinimumVersion,
        [parameter(Mandatory = $false, ParameterSetName = 'VersionRange')]
        [System.Version]$MaximumVersion,
        [switch]$ExcludeDependencies
    )

    $NuGetIndexUri = "https://api.nuget.org/v3/index.json"

    $BaseReturnObjects = @()
    function GetPackage {
        [CmdletBinding(DefaultParameterSetName = 'RequiredVersion')]
        PARAM(
            [parameter(Mandatory = $true, ParameterSetName = 'RequiredVersion')]
            [parameter(Mandatory = $true, ParameterSetName = 'VersionRange')]
            [string]$PackageName,
            [parameter(Mandatory = $false, ParameterSetName = 'RequiredVersion')]
            [parameter(Mandatory = $false, ParameterSetName = 'VersionRange')]
            [string]$TargetFramework = '.NETFramework4.6.2',
            [parameter(Mandatory = $false, ParameterSetName = 'RequiredVersion')]
            [System.Version]$RequiredVersion,
            [parameter(Mandatory = $false, ParameterSetName = 'VersionRange')]
            [System.Version]$MinimumVersion,
            [parameter(Mandatory = $false, ParameterSetName = 'VersionRange')]
            [System.Version]$MaximumVersion,
            [switch]$Dependency,
            [switch]$ExcludeDependencies
        )

        $ReturnObjects = @()
        try {
            $ReturnObject = @{
                PackageName           = $PackageName
                TargetFramework       = $TargetFramework
                PackageTempPath       = $null
                PackageEntries        = @()
                Dependencies          = @()
            }

            "Downloading '{0}', retrieve NuGetIndex from '{1}'" -f $PackageName, $NuGetIndexUri | Write-Verbose
            $NuGetIndex = Invoke-RestMethod -Uri $NuGetIndexUri

            $PackageSearchUri = ($NuGetIndex.resources | Where-Object '@type' -EQ 'SearchQueryService' | Select-Object -First 1).'@id'

            $PackageSearchUri = $PackageSearchUri, $PackageName -join "?q="

            "PackageSearchUri: {0}" -f $PackageSearchUri | Write-Verbose
            $SearchResult = Invoke-RestMethod -Uri $PackageSearchUri
            $PackageSource = ($SearchResult.data | Where-Object title -EQ $PackageName).'@id'

            "PackageSource: {0}" -f $PackageSource | Write-Verbose
            $Package = Invoke-RestMethod -Uri $PackageSource

            $Package = $Package.items | Select-Object -Last 1

            if ($PSCmdlet.ParameterSetName -eq 'RequiredVersion' -and $null -ne $RequiredVersion -and $RequiredVersion.Major -gt -1) {
                "Required version '{0}''" -f $RequiredVersion.ToString() | Write-Verbose
                $PackageFilter = $RequiredVersion.ToString()
                $Id = $Package.items.'@id' | Where-Object { $_.Split("/")[-1] -like "$PackageFilter*" } | Select-Object -Last 1
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'VersionRange' -and (($null -ne $MinimumVersion -and $MinimumVersion.Major -gt -1) -or ($null -ne $MaximumVersion -and $MaximumVersion.Major -gt -1))) {
                if ($null -eq $MinimumVersion -or $MinimumVersion.Major -lt 0) {
                    "Minimum version not valid" | Write-Verbose
                    [System.Version]$MinimumVersion = "0.0.0"
                }
                if ($null -eq $MaximumVersion -or $MinimumVersion.Major -lt 0) {
                    "Minimum version not valid" | Write-Verbose
                    [System.Version]$MaximumVersion = $MinimumVersion
                }
                "Minimum version: '{0}', maximum version: '{1}'" -f $MinimumVersion.ToString(), $MaximumVersion.ToString() | Write-Verbose

                [regex]$VersionRegex = '.*/([\d.]+)\.json$'
                $ValidPackages = @()
                $Package.items.'@id' | ForEach-Object {
                    $Version = $VersionRegex.Match($_)
                    if ($Version.Success -and [System.Version]$Version.Groups[1].Value -ge $MinimumVersion -and [System.Version]$Version.Groups[1].Value -le $MaximumVersion) {
                        "Valid package found!" | Write-Verbose
                        $ValidPackages += $_
                    }
                }
                $Id = $ValidPackages | Select-Object -Last 1
            }
            else {
                $Id = $Package.items.'@id' | Select-Object -Last 1
            }
            if ($null -eq $Id) {
                "Could not find any valid package for '{0}'" -f $PackageName | Write-Error -ErrorAction "Stop"
            }
            "Package Id: {0}" -f $Id | Write-Verbose
            $PackageVersion = Invoke-RestMethod -Uri $Id
            $PackageContent = Invoke-DownloadFile -DownloadUrl $PackageVersion.packageContent

            $ReturnObject.PackageTempPath = Expand-DownloadFile -FilePath $PackageContent


            "catalogEntry: {0}" -f $PackageVersion.catalogEntry | Write-Verbose
            $PackageCatalogInfo = Invoke-RestMethod -Uri $PackageVersion.catalogEntry

            $PackageCatalogInfo.packageEntries | Where-Object { $_.fullName -like "lib/*/*.dll" } | ForEach-Object {
                $ReturnObject.PackageEntries += Join-Path $($ReturnObject.PackageTempPath).FullName -ChildPath $_.fullName.Replace("/", "\")
            }
            if (!$ExcludeDependencies) {

                $Dependencies = $PackageCatalogInfo.dependencyGroups | Where-Object { $_.targetframework -like "$($ReturnObject.TargetFramework)" } | Select-Object -Last 1
                $ReturnObject.Dependencies = $Dependencies.dependencies
                :Dependency foreach ($Package in $ReturnObject.Dependencies) {
                    if ($null -eq $Package) { continue Dependency}
                    "Retrieve dependency '{0}'" -f $Package.Id | Write-Verbose
                    #https://learn.microsoft.com/en-us/nuget/concepts/package-versioning?tabs=semver20sort
                    $Matches = $null
                    [System.Version]$MinimumVersion = "0.0.0"
                    [System.Version]$MaximumVersion = "99.99.9999"
                    if ($Package.range -match "^([\d.])+$") {
                        #MinimumVersionInclusive
                        $Type = "Range"
                        [System.Version]$MinimumVersion = $Matches[1]
                        [System.Version]$MaximumVersion = "99.99.9999"
                    }
                    elseif ($Package.range -match "^\[([\d.]+),\W?\)" ) {
                        #MinimumVersionInclusive
                        $Type = "Range"

                        [System.Version]$MinimumVersion = $Matches[1]
                        [System.Version]$MaximumVersion = "99.99.9999"
                    }
                    elseif ($Package.range -match "^\(([\d.]+),\W?\)" ) {
                        #MinimumVersionExclusive
                        $Type = "Range"
                        [System.Version]$MinimumVersion = $Matches[1]
                        [System.Version]$MaximumVersion = "99.99.9999"
                        $MinimumVersion.Build++
                    }
                    elseif ($Package.range -match "^\[([\d.]+)W?\]" ) {
                        #ExactVersion
                        $Type = "Range"
                        [System.Version]$RequiredVersion = $Matches[1]
                    }
                    elseif ($Package.range -match "^\(,\W?([\d.]+)\]" ) {
                        #MaxVersionInclusive
                        $Type = "Range"
                        [System.Version]$MinimumVersion = "0.0.0"
                        [System.Version]$MaximumVersion = $Matches[1]
                    }
                    elseif ($Package.range -match "^\(,\W?([\d.]+)\)" ) {
                        #MaxVersionExclusive
                        $Type = "Range"
                        [System.Version]$MinimumVersion = "0.0.0"
                        [System.Version]$MaximumVersion = $Matches[1]

                        "Build", "Minor", "Major" | ForEach-Object {
                            if ($MaximumVersion.Minor -le 0) {
                                [System.Version]$MaximumVersion = "0.0.0"
                            }
                            elseif ($MaximumVersion.Minor -eq 0 -and $MaximumVersion.Build -eq 0) {
                                [System.Version]$MaximumVersion = "{0}.99.99999" - $MaximumVersion.Major--
                            }
                            elseif ($MaximumVersion.Minor -eq 0 -and $MaximumVersion.Build -gt 0) {
                                [System.Version]$MaximumVersion = "{0}.{1}.{2}" - $MaximumVersion.Major, $MaximumVersion.Minor, $MaximumVersion.Build--
                            }
                            else {
                                [System.Version]$MaximumVersion = "{0}.{1}.99999" - $MaximumVersion.Major, $MaximumVersion.Minor--
                            }
                        }
                    }
                    elseif ($Package.range -match "^\[([\d.]+),\W?([\d.]+)\]" ) {
                        #ExactVersionRangeInclusive
                        $Type = "Range"
                        [System.Version]$MaximumVersion = $Matches[1]
                        [System.Version]$MinimumVersion = $Matches[2]
                    }
                    elseif ($Package.range -match "^\(([\d.]+),\W?([\d.]+)\)" ) {
                        #ExactVersionRangeExclusive
                        $Type = "Range"
                        [System.Version]$MaximumVersion = $Matches[1]
                        [System.Version]$MinimumVersion = $Matches[2]
                        $MinimumVersion.Build++

                        "Build", "Minor", "Major" | ForEach-Object {
                            if ($MaximumVersion.Minor -le 0) {
                                [System.Version]$MaximumVersion = "0.0.0"
                            }
                            elseif ($MaximumVersion.Minor -eq 0 -and $MaximumVersion.Build -eq 0) {
                                [System.Version]$MaximumVersion = "{0}.99.9999" - $MaximumVersion.Major--
                            }
                            elseif ($MaximumVersion.Minor -eq 0 -and $MaximumVersion.Build -gt 0) {
                                [System.Version]$MaximumVersion = "{0}.{1}.{2}" - $MaximumVersion.Major, $MaximumVersion.Minor, $MaximumVersion.Build--
                            }
                            else {
                                [System.Version]$MaximumVersion = "{0}.{1}.9999" - $MaximumVersion.Major, $MaximumVersion.Minor--
                            }
                        }
                    }
                    elseif ($Package.range -match "^\[([\d.]+),\W?([\d.]+)\)" ) {
                        #MixedInclusiveMinimumExclusiveMaximum
                        $Type = "Range"
                        [System.Version]$MaximumVersion = $Matches[1]
                        [System.Version]$MinimumVersion = $Matches[2]

                        "Build", "Minor", "Major" | ForEach-Object {
                            if ($MaximumVersion.Minor -le 0) {
                                [System.Version]$MaximumVersion = "0.0.0"
                            }
                            elseif ($MaximumVersion.Minor -eq 0 -and $MaximumVersion.Build -eq 0) {
                                [System.Version]$MaximumVersion = "{0}.99.9990" -f $MaximumVersion.Major--
                            }
                            elseif ($MaximumVersion.Minor -eq 0 -and $MaximumVersion.Build -gt 0) {
                                [System.Version]$MaximumVersion = "{0}.{1}.{2}" -f $MaximumVersion.Major, $MaximumVersion.Minor, $MaximumVersion.Build--
                            }
                            else {
                                [System.Version]$MaximumVersion = "{0}.{1}.9990" -f $MaximumVersion.Major, $MaximumVersion.Minor--
                            }
                        }
                    }
                    else {
                        "Invalid range '{0}'" -f $Package.range | Write-Error -ErrorAction "Stop"
                    }
                    switch ($Type) {
                        "Range" {
                            "MinimumVersion: '{0}', MaximumVersion: '{1}'" -f $MinimumVersion.ToString(), $MaximumVersion.ToString() | Write-Verbose
                            $ReturnObjects += GetPackage -PackageName $Package.Id -TargetFramework $($ReturnObject.TargetFramework) -MinimumVersion $MinimumVersion -MaximumVersion $MaximumVersion -Dependency
                        }
                        "Exact" {
                            "Exact version '{0}'" -f $RequiredVersion.ToString() | Write-Verbose
                            $ReturnObjects += GetPackage -PackageName $Package.Id -TargetFramework $($ReturnObject.TargetFramework) -RequiredVersion $DependencyRequiredVersion -Dependency
                        }
                        default {
                            "Invalid range '{0}'" -f $Package.range | Write-Error -ErrorAction "Stop"
                        }
                    }
                }
            }
            $ReturnObjects += $ReturnObject
        }
        catch {
            $_
        }
        return $ReturnObjects
    }

    if ($PSCmdlet.ParameterSetName -eq 'RequiredVersion') {
        $BaseReturnObjects = GetPackage -PackageName $PackageName -TargetFramework $TargetFramework -RequiredVersion $RequiredVersion -ExcludeDependencies:$ExcludeDependencies
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'VersionRange') {
        $BaseReturnObjects = GetPackage -PackageName $PackageName -TargetFramework $TargetFramework -MinimumVersion $MinimumVersion -MaximumVersion $MaximumVersion -ExcludeDependencies:$ExcludeDependencies
    }
    else {
        $BaseReturnObjects = GetPackage -PackageName $PackageName -TargetFramework $TargetFramework
    }

    return $BaseReturnObjects
}