PARAM(
    [string]$SystemDefaultWorkingDirectory,
    [string]$PsGalleryKey
)
#Get-ChildItem "$SystemDefaultWorkingDirectory" -Recurse | ForEach-Object {$_.FullName}
#Get-ChildItem "$SystemDefaultWorkingDirectory/_OmadaWeb.PS Build" | Where-Object {$_.extension -notin (".psm1", ".psd1")} | Remove-Item -Force
Publish-Module -Path "$SystemDefaultWorkingDirectory/_OmadaWeb.PS Build/BuildOutput/OmadaWeb.PS" -NugetAPIKey "$PsGalleryKey" -Verbose

