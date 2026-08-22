#Requires -Version 5.1

<#
.SYNOPSIS
    Fetches the WebView2 SDK assemblies and lays them out inside the built module.
.DESCRIPTION
    OmadaWeb.PS used to download the Microsoft.Web.WebView2 assemblies to
    %LOCALAPPDATA%\OmadaWeb.PS\Bin on first use. That fails outright without egress to nuget.org,
    which is the normal state of a locked-down corporate machine, and it loaded the assemblies from a
    user-writable directory long after their bytes had been verified.

    This script puts them in the package instead. It runs from the psake BundleDependencies task,
    after Build, and writes into the built module:

        <PackagePath>\lib\<Core|Desktop>\<win-x64|win-x86>\
            Microsoft.Web.WebView2.Core.dll
            Microsoft.Web.WebView2.WinForms.dll
            WebView2Loader.dll
        <PackagePath>\ThirdPartyNotices.txt

    Microsoft.Web.WebView2.Core.dll P/Invokes WebView2Loader.dll from its own directory, so all three
    files stay together per folder. Microsoft.Web.WebView2.Wpf.dll is deliberately not bundled -
    nothing in the module asks for it.

    The download itself goes through the module's own Invoke-DownloadFile, dot-sourced from
    OmadaWeb.PS\Private, so the package is fetched from the URL pinned in
    OmadaWeb.PS\DependencyLock.psd1 and verified against the SHA-256 pinned there, by exactly the
    same code that verifies it at runtime. There is no second implementation to keep in step.

    Anything missing from the package is a hard error: a release that silently shipped without the
    assemblies would look fine and then fail on the first sign-in of every restricted-network user.
    The runtime download path in Install-WebView2 stays as it is and takes over whenever the bundle
    is absent or incomplete.
.PARAMETER PackagePath
    The built module folder to write lib\ and ThirdPartyNotices.txt into. Defaults to
    buildoutput\OmadaWeb.PS next to this script.
.PARAMETER RepositoryRoot
    Root of the working copy, used to find the module sources. Defaults to the parent of Build\.
.EXAMPLE
    ./Build/Get-BundledDependency.ps1

    Bundles the pinned WebView2 assemblies into buildoutput\OmadaWeb.PS.
.EXAMPLE
    ./Build/Get-BundledDependency.ps1 -PackagePath C:\Temp\OmadaWeb.PS -Verbose

    Bundles into an arbitrary folder and reports every file it copies.
#>
[CmdletBinding()]
param(
    [parameter(Mandatory = $false)]
    [string]$PackagePath = (Join-Path $PSScriptRoot ".." | Join-Path -ChildPath "buildoutput" | Join-Path -ChildPath "OmadaWeb.PS"),
    [parameter(Mandatory = $false)]
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot ".." | Convert-Path)
)

$ErrorActionPreference = "Stop"

$ArtifactId = "Microsoft.Web.WebView2"

# The editions the module can run under, and the folder inside the NuGet package each one loads from.
# These are the same two folder names Install-WebView2 picks between at runtime.
$Edition = @(
    @{ Name = "Desktop"; PackageFolder = "net462" }
    @{ Name = "Core"; PackageFolder = "netcoreapp3.0" }
)
$Architecture = @("win-x64", "win-x86")
$AssemblyFileName = @("Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.WinForms.dll")
$LoaderFileName = "WebView2Loader.dll"

$PrivatePath = Join-Path $RepositoryRoot "OmadaWeb.PS" | Join-Path -ChildPath "Private"

# One verification implementation, not two: these are the very functions the module uses to fetch and
# hash-check the same artefact at runtime.
foreach ($FunctionName in @("Save-RemoteFile", "Confirm-FileHash", "Get-DependencyLock", "Get-LockedArtifact", "Invoke-DownloadFile", "Expand-DownloadFile")) {
    $FunctionPath = Join-Path $PrivatePath ("{0}.ps1" -f $FunctionName)
    if (-not (Test-Path $FunctionPath -PathType Leaf)) {
        "Cannot bundle dependencies: '{0}' does not exist, so the module's own download and verification code cannot be reused." -f $FunctionPath | Write-Error -ErrorAction Stop
    }
    . $FunctionPath
}

