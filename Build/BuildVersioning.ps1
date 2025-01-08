try {
    $currentDate = $(Get-Date)
    $year = $currentDate.Year
    $month = $currentDate.Month
    $day = $currentDate.Day
    "Current date: {0}" -f $currentDate | Write-Host
    "Current year: {0}" -f $year | Write-Host
    "Current month: {0}" -f $month | Write-Host
    "Current day: {0}" -f $day | Write-Host
    "Revision: {0}" -f $env:revision | Write-Host
    $versionString = "{0:d4}.{1:d2}.{2:d2}.{3}" -f $year, $month, $day, ($env:revision -eq $null ? 0 : $env:revision)
    "Version: {0}" -f $versionString | Write-Host
    Write-Host "##vso[task.setvariable variable=buildVersion;isOutput=true]$versionString"
    Write-Host "##vso[task.setvariable variable=year;isOutput=true]$year"
}
catch {
    Write-Error "Failed to set build version: $_"
    exit 1
}
