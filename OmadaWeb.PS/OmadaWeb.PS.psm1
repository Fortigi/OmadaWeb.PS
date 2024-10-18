#Add parameters like: Import-Module OmadaWeb.PS -ArgumentList "C:\Temp\","C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
PARAM(
    [ValidateNotNullOrEmpty()]
    $WebDriverBasePath = "$PSScriptRoot\Bin",
    [ValidateNotNullOrEmpty()]
    $InstalledEdgeBasePath = "C:\Program Files (x86)\Microsoft\Edge\Application",
    [ValidateNotNullOrEmpty()]
    $NewtonsoftJsonPath="$PSScriptRoot\Bin",
    $OmadaWebAuthCookie
)

"Loading OmadaWeb.PS Module" | Write-Verbose

"PsBoundParameters = {0}" -f ($PsBoundParameters | ConvertTo-Json) | Write-Verbose

#Get public and private function definition files.
$Public = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -Recurse)
$Private = @(Get-ChildItem -Path $PSScriptRoot\Private\*.ps1)

#EdgeDriver Location
$Script:EdgeDriverPath = [System.IO.Path]::Combine($WebDriverBasePath, "msedgedriver.exe")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:EdgeDriverPath | Write-Verbose

#Newtonsoft.Json Location
$Script:NewtonsoftJsonPath = [System.IO.Path]::Combine($($NewtonsoftJsonPath), "Newtonsoft.Json.dll")
"{0} - {1}" -f $MyInvocation.MyCommand, $($Script:NewtonsoftJsonPath) | Write-Verbose

#WebDriver Location
$Script:WebDriverPath = [System.IO.Path]::Combine($WebDriverBasePath, "WebDriver.dll")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebDriverPath | Write-Verbose

#Edge Location
$Script:InstalledEdgeFilePath = [System.IO.Path]::Combine($InstalledEdgeBasePath, "msedge.exe")
"{0} - {1}" -f $MyInvocation.MyCommand, $Script:InstalledEdgeFilePath | Write-Verbose
if ($PSBoundParameters["InstalledEdgeBasePath"] -and -not (Test-Path $Script:InstalledEdgeFilePath -PathType Leaf)) {
    "Cannot find path '{0}'. Please make sure that it exists!" -f $Script:InstalledEdgeFilePath | Write-Error -ErrorAction "Stop"
}

#OmadaWebAuthCookie
if($null -ne $PsBoundParameters["OmadaWebAuthCookie"]){
    "Using provided OmadaWebAuthCookie when loading module" | Write-Verbose
    New-Variable OmadaWebAuthCookie -Value $PsBoundParameters["OmadaWebAuthCookie"] -Force -Scope Global | Out-Null
}
elseif([string]::IsNullOrEmpty($Script:OmadaWebAuthCookie)){
    "Initialize OmadaWebAuthCookie" | Write-Verbose
    New-Variable OmadaWebAuthCookie -Value $null -Force -Scope Global | Out-Null
}

#Dot source the files
Foreach ($Import in @($Public + $Private)) {
    try {
        . $Import.FullName
    }
    catch {
        "Failed to import function {0}: {1}" -f $($Import.FullName), $_ | Write-Error -ErrorAction "Stop"
    }
}

# Export all the functions
Export-ModuleMember -Function $Public.Basename -Alias *