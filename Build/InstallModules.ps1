# The one place the build's PowerShell modules are declared. Build/build.ps1 runs this script rather
# than keeping a list of its own, and every workflow calls it before anything else.
#
# Pester, PSComplexity and PSMutant are pinned to an exact version. A floor resolves to whatever is
# newest on the gallery on the day the runner installs it, and these three decide whether a build
# passes: PSComplexity's metric has moved for unchanged source between releases, a committed
# complexity baseline records the metric version it was taken with and refuses to be compared across
# a change to it, and a mutation score is only comparable with the previous one when the same Pester
# and the same PSMutant produced both. Upgrading any of them is a deliberate change in a pull request,
# where its effect on the numbers is visible.
#
# PSComplexity and PSMutant require PowerShell 7.0 or later and are skipped under Windows PowerShell
# 5.1; the tasks that use them skip themselves there too.
[CmdletBinding()]
param()

$PinnedModules = @(
    # 6.2.0 still ships a net462 build and declares PowerShell 5.1 as its minimum, so the
    # Windows PowerShell leg of PR validation keeps running the same Pester as the pwsh leg.
    @{ Name = 'Pester'; RequiredVersion = '6.2.0'; SkipPublisherCheck = $true; MinimumPowerShell = 5 }
    @{ Name = 'PSComplexity'; RequiredVersion = '0.5.1'; SkipPublisherCheck = $false; MinimumPowerShell = 7 }
    # PSMutant deliberately does not declare Pester as a required module; it runs under the Pester
    # already loaded in the session (5.2.0 or later), which is the pinned one above.
    @{ Name = 'PSMutant'; RequiredVersion = '0.5.0'; SkipPublisherCheck = $false; MinimumPowerShell = 7 }
)

try {
    "Validate Modules" | Write-Host
    $Modules = Get-Module -ListAvailable

    foreach ($PinnedModule in $PinnedModules) {
        if ($PSVersionTable.PSVersion.Major -lt $PinnedModule.MinimumPowerShell) {
            "Skip {0}: requires PowerShell {1}.0+ (running {2})" -f $PinnedModule.Name, $PinnedModule.MinimumPowerShell, $PSVersionTable.PSVersion | Write-Host
            continue
        }
        if ($Modules | Where-Object { $_.Name -eq $PinnedModule.Name -and $_.Version -eq [version]$PinnedModule.RequiredVersion }) {
            continue
        }
        "Install {0} {1}" -f $PinnedModule.Name, $PinnedModule.RequiredVersion | Write-Host
        $InstallParameters = @{
            Name            = $PinnedModule.Name
            RequiredVersion = $PinnedModule.RequiredVersion
            Repository      = 'PSGallery'
            Scope           = 'CurrentUser'
            Force           = $true
        }
        if ($PinnedModule.SkipPublisherCheck) {
            $InstallParameters.SkipPublisherCheck = $true
        }
        Install-Module @InstallParameters
    }

    if ("psake" -notin $Modules.Name) {
        "Install psake" | Write-Host
        Install-Module -Name psake -Repository PSGallery -Scope CurrentUser -Force
    }
    if ("PSDeploy" -notin $Modules.Name) {
        "Install PSDeploy" | Write-Host
        Install-Module -Name PSDeploy -Repository PSGallery -Scope CurrentUser -Force
    }
    # 1.22.0+ is required for the PSAvoidAssignmentToAutomaticVariable suppression used in the module.
    if (-not ($Modules | Where-Object { $_.Name -eq 'PSScriptAnalyzer' -and $_.Version -ge '1.22.0' })) {
        "Install PSScriptAnalyzer" | Write-Host
        Install-Module -Name PSScriptAnalyzer -Repository PSGallery -Scope CurrentUser -Force -SkipPublisherCheck
    }
    if (-not ($Modules | Where-Object { $_.Name -eq 'ThreadJob' }) -and -not (Get-Command -Name Start-ThreadJob -ErrorAction SilentlyContinue)) {
        "Install ThreadJob" | Write-Host
        Install-Module -Name ThreadJob -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
    }
    "Register NuGet PackageSource" | Write-Host
    Register-PackageSource -Name NuGet -Location "https://api.NuGet.org/v3/index.json" -ProviderName NuGet -Force
}
catch {
    Write-Error "Failed to validate modules: $_"
    exit 1
}
