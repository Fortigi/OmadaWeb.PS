param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Expand-DownloadFile' -Tag 'Unit' {
    It 'Should delete the downloaded zip after extraction and return the extracted folder' {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ TestDrive = $TestDrive } {
            $SourceFolder = Join-Path $TestDrive 'source'
            New-Item -ItemType Directory -Path $SourceFolder -Force | Out-Null
            Set-Content -Path (Join-Path $SourceFolder 'file.txt') -Value 'content' -NoNewline

            # Invoke-DownloadFile hands Expand-DownloadFile an extension-less temp file, the same
            # shape produced here: compress to a .zip, then rename away the extension.
            $DownloadedFile = Join-Path $TestDrive 'download.tmp'
            $ZipPath = "$DownloadedFile.zip"
            Compress-Archive -Path (Join-Path $SourceFolder '*') -DestinationPath $ZipPath -Force
            Move-Item -Path $ZipPath -Destination $DownloadedFile -Force

            $Result = Expand-DownloadFile -FilePath $DownloadedFile

            Test-Path -LiteralPath $ZipPath -PathType Leaf | Should -BeFalse
            Test-Path -LiteralPath $Result.FullName -PathType Container | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $Result.FullName 'file.txt') -PathType Leaf | Should -BeTrue
        }
    }
}
