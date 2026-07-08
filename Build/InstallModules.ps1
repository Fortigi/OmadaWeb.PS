try {
    "Validate Modules" | Write-Host
    $Modules = Get-Module -ListAvailable
    if (-not ($Modules | Where-Object { $_.Name -eq 'Pester' -and $_.Version -ge '5.0' })) {
        "Install Pester" | Write-Host
        Install-Module -Name Pester -Repository PSGallery -Scope CurrentUser -Force -SkipPublisherCheck
    }
    if ("psake" -notin $Modules.Name) {
        "Install psake" | Write-Host
        Install-Module -Name psake -Repository PSGallery -Scope CurrentUser -Force
    }
    if ("PSDeploy" -notin $Modules.Name) {
        "Install PSDeploy" | Write-Host
        Install-Module -Name PSDeploy -Repository PSGallery -Scope CurrentUser -Force
    }
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
