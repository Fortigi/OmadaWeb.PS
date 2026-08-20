param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Invoke-DownloadFile' -Tag 'Unit' {
    BeforeEach {
        # A stand-in lock file, so these tests assert the gate's behaviour rather than the current
        # pins. "hello" hashes to the SHA-256 below.
        InModuleScope 'OmadaWeb.PS' {
            $Script:DependencyLock = @{
                SchemaVersion = 1
                Artifacts     = @(
                    @{
                        Id           = 'Test.Pinned'
                        PackageId    = 'Test.Pinned'
                        Version      = '1.2.3'
                        Url          = 'https://example.invalid/test.pinned.1.2.3.nupkg'
                        Sha256       = '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824'
                        Verification = 'Sha256'
                    }
                    @{
                        Id             = 'Test.Signed'
                        Verification   = 'Authenticode'
                        SubjectPattern = '*O=Contoso*'
                    }
                )
            }

            # Stands in for the network. Each test decides what the "server" returns.
            Mock Save-RemoteFile { Set-Content -Path $OutputFile -Value $Script:TestPayload -NoNewline }
            $Script:TestPayload = 'hello'
        }
    }

    It 'Should return the downloaded file when its hash matches the pin' {
        InModuleScope 'OmadaWeb.PS' {
            $Path = Invoke-DownloadFile -ArtifactId 'Test.Pinned'

            Test-Path $Path -PathType Leaf | Should -BeTrue
            Get-Content -Path $Path -Raw | Should -Be 'hello'
            Should -Invoke Save-RemoteFile -Times 1 -ParameterFilter { $DownloadUrl -eq 'https://example.invalid/test.pinned.1.2.3.nupkg' }

            Remove-Item $Path -Force
        }
    }

    It 'Should refuse a tampered download, delete it, and name the artefact and both hashes' {
        InModuleScope 'OmadaWeb.PS' {
            $Script:TestPayload = 'tampered'
            $Script:CapturedOutputFile = $null
            Mock Save-RemoteFile {
                $Script:CapturedOutputFile = $OutputFile
                Set-Content -Path $OutputFile -Value $Script:TestPayload -NoNewline
            }

            { Invoke-DownloadFile -ArtifactId 'Test.Pinned' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Integrity check FAILED*'

            # The bytes must be gone, not merely rejected.
            Test-Path $Script:CapturedOutputFile -PathType Leaf | Should -BeFalse
        }
    }

    It 'Should report the artefact, the expected hash and the actual hash in the failure' {
        InModuleScope 'OmadaWeb.PS' {
            $Script:TestPayload = 'tampered'

            $Message = $null
            try {
                Invoke-DownloadFile -ArtifactId 'Test.Pinned' -ErrorAction Stop
            }
            catch {
                $Message = $_.Exception.Message
            }

            $Message | Should -BeLike '*Test.Pinned 1.2.3*'
            $Message | Should -BeLike '*2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824*'
            # SHA-256 of "tampered".
            $Message | Should -BeLike '*d121be3103007b41edf96f8262925f8c7d61894afe9a041843b631f69445bc57*'
        }
    }

    It 'Should refuse an artefact that is not in the lock file without downloading anything' {
        InModuleScope 'OmadaWeb.PS' {
            { Invoke-DownloadFile -ArtifactId 'Definitely.Not.Pinned' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*no lock entry for artefact*'

            Should -Invoke Save-RemoteFile -Times 0
        }
    }

    It 'Should refuse to download a hash-pinned artefact from a caller-supplied URL' {
        InModuleScope 'OmadaWeb.PS' {
            { Invoke-DownloadFile -ArtifactId 'Test.Pinned' -DownloadUrl 'https://evil.invalid/payload.nupkg' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*must be downloaded from its pinned URL*'

            Should -Invoke Save-RemoteFile -Times 0
        }
    }

    It 'Should allow a caller-supplied URL only for an artefact declared Authenticode-verified' {
        InModuleScope 'OmadaWeb.PS' {
            $Path = Invoke-DownloadFile -ArtifactId 'Test.Signed' -DownloadUrl 'https://msedgedriver.invalid/edgedriver_win64.zip'

            Should -Invoke Save-RemoteFile -Times 1 -ParameterFilter { $DownloadUrl -eq 'https://msedgedriver.invalid/edgedriver_win64.zip' }
            Test-Path $Path -PathType Leaf | Should -BeTrue

            Remove-Item $Path -Force
        }
    }

    It 'Should refuse an Authenticode artefact requested without a URL, since it has no pinned one' {
        InModuleScope 'OmadaWeb.PS' {
            { Invoke-DownloadFile -ArtifactId 'Test.Signed' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*explicit -DownloadUrl*'

            Should -Invoke Save-RemoteFile -Times 0
        }
    }
}

Describe 'Get-DependencyLock' -Tag 'Unit' {
    It 'Should refuse to run when the lock file is missing rather than downloading unverified' {
        InModuleScope 'OmadaWeb.PS' {
            $Script:DependencyLock = $null
            $OriginalPath = $Script:DependencyLockPath
            try {
                $Script:DependencyLockPath = Join-Path $TestDrive 'does-not-exist.psd1'

                { Get-DependencyLock -ErrorAction Stop } | Should -Throw -ExpectedMessage '*is missing*'
            }
            finally {
                $Script:DependencyLockPath = $OriginalPath
                $Script:DependencyLock = $null
            }
        }
    }

    It 'Should refuse a lock file written to a schema it does not understand' {
        InModuleScope 'OmadaWeb.PS' {
            $Script:DependencyLock = $null
            $OriginalPath = $Script:DependencyLockPath
            try {
                $FuturePath = Join-Path $TestDrive 'future.psd1'
                Set-Content -Path $FuturePath -Value "@{ SchemaVersion = 99; Artifacts = @() }"
                $Script:DependencyLockPath = $FuturePath

                { Get-DependencyLock -ErrorAction Stop } | Should -Throw -ExpectedMessage '*schema version*'
            }
            finally {
                $Script:DependencyLockPath = $OriginalPath
                $Script:DependencyLock = $null
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
