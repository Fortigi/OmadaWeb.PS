PARAM(
    [string]$SystemDefaultWorkingDirectory,
    [string]$PsGalleryKey,
    [string]$BuildPath
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls13

try {
    "Folder tree for SystemDefaultWorkingDirectory:" | Write-Host
    Get-ChildItem "$SystemDefaultWorkingDirectory" -Recurse | ForEach-Object { Write-Host $_.FullName }
}
catch {
    Write-Host "Failed to retrieve directory tree: $_"
}

try {
    "Publish-Module to PSGallery" | Write-Host
    $SourcePath = "{0}/_Artifact/{1}" -f $SystemDefaultWorkingDirectory,$BuildPath.TrimStart('/')
    Publish-Module -Path $SourcePath -NuGetApiKey "$PsGalleryKey" -Verbose
}
catch {
    Write-Error "Failed to deploy to PowerShell Gallery: $_"
    exit 1
}




