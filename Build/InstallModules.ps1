try {
    "Validate Modules" | Write-Host
    $Modules = Get-Module -ListAvailable
    if ("Pester" -notin $Modules.Name) {
        "Install Pester" | Write-Host
        Install-Module -Name Pester -Scope CurrentUser -Force
    }
    if ("psake" -notin $Modules.Name) {
        "Install psake" | Write-Host
        Install-Module -Name psake -Scope CurrentUser -Force
    }
    if ("PSDeploy" -notin $Modules.Name) {
        "Install PSDeploy" | Write-Host
        Install-Module -Name PSDeploy -Scope CurrentUser -Force
    }
    if ("PSScriptAnalyzer" -notin $Modules.Name) {
        "Install PSScriptAnalyzer" | Write-Host
        Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
    }
    "Register NuGet PackageSource" | Write-Host
    Register-PackageSource -Name NuGet -Location "https://api.NuGet.org/v3/index.json" -ProviderName NuGet -Force
}
catch {
    Write-Error "Failed to validate modules: $_"
    exit 1
}
