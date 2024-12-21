PARAM(
    [string]$SystemDefaultWorkingDirectory,
    [string]$PsGalleryKey
)
try {
    "Folder tree for SystemDefaultWorkingDirectory:"
    Get-ChildItem "$SystemDefaultWorkingDirectory" -Recurse | ForEach-Object { Write-Host $_.FullName }
}
catch {
    Write-Host "Failed to retrieve directory tree: $_"
}

try {
    Get-ChildItem "$SystemDefaultWorkingDirectory/_OmadaWeb.PS" -Filter *.nuspec -Recurse | Copy-Item -Destination "$SystemDefaultWorkingDirectory/_OmadaWeb.PS Build\BuildOutput\OmadaWeb.PS" -Force
}
catch {
    Write-Error "Failed to copy nuspec file: $_"
    exit 1
}

#Get-ChildItem "$SystemDefaultWorkingDirectory/_OmadaWeb.PS Build" | Where-Object {$_.extension -notin (".psm1", ".psd1")} | Remove-Item -Force
#Publish-Module -Path "$SystemDefaultWorkingDirectory/_OmadaWeb.PS Build/BuildOutput/OmadaWeb.PS" -NugetAPIKey "$PsGalleryKey" -Verbose


