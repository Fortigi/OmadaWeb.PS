param(
    # Accepted for consistency with the other test files (psakeBuild.ps1 passes it to every
    # container); these tests exercise the build scripts, not the built module.
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    $Script:RepositoryRoot = Split-Path $(Split-Path $PSScriptRoot)
    $Script:ConfirmScript = Join-Path $Script:RepositoryRoot -ChildPath 'Build\Confirm-PackageFileList.ps1'
    $Script:PsakeBuild = Join-Path $Script:RepositoryRoot -ChildPath 'Build\psakeBuild.ps1'

    $Script:WorkFolder = Join-Path ([System.IO.Path]::GetTempPath()) ("OmadaWebPackageTests_{0}" -f ([System.Guid]::NewGuid().ToString('N')))
    $null = New-Item -Path $Script:WorkFolder -ItemType Directory -Force

    function New-TestPackage {
        # A miniature built package: a manifest declaring a FileList, and whichever of those files
        # the test wants to exist.
        param(
            [string]$Name,
            [string[]]$Declared,
            [string[]]$Present
        )

        $PackagePath = Join-Path $Script:WorkFolder -ChildPath $Name
        $null = New-Item -Path $PackagePath -ItemType Directory -Force

        foreach ($File in $Present) {
            $FullPath = Join-Path $PackagePath $File
            $null = New-Item -Path (Split-Path $FullPath) -ItemType Directory -Force
            Set-Content -Path $FullPath -Value 'stub' -NoNewline
        }

        $FileListLiteral = ($Declared | ForEach-Object { "'{0}'" -f $_ }) -join ', '
        $ManifestContent = "@{{ ModuleVersion = '1.0'; FileList = @({0}) }}" -f $FileListLiteral
        Set-Content -Path (Join-Path $PackagePath 'OmadaWeb.PS.psd1') -Value $ManifestContent

        return $PackagePath
    }
}

Describe 'Confirm-PackageFileList.ps1' -Tag 'Unit' {
    It 'Should pass when every declared file is in the package' {
        $PackagePath = New-TestPackage -Name 'complete' `
            -Declared @('OmadaWeb.PS.psd1', 'ThirdPartyNotices.txt', 'lib\Core\win-x64\WebView2Loader.dll') `
            -Present @('ThirdPartyNotices.txt', 'lib\Core\win-x64\WebView2Loader.dll')

        { & $Script:ConfirmScript -PackagePath $PackagePath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Should fail when a declared file is missing, and name it' {
        # Exactly what nightly shipped: a manifest promising the bundle, and a package without it.
        # Update-ModuleManifest refused it minutes later, in another job, with an error about the
        # manifest rather than about the missing build step.
        $PackagePath = New-TestPackage -Name 'missing-bundle' `
            -Declared @('OmadaWeb.PS.psd1', 'ThirdPartyNotices.txt', 'lib\Core\win-x64\WebView2Loader.dll') `
            -Present @()

        $Message = $null
        try {
            & $Script:ConfirmScript -PackagePath $PackagePath -ErrorAction Stop
        }
        catch {
            $Message = $_.Exception.Message
        }

        $Message | Should -Not -BeNullOrEmpty
        $Message | Should -BeLike '*ThirdPartyNotices.txt*'
        $Message | Should -BeLike '*lib\Core\win-x64\WebView2Loader.dll*'
    }

    It 'Should count every missing file, not stop at the first' {
        $PackagePath = New-TestPackage -Name 'partly-missing' `
            -Declared @('OmadaWeb.PS.psd1', 'a.dll', 'b.dll', 'c.dll') `
            -Present @('a.dll')

        $Message = $null
        try {
            & $Script:ConfirmScript -PackagePath $PackagePath -ErrorAction Stop
        }
        catch {
            $Message = $_.Exception.Message
        }

        $Message | Should -BeLike '*missing 2 file(s)*'
    }

    It 'Should refuse a manifest with no FileList, which would verify nothing' {
        $PackagePath = Join-Path $Script:WorkFolder -ChildPath 'no-filelist'
        $null = New-Item -Path $PackagePath -ItemType Directory -Force
        Set-Content -Path (Join-Path $PackagePath 'OmadaWeb.PS.psd1') -Value "@{ ModuleVersion = '1.0' }"

        { & $Script:ConfirmScript -PackagePath $PackagePath -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*declares no FileList*'
    }
}

Describe 'psakeBuild.ps1 packaging' -Tag 'Unit' {
    It 'Should bundle and verify inside the Build task itself' {
        # nightly.yml runs `build.ps1 -Task Build`. When bundling lived in a separate task that only
        # the aggregate task lists pulled in, that produced a package missing every file the manifest
        # declares, and the failure surfaced at publish time.
        $Content = Get-Content -Path $Script:PsakeBuild -Raw

        $BuildTask = [regex]::Match($Content, '(?s)Task Build -depends Analyze \{.*?\r?\n\}')
        $BuildTask.Success | Should -BeTrue

        $BuildTask.Value | Should -BeLike '*Get-BundledDependency.ps1*' -Because 'a build that does not bundle produces a package its own manifest contradicts'
        $BuildTask.Value | Should -BeLike '*Confirm-PackageFileList.ps1*' -Because 'the package must be checked where it is created, not where it is published'
    }

    It 'Should not leave a separate task the task lists have to remember' {
        $Content = Get-Content -Path $Script:PsakeBuild -Raw
        $Content | Should -Not -BeLike '*Task BundleDependencies*'
    }
}

AfterAll {
    if (Test-Path $Script:WorkFolder -PathType Container) {
        Remove-Item -Path $Script:WorkFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}
