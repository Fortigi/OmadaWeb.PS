PARAM(
    [string]$SystemDefaultWorkingDirectory,
    [string]$PAT
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12,[Net.SecurityProtocolType]::Tls11,[Net.SecurityProtocolType]::Tls13

try {
    "Current path {0}" -f (Get-Location).Path | Write-Host
    Set-Location "$SystemDefaultWorkingDirectory\_OmadaWeb.PS\"
    "Current path {0}" -f (Get-Location).Path | Write-Host

    "Folder contents for SystemDefaultWorkingDirectory: $SystemDefaultWorkingDirectory" | Write-Host
    Get-ChildItem "$SystemDefaultWorkingDirectory" -Recurse | ForEach-Object {
        $_.FullName | Write-Host
    }
}
catch {
    Write-Error "Error: $_"
    exit 1
}

try {
    "Installing GitHub CLI" | Write-Host
    Invoke-WebRequest -Uri https://github.com/cli/cli/releases/download/v2.63.2/gh_2.63.2_windows_amd64.msi -OutFile gh.msi
    Start-Process msiexec.exe -Wait -ArgumentList '/i gh.msi /quiet /norestart'
    Get-Item gh.msi | Remove-Item -Force
    "GitHub CLI installed successfully" | Write-Host
}
catch {
    Write-Error "GitHub CLI installation failed: $_"
    exit 1
}

try {
    $PAT | gh auth login --with-token -
    gh auth status | Write-Host
}
catch {
    Write-Error "GitHub authentication failed: $_"
    exit 1
}

try {
    # git fetch --tags
    $latestTag = git describe --tags "$(git rev-list --tags --max-count=1)"
    if ([string]::IsNullOrEmpty($latestTag)) {
        Write-Error "No tags found. Exiting."
        exit 1
    }
    Write-Host "Latest tag: $latestTag"
    git checkout $latestTag
}
catch {
    Write-Error "Git tag operations failed: $_"
    exit 1
}

try {
    Set-Location "$SystemDefaultWorkingDirectory\_Fortigi_OmadaWeb.PS"
    git config --global user.email "mark@fortigi.nl"
    git config --global user.name "Mark van Eijken"
    git remote set-url origin "https://$($PAT)@github.com/fortigi/OmadaWeb.PS.git"
    git checkout main
}
catch {
    Write-Error "Git or release operations failed: $_"
    exit 1
}


try {
    "Copy contents to _Fortigi_OmadaWeb.PS" | Write-Host
    Copy-Item -Path "$SystemDefaultWorkingDirectory\_OmadaWeb.PS\*" -Destination "$SystemDefaultWorkingDirectory\_Fortigi_OmadaWeb.PS" -Recurse -Force -PassThru -Exclude ".git"
}
catch {
    Write-Error "File operations failed: $_"
    exit 1
}

try {
    git add .
    git commit -m "Release version $latestTag"
    git push -f origin main
}
catch {
    Write-Error "Git or release operations failed: $_"
    exit 1
}

try {
    gh release create $latestTag --title "Release $latestTag" --notes "Release $latestTag"
}
catch {
    Write-Error "Git or release operations failed: $_"
    exit 1
}