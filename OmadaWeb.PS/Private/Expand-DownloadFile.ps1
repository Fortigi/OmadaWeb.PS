function Expand-DownloadFile {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true)]
        [validateScript({ Test-Path $_ -PathType Leaf })]
        $FilePath

    )
    "{0} - Expanding archive: {1}" -f $MyInvocation.MyCommand, $FilePath | Write-Verbose
    $FilePath = Get-Item $FilePath | Move-Item -Destination ("{0}.zip" -f $FilePath) -PassThru -Force
    $ZipOutputPath = (Join-Path (Get-Item $FilePath).PsParentPath -ChildPath $($FilePath.BaseName.Substring(0, $FilePath.BaseName.IndexOf("."))))
    $ZipOutputPath = New-Item $ZipOutputPath -ItemType Directory -Force
    Get-Item $FilePath | Expand-Archive -DestinationPath $($ZipOutputPath.FullName)

    return $($ZipOutputPath)
}