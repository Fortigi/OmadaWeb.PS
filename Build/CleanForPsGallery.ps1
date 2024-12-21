PARAM(
    [string]$WorkSpaceFolder,
    [string]$psgallery
)
Get-ChildItem "$WorkSpaceFolder" -Recurse | ForEach-Object {$_.FullName}
Get-ChildItem "$WorkSpaceFolder/_OmadaWeb.PS Build" | Where-Object {$_.extension -notin (".psm1", ".psd1")} | Remove-Item -Force
#Publish-Module -Path "$WorkSpaceFolder/_OmadaWeb.PS Build" -NugetAPIKey "$(psgallery)" -Verbose