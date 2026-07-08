try {
    "Validate Modules" | Write-Host
    $Modules = Get-Module -ListAvailable
    if (-not ($Modules | Where-Object { $_.Name -eq 'Pester' -and $_.Version -ge '5.0' })) {
        "Install Pester" | Write-Host
        Install-Module -Name Pester -Scope CurrentUser -Force -SkipPublisherCheck
    }
    if ("psake" -notin $Modules.Name) {
        "Install psake" | Write-Host
        Install-Module -Name psake -Scope CurrentUser -Force
    }
    if ("PSDeploy" -notin $Modules.Name) {
        "Install PSDeploy" | Write-Host
        Install-Module -Name PSDeploy -Scope CurrentUser -Force
    }
    if (-not ($Modules | Where-Object { $_.Name -eq 'PSScriptAnalyzer' -and $_.Version -ge '1.22.0' })) {
        "Install PSScriptAnalyzer" | Write-Host
        Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck
    }
    if (-not (Get-Command -Name Start-ThreadJob -ErrorAction SilentlyContinue)) {
        "Install ThreadJob" | Write-Host
        Install-Module -Name ThreadJob -Scope CurrentUser -Force
    }
    "Register NuGet PackageSource" | Write-Host
    Register-PackageSource -Name NuGet -Location "https://api.NuGet.org/v3/index.json" -ProviderName NuGet -Force
}
catch {
    Write-Error "Failed to validate modules: $_"
    exit 1
}
