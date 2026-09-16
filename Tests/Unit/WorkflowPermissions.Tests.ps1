param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    $Script:RepositoryRoot = Split-Path $(Split-Path $PSScriptRoot)
    $Script:WorkflowsPath = Join-Path $Script:RepositoryRoot -ChildPath '.github\workflows'

    # Deliberately line-based rather than a real YAML parser: no YAML module is a
    # dependency of this repository's tests or build, and adding one just for this
    # regression test is not worth it. GitHub Actions workflow files have a fixed,
    # predictable indentation shape, so a targeted regex over that structure is
    # reliable here without pulling in powershell-yaml.
    function Get-JobPermissionBlocks {
        # Not [Parameter(Mandatory)]: a mandatory string[] parameter rejects an
        # array containing an empty string element, and workflow YAML files are
        # full of blank lines.
        param(
            [string[]]$Lines
        )

        # Top-level `permissions:` sits at column 0. A job-level `permissions:` sits
        # nested under `jobs:` at 4-space indent (`  <job-name>:` at 2 spaces,
        # `    permissions:` at 4 spaces). A scope line under either block is
        # indented two spaces further than its own `permissions:` key.
        $Result = [ordered]@{
            TopLevel = $null
            Jobs     = [ordered]@{}
        }

        $CurrentJob = $null
        $InTopLevelPermissions = $false
        $InJobPermissions = $false

        for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
            $Line = $Lines[$Index]

            if ($Line -match '^permissions:\s*$') {
                $InTopLevelPermissions = $true
                $InJobPermissions = $false
                $Result.TopLevel = [System.Collections.Generic.List[string]]::new()
                continue
            }

            if ($Line -match '^\S') {
                $InTopLevelPermissions = $false
            }

            if ($InTopLevelPermissions) {
                if ($Line -match '^  (\S+):\s*(\S*)\s*$') {
                    $Result.TopLevel.Add($Matches[1] + ':' + $Matches[2])
                    continue
                }
                else {
                    $InTopLevelPermissions = $false
                }
            }

            # A job name is a two-space-indented key directly under `jobs:`.
            if ($Line -match '^  (\S[^:]*):\s*$') {
                $CurrentJob = $Matches[1]
                $InJobPermissions = $false
                continue
            }

            if ($null -ne $CurrentJob -and $Line -match '^    permissions:\s*$') {
                $InJobPermissions = $true
                $Result.Jobs[$CurrentJob] = [System.Collections.Generic.List[string]]::new()
                continue
            }

            if ($InJobPermissions) {
                if ($Line -match '^      (\S+):\s*(\S*)\s*$') {
                    $Result.Jobs[$CurrentJob].Add($Matches[1] + ':' + $Matches[2])
                    continue
                }
                else {
                    $InJobPermissions = $false
                }
            }
        }

        return $Result
    }

    function Get-WriteScopes {
        param(
            [AllowNull()]
            [System.Collections.Generic.List[string]]$ScopeLines
        )

        if ($null -eq $ScopeLines) {
            return @()
        }

        return @($ScopeLines | Where-Object { $_ -match ':\s*write\s*$' })
    }

    $Script:NightlyLines = Get-Content -Path (Join-Path $Script:WorkflowsPath -ChildPath 'nightly.yml')
    $Script:NightlyPermissions = Get-JobPermissionBlocks -Lines $Script:NightlyLines

    $Script:ReleaseLines = Get-Content -Path (Join-Path $Script:WorkflowsPath -ChildPath 'release.yml')
    $Script:ReleasePermissions = Get-JobPermissionBlocks -Lines $Script:ReleaseLines
}

Describe 'Workflow token permissions are least-privilege' {

    Context 'nightly.yml' {

        It 'declares a top-level permissions block' {
            $Script:NightlyPermissions.TopLevel | Should -Not -BeNullOrEmpty
        }

        It 'defaults the top-level permissions to contents: read' {
            $Script:NightlyPermissions.TopLevel | Should -Contain 'contents:read'
        }

        It 'grants no write scope at the top level' {
            Get-WriteScopes -ScopeLines $Script:NightlyPermissions.TopLevel | Should -BeNullOrEmpty
        }

        It 'grants contents: write only on the nightly-release job' {
            $Script:NightlyPermissions.Jobs.Keys | Should -Contain 'nightly-release'
            $Script:NightlyPermissions.Jobs['nightly-release'] | Should -Contain 'contents:write'
        }

        It 'does not grant a job-level permissions block to the check job' {
            $Script:NightlyPermissions.Jobs.Keys | Should -Not -Contain 'check'
        }

        It 'does not grant a job-level permissions block to the build job' {
            $Script:NightlyPermissions.Jobs.Keys | Should -Not -Contain 'build'
        }
    }

    Context 'release.yml' {

        It 'declares a top-level permissions block' {
            $Script:ReleasePermissions.TopLevel | Should -Not -BeNullOrEmpty
        }

        It 'defaults the top-level permissions to contents: read' {
            $Script:ReleasePermissions.TopLevel | Should -Contain 'contents:read'
        }

        It 'grants no write scope at the top level' {
            Get-WriteScopes -ScopeLines $Script:ReleasePermissions.TopLevel | Should -BeNullOrEmpty
        }

        It 'grants checks: write only on the build job, which runs the test reporter' {
            $Script:ReleasePermissions.Jobs.Keys | Should -Contain 'build'
            $Script:ReleasePermissions.Jobs['build'] | Should -Contain 'checks:write'
        }

        It 'does not grant contents: write on the build job' {
            $Script:ReleasePermissions.Jobs['build'] | Should -Not -Contain 'contents:write'
        }

        It 'grants contents: write only on the release job, which tags and publishes' {
            $Script:ReleasePermissions.Jobs.Keys | Should -Contain 'release'
            $Script:ReleasePermissions.Jobs['release'] | Should -Contain 'contents:write'
        }

        It 'does not grant checks: write on the release job' {
            $Script:ReleasePermissions.Jobs['release'] | Should -Not -Contain 'checks:write'
        }
    }
}
