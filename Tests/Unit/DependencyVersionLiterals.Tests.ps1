param(
    # Accepted for consistency with the other test files (psakeBuild.ps1 passes it to every
    # container); these tests read the repository's files, not the built module.
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

# A pinned dependency version belongs in exactly one place: Build/Dependencies.psd1, with the hashes
# in OmadaWeb.PS/DependencyLock.psd1 and the package references in Build/Dependencies/*.csproj, all
# three of which a Dependabot bump and the lock refresh update together. A copy of that version
# anywhere else - a test asserting '8.0.5', a README naming the Selenium release - is not updated
# with them, so the next bump fails validation until main is edited first. Read the version from the
# inventory instead.

BeforeAll {
    $Script:RepositoryRoot = Split-Path $(Split-Path $PSScriptRoot)

    # The sources of truth, which must contain the versions.
    $Script:SourceOfTruth = @(
        'Build/Dependencies.psd1'
        'OmadaWeb.PS/DependencyLock.psd1'
    )
    $Script:SourceOfTruthFolder = @(
        'Build/Dependencies/'
    )
    # Generated or downloaded content, never committed.
    $Script:IgnoredFolder = @(
        '.git/'
        'buildoutput/'
        'OmadaWeb.PS/Bin/'
    )
    # Files allowed to contain such a literal, each with its reason.
    $Script:Allowed = @{
        # Fully mocked: its version strings are invented commit messages and API answers, read from
        # nowhere and compared with nothing in the inventory.
        'Tests/Unit/DependabotValidation.Tests.ps1' = 'test fixtures independent of the inventory'
    }
    $Script:TextExtension = @('.ps1', '.psm1', '.psd1', '.md', '.yml', '.yaml', '.json', '.xml', '.nuspec', '.txt')

    function Get-RelativeRepositoryPath {
        param([string]$Root, [string]$Path)
        $Path.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
    }

    # Returns one finding per file and component when the file names the component AND contains its
    # exact pinned version. Requiring the name keeps a short version such as 8.0.0 from matching
    # unrelated text.
    function Find-DependencyVersionLiteral {
        param(
            [string]$Root,
            [object[]]$Component,
            [string[]]$Skip,
            [string[]]$SkipFolder
        )

        $Root = (Resolve-Path -LiteralPath $Root).ProviderPath
        foreach ($File in Get-ChildItem -LiteralPath $Root -Recurse -File -Force) {
            if ($Script:TextExtension -notcontains $File.Extension.ToLowerInvariant()) {
                continue
            }
            $Relative = Get-RelativeRepositoryPath -Root $Root -Path $File.FullName
            if ($Skip -contains $Relative) {
                continue
            }
            if (@($SkipFolder | Where-Object { $Relative.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
                continue
            }

            $Content = [System.IO.File]::ReadAllText($File.FullName)
            foreach ($Item in $Component) {
                $VersionPattern = '(?<![\d.]){0}(?![\d.])' -f [regex]::Escape($Item.Version)
                if ($Content.IndexOf($Item.Name, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                    $Content -match $VersionPattern) {
                    [PSCustomObject]@{
                        File      = $Relative
                        Component = $Item.Name
                        Version   = $Item.Version
                    }
                }
            }
        }
    }

    $Inventory = Import-PowerShellDataFile -Path (Join-Path $Script:RepositoryRoot -ChildPath 'Build/Dependencies.psd1')
    $Script:PinnedComponent = @($Inventory.Components | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Version) } |
            ForEach-Object { [PSCustomObject]@{ Name = $_.Name; Version = $_.Version } })

    $Script:FixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("OmadaWebVersionLiteralTests_{0}" -f ([System.Guid]::NewGuid().ToString('N')))
    $null = New-Item -Path $Script:FixtureRoot -ItemType Directory -Force
}

AfterAll {
    if (Test-Path -LiteralPath $Script:FixtureRoot) {
        Remove-Item -LiteralPath $Script:FixtureRoot -Recurse -Force
    }
}

Describe 'Dependency version literals' -Tag 'Unit' {

    It 'Should have pinned components to check' {
        $Script:PinnedComponent.Count | Should -BeGreaterThan 0 -Because 'Build/Dependencies.psd1 pins at least one component'
    }

    It 'Should only allow files that exist' {
        foreach ($Path in $Script:Allowed.Keys) {
            Join-Path $Script:RepositoryRoot -ChildPath $Path | Should -Exist -Because "a stale entry in the allow list hides nothing and should be removed"
        }
    }

    It 'Should find a pinned version copied outside the inventory' {
        # Guards the guard: a planted copy must be reported, and the same version in a source of truth,
        # an ignored folder, for an unrelated name or inside a longer version must not.
        $Component = @([PSCustomObject]@{ Name = 'Example.Package'; Version = '8.0.5' })
        $Planted = Join-Path $Script:FixtureRoot -ChildPath 'Tests'
        $Truth = Join-Path $Script:FixtureRoot -ChildPath 'Build'
        $Ignored = Join-Path $Script:FixtureRoot -ChildPath 'buildoutput'
        $null = New-Item -Path $Planted, $Truth, $Ignored -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path $Planted -ChildPath 'Copy.Tests.ps1') -Value "`$Pinned.version | Should -Be '8.0.5' # Example.Package"
        Set-Content -LiteralPath (Join-Path $Planted -ChildPath 'OtherName.Tests.ps1') -Value 'Unrelated.Package 8.0.5'
        Set-Content -LiteralPath (Join-Path $Planted -ChildPath 'LongerVersion.Tests.ps1') -Value 'Example.Package 18.0.5 and 8.0.5.1'
        Set-Content -LiteralPath (Join-Path $Truth -ChildPath 'Dependencies.psd1') -Value "@{ Name = 'Example.Package'; Version = '8.0.5' }"
        Set-Content -LiteralPath (Join-Path $Ignored -ChildPath 'out.json') -Value '{"Example.Package":"8.0.5"}'

        $Found = @(Find-DependencyVersionLiteral -Root $Script:FixtureRoot -Component $Component -Skip @('Build/Dependencies.psd1') -SkipFolder @('buildoutput/'))

        $Found.Count | Should -Be 1
        $Found[0].File | Should -Be 'Tests/Copy.Tests.ps1'
    }

    It 'Should not copy any pinned dependency version outside the inventory' {
        $Found = @(Find-DependencyVersionLiteral -Root $Script:RepositoryRoot -Component $Script:PinnedComponent `
                -Skip (@($Script:SourceOfTruth) + @($Script:Allowed.Keys)) -SkipFolder (@($Script:SourceOfTruthFolder) + @($Script:IgnoredFolder)))
        $Detail = ($Found | ForEach-Object { '{0}: {1} {2}' -f $_.File, $_.Component, $_.Version }) -join "`n"
        $Found | Should -BeNullOrEmpty -Because "a copied version breaks the next Dependabot bump; read it from Build/Dependencies.psd1 instead`n$Detail"
    }
}
