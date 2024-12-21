"Folder contents" | Write-Host
Get-ChildItem "$(System.DefaultWorkingDirectory)" -Recurse | ForEach-Object {$_.FullName}
"Installing GitHub CLI" | Write-Host
Invoke-WebRequest -Uri https://github.com/cli/cli/releases/download/v2.63.2/gh_2.63.2_windows_amd64.msi -OutFile gh.msi
Start-Process msiexec.exe -Wait -ArgumentList '/i gh.msi /quiet /norestart'
Get-Item gh.msi | Remove-Item -Force
"GitHub CLI installed successfully" | Write-Host