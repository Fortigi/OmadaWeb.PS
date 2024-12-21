Get-ChildItem $(Pipeline.Workspace) -Recurse | ForEach-Object {$_.FullName}
Get-ChildItem "$(Pipeline.Workspace)/_OmadaWeb.PS Build" | Where-Object {$_.extension -notin (".psm1", ".psd1")} | Remove-Item -Force
#Publish-Module -Path "$(Pipeline.Workspace)/_OmadaWeb.PS Build" -NugetAPIKey "$(psgallery)" -Verbose