# Those functions read the lock through this script-scope variable, exactly as the module does
# through its own.
$Script:DependencyLockPath = Join-Path $RepositoryRoot "OmadaWeb.PS" | Join-Path -ChildPath "DependencyLock.psd1"
$Script:DependencyLock = $null

if (-not (Test-Path $PackagePath -PathType Container)) {
    "Package folder '{0}' does not exist. Run the Build task before bundling." -f $PackagePath | Write-Error -ErrorAction Stop
}

function Copy-PackageFile {
    # Finds one file in the extracted package and copies it into the bundle. The search mirrors what
    # Install-WebView2 does at runtime - by file name, filtered on the directory it has to come from -
    # so the bundled files are the same ones the download path would have installed. The managed
    # assemblies are identified by their target-framework folder, the native loader by the runtime
    # path it sits under, because the package carries one loader per architecture under the same
    # 'native' folder name.
    [CmdletBinding(DefaultParameterSetName = "DirectoryName")]
    param(
        [parameter(Mandatory = $true)]
        [string]$SourceRoot,
        [parameter(Mandatory = $true)]
        [string]$FileName,
        [parameter(Mandatory = $true, ParameterSetName = "DirectoryName")]
        [string]$DirectoryName,
        [parameter(Mandatory = $true, ParameterSetName = "DirectoryPath")]
        [string]$DirectoryPathLike,
        [parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )

    # Sorted before the first match is taken: Get-ChildItem does not promise an enumeration order, so
    # a package that ever grew a second matching folder could otherwise bundle a different binary
    # from one build to the next, for no visible reason.
    if ($PSCmdlet.ParameterSetName -eq "DirectoryName") {
        $Criterion = $DirectoryName
        $Source = Get-ChildItem -Path $SourceRoot -Filter $FileName -Recurse -File |
            Where-Object { $_.Directory.Name -eq $DirectoryName } |
            Sort-Object FullName |
            Select-Object -First 1
    }
    else {
        $Criterion = $DirectoryPathLike
        $Source = Get-ChildItem -Path $SourceRoot -Filter $FileName -Recurse -File |
            Where-Object { $_.Directory.FullName -like $DirectoryPathLike } |
            Sort-Object FullName |
            Select-Object -First 1
    }

    if ($null -eq $Source) {
        "The '{0}' package does not contain '{1}' under a '{2}' folder. The bundled layout cannot be produced from this package." -f $ArtifactId, $FileName, $Criterion | Write-Error -ErrorAction Stop
    }

    $Destination = Join-Path $DestinationFolder $FileName
    Copy-Item -Path $Source.FullName -Destination $Destination -Force
    "  {0} <- {1}" -f $Destination, $Source.FullName | Write-Verbose

    return (Get-Item $Destination)
}

function Copy-PackageText {
    # Licence and notice text is taken from the package rather than kept in the repository, so it
    # always describes the version that was actually bundled.
    param(
        [parameter(Mandatory = $true)]
        [string]$SourceRoot,
        [parameter(Mandatory = $true)]
        [string]$FileName
    )

    $Source = Get-ChildItem -Path $SourceRoot -Filter $FileName -Recurse -File | Sort-Object FullName | Select-Object -First 1
    if ($null -eq $Source) {
        "The '{0}' package does not contain '{1}', so the redistribution notice cannot be reproduced." -f $ArtifactId, $FileName | Write-Error -ErrorAction Stop
    }

    return (Get-Content -Path $Source.FullName -Raw)
}

$Artifact = Get-LockedArtifact -Id $ArtifactId
"Bundling {0} {1} into '{2}'" -f $Artifact.PackageId, $Artifact.Version, $PackagePath | Write-Host -ForegroundColor Cyan

$DownloadedFile = $null
$ExtractedPath = $null
try {
    # Downloads from the pinned URL and refuses anything whose SHA-256 does not match the pin.
    $DownloadedFile = Invoke-DownloadFile -ArtifactId $ArtifactId
    $ExtractedPath = Expand-DownloadFile -FilePath $DownloadedFile

    $LibraryRoot = Join-Path $PackagePath "lib"
    if (Test-Path $LibraryRoot -PathType Container) {
        # A rebuild into an existing buildoutput must not leave files from an earlier version behind.
        Remove-Item -Path $LibraryRoot -Recurse -Force
    }

    $BundledFile = [System.Collections.Generic.List[object]]::new()
    foreach ($CurrentEdition in $Edition) {
        foreach ($CurrentArchitecture in $Architecture) {
            $DestinationFolder = Join-Path $LibraryRoot $CurrentEdition.Name | Join-Path -ChildPath $CurrentArchitecture
            $null = New-Item -Path $DestinationFolder -ItemType Directory -Force

            foreach ($FileName in $AssemblyFileName) {
                $BundledFile.Add((Copy-PackageFile -SourceRoot $ExtractedPath -FileName $FileName -DirectoryName $CurrentEdition.PackageFolder -DestinationFolder $DestinationFolder))
            }

            # The loader is native code, so it comes from runtimes\<arch>\native rather than from a
            # target-framework folder, and is the same file for both editions.
            $BundledFile.Add((Copy-PackageFile -SourceRoot $ExtractedPath -FileName $LoaderFileName -DirectoryPathLike ("*runtimes\{0}\native" -f $CurrentArchitecture) -DestinationFolder $DestinationFolder))

            "Bundled {0}\{1}: {2} file(s)" -f $CurrentEdition.Name, $CurrentArchitecture, ($AssemblyFileName.Count + 1) | Write-Host
        }
    }

    $Notice = [System.Text.StringBuilder]::new()
    $null = $Notice.AppendLine("THIRD-PARTY NOTICES FOR OmadaWeb.PS")
    $null = $Notice.AppendLine()
    $null = $Notice.AppendLine("OmadaWeb.PS redistributes the following component in binary form. The notice below is")
    $null = $Notice.AppendLine("reproduced from the package this build bundled, and applies to the files under lib\.")
    $null = $Notice.AppendLine()
    $null = $Notice.AppendLine(("{0} {1}" -f $Artifact.PackageId, $Artifact.Version))
    $null = $Notice.AppendLine($Artifact.Url)
    $null = $Notice.AppendLine()
    $null = $Notice.AppendLine("--------------------------------------------------------------------------------")
    $null = $Notice.AppendLine()
    $null = $Notice.AppendLine((Copy-PackageText -SourceRoot $ExtractedPath -FileName "LICENSE.txt"))
    $null = $Notice.AppendLine()
    $null = $Notice.AppendLine("--------------------------------------------------------------------------------")
    $null = $Notice.AppendLine()
    $null = $Notice.AppendLine((Copy-PackageText -SourceRoot $ExtractedPath -FileName "NOTICE.txt"))

    $NoticePath = Join-Path $PackagePath "ThirdPartyNotices.txt"
    # Written without a BOM and with CRLF, matching the rest of the repository.
    $NoticeText = ($Notice.ToString() -replace "`r?`n", "`r`n")
    [System.IO.File]::WriteAllText($NoticePath, $NoticeText, (New-Object System.Text.UTF8Encoding($false)))
    "Wrote {0}" -f $NoticePath | Write-Host

    # Printed so the cost of bundling stays visible: the package grew from tens of kilobytes to this,
    # for every user, including those who only use -AuthenticationType Browser.
    $TotalBytes = ($BundledFile | Measure-Object -Property Length -Sum).Sum + (Get-Item $NoticePath).Length
    "Bundle size: {0:N2} MB across {1} file(s)" -f ($TotalBytes / 1MB), ($BundledFile.Count + 1) | Write-Host -ForegroundColor Green
}
finally {
    if ($null -ne $ExtractedPath -and (Test-Path $ExtractedPath)) {
        Remove-Item -Path $ExtractedPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($null -ne $DownloadedFile) {
        # Expand-DownloadFile renames the temporary file to .zip before extracting it.
        foreach ($Leftover in @($DownloadedFile, ("{0}.zip" -f $DownloadedFile))) {
            if (Test-Path $Leftover -PathType Leaf) {
                Remove-Item -Path $Leftover -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
