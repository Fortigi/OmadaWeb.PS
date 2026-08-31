param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    $Script:RepositoryRoot = Split-Path $(Split-Path $PSScriptRoot)
    $Script:LockPath = Join-Path $Script:RepositoryRoot -ChildPath 'OmadaWeb.PS\DependencyLock.psd1'
    $Script:PrivatePath = Join-Path $Script:RepositoryRoot -ChildPath 'OmadaWeb.PS\Private'
    $Script:InventoryPath = Join-Path $Script:RepositoryRoot -ChildPath 'Build\Dependencies.psd1'

    $Script:Lock = Import-PowerShellDataFile -Path $Script:LockPath
    $Script:Artifacts = @($Script:Lock.Artifacts)

    $Script:UpdateScript = Join-Path $Script:RepositoryRoot -ChildPath 'Build\Update-DependencyLock.ps1'
    $Script:WorkFolder = Join-Path ([System.IO.Path]::GetTempPath()) ("OmadaWebLockTests_{0}" -f ([System.Guid]::NewGuid().ToString('N')))
    $null = New-Item -Path $Script:WorkFolder -ItemType Directory -Force

    function New-LockSandbox {
        # A throwaway copy of everything Update-DependencyLock.ps1 reads, so a test can doctor one
        # file and assert the gate notices. The script itself is always run from the real repository,
        # which is also how the scheduled sweep invokes it: trusted script, untrusted tree.
        $Root = Join-Path $Script:WorkFolder -ChildPath ([System.Guid]::NewGuid().ToString('N'))
        foreach ($Relative in @('OmadaWeb.PS', 'Build\Dependencies', '.github')) {
            $null = New-Item -Path (Join-Path $Root -ChildPath $Relative) -ItemType Directory -Force
        }

        Copy-Item -Path $Script:LockPath -Destination (Join-Path $Root -ChildPath 'OmadaWeb.PS\DependencyLock.psd1')
        Copy-Item -Path $Script:InventoryPath -Destination (Join-Path $Root -ChildPath 'Build\Dependencies.psd1')
        Copy-Item -Path (Join-Path $Script:RepositoryRoot -ChildPath '.github\dependabot.yml') -Destination (Join-Path $Root -ChildPath '.github\dependabot.yml')
        Copy-Item -Path (Join-Path $Script:RepositoryRoot -ChildPath 'Build\Dependencies') -Destination (Join-Path $Root -ChildPath 'Build') -Recurse -Force
        Copy-Item -Path $Script:PrivatePath -Destination (Join-Path $Root -ChildPath 'OmadaWeb.PS') -Recurse -Force

        return $Root
    }

    function Get-PinnedVersion {
        # Versions are read from the lock rather than written into the test, so a legitimate bump does
        # not break a test that is really about "these two files disagree".
        param([string]$Id)

        $Artifact = @($Script:Artifacts | Where-Object { $_.Id -eq $Id })
        $Artifact.Count | Should -Be 1 -Because "the tests below doctor the pin for '$Id'"
        return $Artifact[0].Version
    }

    function Set-DoctoredVersion {
        # Introduces one specific disagreement into a sandbox file, and asserts it actually landed -
        # otherwise a renamed field would leave the test passing while exercising nothing.
        param([string]$Path, [string]$Find, [string]$Replace)

        $Content = Get-Content -Path $Path -Raw
        $Content | Should -BeLike "*$Find*" -Because "the test needs '$Find' present in '$Path' to doctor it"
        $Content.Replace($Find, $Replace) | Set-Content -Path $Path -NoNewline
    }
}

