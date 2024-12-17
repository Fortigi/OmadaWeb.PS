function Expand-DownloadFile {
    PARAM(
        [parameter(Mandatory = $true)]
        [validateScript({ Test-Path $_ -PathType Leaf })]
        $FilePath

    )

    $FilePath = Get-Item $FilePath | Move-Item -Destination ("{0}.zip" -f $FilePath) -PassThru -Force
    $ZipOutputPath = (Join-Path (Get-Item $FilePath).PsParentPath -ChildPath $($FilePath.BaseName.Substring(0, $FilePath.BaseName.IndexOf("."))))
    $ZipOutputPath = New-Item $ZipOutputPath -ItemType Directory -Force
    Get-Item $FilePath | Expand-Archive -DestinationPath $($ZipOutputPath.FullName)

    return $($ZipOutputPath)
}