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