AfterAll {
    if ($Script:WorkFolder -and (Test-Path $Script:WorkFolder)) {
        Remove-Item -Path $Script:WorkFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'DependencyLock.psd1' -Tag 'Unit' {
    It 'Should ship with the module so downloads can be verified on a clean install' {
        # The module resolves the lock through $PSScriptRoot, and refuses every download without it,
        # so it has to be packaged - both by Publish-Module (FileList) and by nuget pack (nuspec).
        Test-Path $Script:LockPath -PathType Leaf | Should -BeTrue

        $Manifest = Import-PowerShellDataFile -Path (Join-Path $Script:RepositoryRoot -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psd1')
        $Manifest.FileList | Should -Contain 'DependencyLock.psd1'

        $Nuspec = Get-Content -Path (Join-Path $Script:RepositoryRoot -ChildPath 'OmadaWeb.PS.nuspec') -Raw
        $Nuspec | Should -BeLike '*DependencyLock.psd1*'
    }

    It 'Should declare a schema version the module understands' {
        $Script:Lock.SchemaVersion | Should -Be 1
    }

    It 'Should list every artefact exactly once' {
        $Duplicates = $Script:Artifacts | Group-Object { $_.Id } | Where-Object { $_.Count -gt 1 }
        $Duplicates | Should -BeNullOrEmpty -Because 'Get-LockedArtifact refuses an ambiguous id'
    }

    It 'Should pin a 64-character lower-case SHA-256 for every hash-verified artefact' {
        foreach ($Artifact in $Script:Artifacts | Where-Object { $_.Verification -eq 'Sha256' }) {
            $Artifact.Sha256 | Should -Match '^[0-9a-f]{64}$' -Because "artefact '$($Artifact.Id)' is verified by hash"
            $Artifact.Version | Should -Not -BeNullOrEmpty -Because "artefact '$($Artifact.Id)' is verified by hash"
            $Artifact.Url | Should -BeLike 'https://*' -Because "artefact '$($Artifact.Id)' must be fetched over TLS"
        }
    }

    It 'Should give every Authenticode artefact a publisher to match against' {
        $Signed = @($Script:Artifacts | Where-Object { $_.Verification -eq 'Authenticode' })
        $Signed.Count | Should -BeGreaterThan 0

        foreach ($Artifact in $Signed) {
            # Without a subject pattern any validly signed binary would pass, which is the whole risk.
            $Artifact.SubjectPattern | Should -Not -BeNullOrEmpty -Because "artefact '$($Artifact.Id)' is verified by signature alone"
            $Artifact.PinReason | Should -Not -BeNullOrEmpty -Because "not pinning an artefact by hash needs a stated reason"
        }
    }

    It 'Should use only verification modes the module implements' {
        foreach ($Artifact in $Script:Artifacts) {
            $Artifact.Verification | Should -BeIn @('Sha256', 'Authenticode')
        }
    }

    It 'Should have an entry for every artefact the module downloads' {
        # The guard against a new Install-*.ps1 download slipping in unpinned: it would fail closed at
        # runtime, which is safe but is a bug better caught here.
        $KnownIds = @($Script:Artifacts | ForEach-Object { $_.Id })
        $Requested = Get-ChildItem -Path $Script:PrivatePath -Filter '*.ps1' -File |
            Select-String -Pattern '-ArtifactId\s+"(?<Id>[^"]+)"' -AllMatches |
            ForEach-Object { $_.Matches } |
            ForEach-Object { $_.Groups['Id'].Value } |
            Sort-Object -Unique

        @($Requested).Count | Should -BeGreaterThan 0
        foreach ($Id in $Requested) {
            $KnownIds | Should -Contain $Id -Because "Invoke-DownloadFile -ArtifactId '$Id' would otherwise be refused at runtime"
        }
    }

    It 'Should name an installer that exists for every artefact' {
        foreach ($Artifact in $Script:Artifacts) {
            $InstallerPath = Join-Path $Script:PrivatePath -ChildPath ('{0}.ps1' -f $Artifact.InstalledBy)
            Test-Path $InstallerPath -PathType Leaf | Should -BeTrue -Because "artefact '$($Artifact.Id)' claims to be installed by '$($Artifact.InstalledBy)'"
        }
    }

    It 'Should derive every download URL from the pinned package and version' {
        foreach ($Artifact in $Script:Artifacts | Where-Object { $_.Verification -eq 'Sha256' }) {
            $Expected = 'https://api.nuget.org/v3-flatcontainer/{0}/{1}/{0}.{1}.nupkg' -f $Artifact.PackageId.ToLowerInvariant(), $Artifact.Version.ToLowerInvariant()
            $Artifact.Url | Should -Be $Expected -Because "artefact '$($Artifact.Id)' must be fetched from the version it is pinned to"
        }
    }
}

Describe 'Dependency manifests' -Tag 'Unit' {
    It 'Should declare every hash-pinned artefact so Dependabot can raise advisories against it' {
        foreach ($Artifact in $Script:Artifacts | Where-Object { $_.Verification -eq 'Sha256' }) {
            $ManifestPath = Join-Path $Script:RepositoryRoot -ChildPath $Artifact.Manifest
            Test-Path $ManifestPath -PathType Leaf | Should -BeTrue -Because "artefact '$($Artifact.Id)' names manifest '$($Artifact.Manifest)'"

            [xml]$Manifest = Get-Content -Path $ManifestPath -Raw
            $Reference = @($Manifest.Project.ItemGroup.PackageReference | Where-Object { $_.Include -eq $Artifact.PackageId })

            $Reference.Count | Should -Be 1 -Because "'$($Artifact.PackageId)' must appear once in '$($Artifact.Manifest)' to enter the dependency graph"
            $Reference[0].Version | Should -Be $Artifact.Version -Because "a pin that disagrees with the manifest means the hash was never refreshed"
        }
    }
}

Describe 'Update-DependencyLock.ps1 -Check' -Tag 'Unit' {
    # -SkipDownload throughout: these assert the offline gates, and a unit test must not depend on
    # nuget.org being reachable.
    It 'Should pass on the repository as it stands' {
        { & $Script:UpdateScript -Check -SkipDownload -RepositoryRoot (New-LockSandbox) } | Should -Not -Throw
    }

    It 'Should fail when the SBOM reports a version the lock does not pin' {
        # The gap that kept every Dependabot pull request red even once its hashes were refreshed:
        # Build/Dependencies.psd1 was the third file that had to move, and nothing moved it.
        $Root = New-LockSandbox
        $InventoryFile = Join-Path $Root -ChildPath 'Build\Dependencies.psd1'
        Set-DoctoredVersion -Path $InventoryFile -Find ('Version         = "{0}"' -f (Get-PinnedVersion 'Newtonsoft.Json')) -Replace 'Version         = "0.0.0"'

        { & $Script:UpdateScript -Check -SkipDownload -RepositoryRoot $Root } | Should -Throw -ExpectedMessage '*problem(s) found*'
    }

    It 'Should fail when a closure member has no Dependabot ignore rule' {
        $Root = New-LockSandbox
        $ConfigFile = Join-Path $Root -ChildPath '.github\dependabot.yml'
        # Read fully before writing: streaming Get-Content straight back into Set-Content on the same
        # path leaves the file open for reading while Set-Content wants it.
        $Line = @(Get-Content -Path $ConfigFile | Where-Object { $_ -notmatch 'dependency-name: "System.Memory"' })
        $Line | Set-Content -Path $ConfigFile

        { & $Script:UpdateScript -Check -SkipDownload -RepositoryRoot $Root } | Should -Throw -ExpectedMessage '*problem(s) found*'
    }

    It 'Should fail when the lock and the Dependabot manifest disagree on a version' {
        $Root = New-LockSandbox
        $ManifestFile = Join-Path $Root -ChildPath 'Build\Dependencies\Dependencies.csproj'
        Set-DoctoredVersion -Path $ManifestFile -Find ('"Newtonsoft.Json" Version="{0}"' -f (Get-PinnedVersion 'Newtonsoft.Json')) -Replace '"Newtonsoft.Json" Version="0.0.0"'

        { & $Script:UpdateScript -Check -SkipDownload -RepositoryRoot $Root } | Should -Throw -ExpectedMessage '*problem(s) found*'
    }

    It 'Should read the ignore list whichever way its YAML scalars are quoted' {
        # Double quotes, single quotes and bare scalars all mean the same string in YAML. Reading only
        # one form would turn a reformatting of dependabot.yml into a false build failure.
        $Root = New-LockSandbox
        $ConfigFile = Join-Path $Root -ChildPath '.github\dependabot.yml'
        $Rewritten = @(Get-Content -Path $ConfigFile | ForEach-Object {
                if ($_ -match '^(\s*-\s+dependency-name\s*:\s*)"([^"]+)"\s*$') {
                    "{0}'{1}'" -f $Matches[1], $Matches[2]
                }
                elseif ($_ -match '^(\s*directory\s*:\s*)"([^"]+)"\s*$') {
                    "{0}{1}" -f $Matches[1], $Matches[2]
                }
                else {
                    $_
                }
            })
        $Rewritten | Set-Content -Path $ConfigFile

        { & $Script:UpdateScript -Check -SkipDownload -RepositoryRoot $Root } | Should -Not -Throw
    }

    It 'Should not accept an ignore rule that belongs to a different manifest directory' {
        # Legacy/ has its own ignore list. A rule there must not satisfy a requirement about the main
        # manifest, or the closure check would pass on a configuration that does not govern it.
        $Root = New-LockSandbox
        $ConfigFile = Join-Path $Root -ChildPath '.github\dependabot.yml'
        $Line = @(Get-Content -Path $ConfigFile | Where-Object { $_ -notmatch 'dependency-name: "System.Memory"' })
        # Re-add it under the Legacy directory block, which is the last one in the file.
        ($Line + '      - dependency-name: "System.Memory"') | Set-Content -Path $ConfigFile

        { & $Script:UpdateScript -Check -SkipDownload -RepositoryRoot $Root } | Should -Throw -ExpectedMessage '*problem(s) found*'
    }
}

Describe 'Dependabot ignore policy' -Tag 'Unit' {
    # The System.Text.Json closure cannot be upgraded a member at a time: the module loads these
    # assemblies with Assembly.LoadFrom, which applies no binding redirects, so the versions loaded
    # have to be the ones the pinned System.Text.Json resolves. Dependabot has to be told, or it keeps
    # opening pull requests that can never go green - which is what happened to #55 and #58.
    It 'Should ignore version updates for every member of the System.Text.Json closure' {
        $Closure = @($Script:Artifacts | Where-Object { $_.Group -eq 'SystemTextJson' })
        $Closure.Count | Should -BeGreaterThan 0 -Because 'the closure is what this rule protects'

        $Config = Get-Content -Path (Join-Path $Script:RepositoryRoot -ChildPath '.github\dependabot.yml') -Raw

        foreach ($Artifact in $Closure) {
            $Config | Should -BeLike "*dependency-name: `"$($Artifact.PackageId)`"*" -Because "Dependabot would otherwise propose bumping '$($Artifact.PackageId)' on its own"
        }
    }

    It 'Should keep the frozen Selenium pin out of Dependabot version updates' {
        # 4.11.0 is the last Selenium that ships a net4* build, so the Desktop pin must not move.
        $Desktop = @($Script:Artifacts | Where-Object { $_.Id -eq 'Selenium.Desktop' })
        $Desktop.Count | Should -Be 1

        $Config = Get-Content -Path (Join-Path $Script:RepositoryRoot -ChildPath '.github\dependabot.yml') -Raw
        $Config | Should -BeLike '*dependency-name: "Selenium.WebDriver"*'
    }
}

Describe 'SBOM inventory' -Tag 'Unit' {
    It 'Should record the same versions as the lock file' {
        $Inventory = Import-PowerShellDataFile -Path $Script:InventoryPath

        foreach ($Component in $Inventory.Components | Where-Object { -not [string]::IsNullOrWhiteSpace($_.LockId) }) {
            $Artifact = @($Script:Artifacts | Where-Object { $_.Id -eq $Component.LockId })
            $Artifact.Count | Should -Be 1 -Because "SBOM component '$($Component.Name)' points at lock artefact '$($Component.LockId)'"
            $Component.Version | Should -Be $Artifact[0].Version -Because "the SBOM must report the version that is actually pinned and loaded"
        }
    }
}
