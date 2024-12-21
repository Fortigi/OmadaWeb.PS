PARAM(
    $SystemDefaultWorkingDirectory,
    $GitHubPAT
)

try {
    "Current path {0}" -f (Get-Location).Path | Write-Host

    "Folder contents for: $SystemDefaultWorkingDirectory" | Write-Host
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
    git fetch --tags
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
    $env:GH_TOKEN | gh auth login --with-token -
    gh auth status | Write-Host
}
catch {
    Write-Error "GitHub authentication failed: $_"
    exit 1
}

try {
    Get-Item .git* -Force | Remove-Item -Force -Recurse
    New-Item ./GitHub -ItemType Directory | Out-Null
    git clone https://$GitHubPAT@github.com/fortigi/OmadaWeb.PS.git ./GitHub
    Copy-Item -Path "./Azure/*" -Destination "./GitHub/" -Recurse -Force
}
catch {
    Write-Error "File operations failed: $_"
    exit 1
}

try {
    Set-Location ./GitHub
    git config --global user.email "mark@fortigi.nl"
    git config --global user.name "Mark van Eijken"
    git add .
    git commit -m "Release version $latestTag"
    git push -f origin main
    gh release create $latestTag --title "Release $latestTag" --notes "Release $latestTag"
}
catch {
    Write-Error "Git or release operations failed: $_"
    exit 1
}