param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

# Reputation-gated validation decides, without a maintainer, which Dependabot pull requests get PR
# Validation started for them. A mistake here fails OPEN - a version is validated, and offered for
# merge as eligible, that policy says should have waited - so every decision is pinned against the real
# policy file, with all network access mocked. Runs on Windows PowerShell 5.1 and PowerShell 7 alike.

BeforeAll {
    $Script:RepositoryRoot = Split-Path $(Split-Path $PSScriptRoot)
    $Script:BuildPath = Join-Path $Script:RepositoryRoot -ChildPath 'Build'
    . (Join-Path $Script:BuildPath -ChildPath 'DependabotValidation.ps1')
    $Script:Policy = Get-DependabotPolicy -Path (Join-Path $Script:BuildPath -ChildPath 'DependabotValidation.psd1')
    $Script:Now = New-Object System.DateTime -ArgumentList 2026, 10, 12, 12, 0, 0, ([System.DateTimeKind]::Utc)

    function New-ApiResponse {
        param([int]$StatusCode = 200, [object]$Content)
        [PSCustomObject]@{ StatusCode = $StatusCode; Content = $Content }
    }

    function New-Scorecard {
        param([double]$Score = 8.5, [int]$DangerousWorkflow = 10, [object]$Date = $Script:Now.AddDays(-5))
        [PSCustomObject]@{
            overallScore = $Score
            date         = $Date.ToString('o')
            checks       = @([PSCustomObject]@{ name = 'Dangerous-Workflow'; score = $DangerousWorkflow })
        }
    }

    function New-Dependency {
        param([string]$Name = 'Selenium.WebDriver', [string]$Version = '4.51.0', [string]$UpdateType = 'version-update:semver-minor')
        [PSCustomObject]@{ Name = $Name; Version = $Version; UpdateType = $UpdateType; DependencyType = 'direct:production' }
    }

    function New-Commit {
        param([string]$Login = 'dependabot[bot]', [bool]$Verified = $true, [string]$Sha = 'abcdef1234567890', [string]$Message = '')
        [PSCustomObject]@{
            sha    = $Sha
            author = [PSCustomObject]@{ login = $Login }
            commit = [PSCustomObject]@{ message = $Message; verification = [PSCustomObject]@{ verified = $Verified } }
        }
    }

    function New-PrFile {
        param([string]$Name, [string]$Status = 'modified')
        [PSCustomObject]@{ filename = $Name; status = $Status }
    }

    $Script:NuGetMessage = @'
deps: Bump Selenium.WebDriver and 2 others

Bumps Selenium.WebDriver from 4.47.0 to 4.51.0
Bumps System.Runtime.CompilerServices.Unsafe from 4.5.3 to 6.0.0
Bumps System.Text.Json from 8.0.5 to 8.0.6

---
updated-dependencies:
- dependency-name: Selenium.WebDriver
  dependency-version: 4.51.0
  dependency-type: direct:production
  update-type: version-update:semver-minor
- dependency-name: System.Runtime.CompilerServices.Unsafe
  dependency-version: 6.0.0
  dependency-type: direct:production
  update-type: version-update:semver-major
- dependency-name: System.Text.Json
  dependency-version: '8.0.6'
  dependency-type: direct:production
  update-type: version-update:semver-patch
...

Signed-off-by: dependabot[bot] <support@github.com>
'@
}

Describe 'ConvertFrom-DependabotCommitMessage' -Tag 'Unit' {
    It 'reads every dependency of a multi-dependency update, unquoting values' {
        $Result = @(ConvertFrom-DependabotCommitMessage -Message $Script:NuGetMessage)
        $Result.Count | Should -Be 3
        $Result[0].Name | Should -Be 'Selenium.WebDriver'
        $Result[0].Version | Should -Be '4.51.0'
        $Result[1].UpdateType | Should -Be 'version-update:semver-major'
        $Result[2].Version | Should -Be '8.0.6'
    }

    It 'reads a CRLF message the same way' {
        $Result = @(ConvertFrom-DependabotCommitMessage -Message ($Script:NuGetMessage -replace '\r?\n', "`r`n"))
        $Result.Count | Should -Be 3
        $Result[2].UpdateType | Should -Be 'version-update:semver-patch'
    }

    It 'falls back to the Bumps line when the metadata carries no dependency-version' {
        $Message = "Bumps Newtonsoft.Json from 13.0.3 to 13.0.4.`n`n---`nupdated-dependencies:`n- dependency-name: Newtonsoft.Json`n  update-type: version-update:semver-patch`n...`n"
        $Result = @(ConvertFrom-DependabotCommitMessage -Message $Message)
        $Result[0].Version | Should -Be '13.0.4'
    }

    It 'returns nothing for a message without the metadata block' {
        @(ConvertFrom-DependabotCommitMessage -Message 'Fix a typo').Count | Should -Be 0
    }
}

Describe 'Get-DependabotEcosystem' -Tag 'Unit' {
    It 'reads <Expected> from <Branch>' -ForEach @(
        @{ Branch = 'dependabot/nuget/Build/Dependencies/multi-fa6232684c'; Expected = 'nuget' }
        @{ Branch = 'dependabot/github_actions/github-actions-1a2b3c'; Expected = 'github_actions' }
    ) {
        Get-DependabotEcosystem -BranchName $Branch | Should -Be $Expected
    }

    It 'returns nothing for a branch that is not Dependabot''s' {
        Get-DependabotEcosystem -BranchName 'feature/dependabot-like' | Should -BeNullOrEmpty
    }
}

Describe 'Test-DependabotProvenance' -Tag 'Unit' {
    It 'accepts a verified Dependabot bump plus the signed lock refresh of this repository''s workflow' {
        $Commits = @((New-Commit), (New-Commit -Login 'github-actions[bot]' -Sha '1234567abcdef'))
        $Files = @((New-PrFile 'Build/Dependencies/Dependencies.csproj'), (New-PrFile 'Build/Dependencies.psd1'), (New-PrFile 'OmadaWeb.PS/DependencyLock.psd1'))
        (Test-DependabotProvenance -Commit $Commits -File $Files -Ecosystem 'nuget' -Policy $Script:Policy).Eligible | Should -BeTrue
    }

    It 'accepts the legacy manifest' {
        (Test-DependabotProvenance -Commit @(New-Commit) -File @(New-PrFile 'Build/Dependencies/Legacy/Dependencies.Legacy.csproj') -Ecosystem 'nuget' -Policy $Script:Policy).Eligible | Should -BeTrue
    }

    It 'accepts a verified Dependabot commit that only touches workflow files' {
        (Test-DependabotProvenance -Commit @(New-Commit) -File @(New-PrFile '.github/workflows/release.yml') -Ecosystem 'github_actions' -Policy $Script:Policy).Eligible | Should -BeTrue
    }

    It 'rejects the unsigned lock refresh the workflow pushed before it committed through the API' {
        $Commits = @((New-Commit), (New-Commit -Login 'github-actions[bot]' -Verified $false))
        $Result = Test-DependabotProvenance -Commit $Commits -File @(New-PrFile 'OmadaWeb.PS/DependencyLock.psd1') -Ecosystem 'nuget' -Policy $Script:Policy
        $Result.Eligible | Should -BeFalse
        ($Result.Reasons -join ' ') | Should -Match 'no signature GitHub verified'
    }

    It 'rejects a commit pushed by a person' {
        $Result = Test-DependabotProvenance -Commit @((New-Commit), (New-Commit -Login 'someone')) -File @(New-PrFile 'Build/Dependencies/Dependencies.csproj') -Ecosystem 'nuget' -Policy $Script:Policy
        $Result.Eligible | Should -BeFalse
        ($Result.Reasons -join ' ') | Should -Match "authored by 'someone'"
    }

    It 'rejects a commit no GitHub account is attributed to, as the lock refresh used to push' {
        $Unattributed = New-Commit
        $Unattributed.author = $null
        $Result = Test-DependabotProvenance -Commit @((New-Commit), $Unattributed) -File @(New-PrFile 'OmadaWeb.PS/DependencyLock.psd1') -Ecosystem 'nuget' -Policy $Script:Policy
        $Result.Eligible | Should -BeFalse
        ($Result.Reasons -join ' ') | Should -Match 'not attributed to any GitHub account'
    }

    It 'rejects a github-actions[bot] commit on an Actions update, where only Dependabot may commit' {
        (Test-DependabotProvenance -Commit @((New-Commit), (New-Commit -Login 'github-actions[bot]')) -File @(New-PrFile '.github/workflows/release.yml') -Ecosystem 'github_actions' -Policy $Script:Policy).Eligible | Should -BeFalse
    }

    It 'rejects a pull request whose first commit is not Dependabot''s' {
        (Test-DependabotProvenance -Commit @(New-Commit -Login 'github-actions[bot]') -File @(New-PrFile 'OmadaWeb.PS/DependencyLock.psd1') -Ecosystem 'nuget' -Policy $Script:Policy).Eligible | Should -BeFalse
    }

    It 'rejects <Name> (<Status>) on a <Ecosystem> update' -ForEach @(
        @{ Name = 'OmadaWeb.PS/OmadaWeb.PS.psm1'; Status = 'modified'; Ecosystem = 'nuget' }
        @{ Name = 'Build/Update-DependencyLock.ps1'; Status = 'modified'; Ecosystem = 'nuget' }
        @{ Name = 'Build/Dependencies/Extra.csproj'; Status = 'added'; Ecosystem = 'nuget' }
        @{ Name = 'OmadaWeb.PS/DependencyLock.psd1'; Status = 'modified'; Ecosystem = 'github_actions' }
    ) {
        (Test-DependabotProvenance -Commit @(New-Commit) -File @(New-PrFile -Name $Name -Status $Status) -Ecosystem $Ecosystem -Policy $Script:Policy).Eligible | Should -BeFalse
    }

    It 'rejects an ecosystem that is not configured' {
        (Test-DependabotProvenance -Commit @(New-Commit) -File @() -Ecosystem 'docker' -Policy $Script:Policy).Eligible | Should -BeFalse
    }
}

Describe 'Test-DependabotScorecard' -Tag 'Unit' {
    It 'passes a recent Scorecard above every floor' {
        @(Test-DependabotScorecard -Scorecard (New-Scorecard) -ProjectKey 'github.com/a/b' -Policy $Script:Policy.Reputation -Now $Script:Now).Count | Should -Be 0
    }

    It 'fails <Case>' -ForEach @(
        @{ Case = 'a missing Scorecard'; Kind = 'none'; Pattern = 'no OpenSSF Scorecard' }
        @{ Case = 'a score below the minimum'; Kind = 'low'; Pattern = 'below the minimum of 7.0' }
        @{ Case = 'a stale Scorecard'; Kind = 'stale'; Pattern = 'days old' }
        @{ Case = 'a dangerous workflow'; Kind = 'dangerous'; Pattern = 'Dangerous-Workflow' }
        @{ Case = 'an inconclusive dangerous-workflow check'; Kind = 'inconclusive'; Pattern = 'Dangerous-Workflow' }
        @{ Case = 'a Scorecard without the check'; Kind = 'nocheck'; Pattern = 'has no Dangerous-Workflow check' }
    ) {
        $Card = switch ($Kind) {
            'low' { New-Scorecard -Score 6.9 }
            'stale' { New-Scorecard -Date $Script:Now.AddDays(-60) }
            'dangerous' { New-Scorecard -DangerousWorkflow 0 }
            'inconclusive' { New-Scorecard -DangerousWorkflow -1 }
            'nocheck' { $C = New-Scorecard; $C.checks = @(); $C }
            default { $null }
        }
        $Reasons = @(Test-DependabotScorecard -Scorecard $Card -ProjectKey 'github.com/a/b' -Policy $Script:Policy.Reputation -Now $Script:Now)
        $Reasons.Count | Should -BeGreaterThan 0
        ($Reasons -join ' ') | Should -Match $Pattern
    }

    It 'reads a date ConvertFrom-Json already turned into a DateTime' {
        $Card = New-Scorecard
        $Card.date = $Script:Now.AddDays(-2)
        @(Test-DependabotScorecard -Scorecard $Card -ProjectKey 'github.com/a/b' -Policy $Script:Policy.Reputation -Now $Script:Now).Count | Should -Be 0
    }
}

Describe 'Test-DependabotReputation' -Tag 'Unit' {
    BeforeEach {
        Mock Invoke-DependabotApi { New-ApiResponse -StatusCode 404 }
    }

    It 'stops at a major update without asking any reputation source' {
        (Test-DependabotReputation -Dependency (New-Dependency -UpdateType 'version-update:semver-major') -Ecosystem 'nuget' -Policy $Script:Policy -Now $Script:Now).Eligible | Should -BeFalse
        Should -Invoke Invoke-DependabotApi -Times 0
    }

    Context 'a NuGet package' {
        It 'passes a version old enough from a source repository with a good Scorecard, trying the lower-cased id' {
            Mock Invoke-DependabotApi -ParameterFilter { $Uri -eq 'https://api.deps.dev/v3/systems/nuget/packages/selenium.webdriver/versions/4.51.0' } {
                New-ApiResponse -Content ([PSCustomObject]@{
                        publishedAt     = $Script:Now.AddDays(-12).ToString('o')
                        relatedProjects = @(
                            [PSCustomObject]@{ relationType = 'ISSUE_TRACKER'; projectKey = [PSCustomObject]@{ id = 'github.com/elsewhere/tracker' } }
                            [PSCustomObject]@{ relationType = 'SOURCE_REPO'; projectKey = [PSCustomObject]@{ id = 'github.com/seleniumhq/selenium' } }
                        )
                    })
            }
            Mock Invoke-DependabotApi -ParameterFilter { $Uri -eq 'https://api.deps.dev/v3/projects/github.com%2Fseleniumhq%2Fselenium' } { New-ApiResponse -Content ([PSCustomObject]@{ scorecard = (New-Scorecard -Score 8.1) }) }

            $Result = Test-DependabotReputation -Dependency (New-Dependency) -Ecosystem 'nuget' -Policy $Script:Policy -Now $Script:Now
            $Result.Reasons | Should -BeNullOrEmpty
            $Result.Eligible | Should -BeTrue
            $Result.Score | Should -Be 8.1
        }

        It 'fails a package deps.dev links to no source repository' {
            Mock Invoke-DependabotApi -ParameterFilter { $Uri -like 'https://api.deps.dev/v3/systems/nuget/*' } { New-ApiResponse -Content ([PSCustomObject]@{ publishedAt = $Script:Now.AddDays(-12).ToString('o'); relatedProjects = @() }) }
            $Result = Test-DependabotReputation -Dependency (New-Dependency -Name 'Microsoft.Web.WebView2' -Version '1.0.4258.31' -UpdateType 'version-update:semver-patch') -Ecosystem 'nuget' -Policy $Script:Policy -Now $Script:Now
            $Result.Eligible | Should -BeFalse
            ($Result.Reasons -join ' ') | Should -Match 'no source repository'
        }

        It 'fails a version younger than the minimum age, as a fresh security update would be' {
            Mock Invoke-DependabotApi -ParameterFilter { $Uri -like 'https://api.deps.dev/v3/systems/nuget/*' } {
                New-ApiResponse -Content ([PSCustomObject]@{ publishedAt = $Script:Now.AddHours(-20).ToString('o'); relatedProjects = @([PSCustomObject]@{ relationType = 'SOURCE_REPO'; projectKey = [PSCustomObject]@{ id = 'github.com/a/b' } }) })
            }
            Mock Invoke-DependabotApi -ParameterFilter { $Uri -like 'https://api.deps.dev/v3/projects/*' } { New-ApiResponse -Content ([PSCustomObject]@{ scorecard = (New-Scorecard) }) }
            $Result = Test-DependabotReputation -Dependency (New-Dependency) -Ecosystem 'nuget' -Policy $Script:Policy -Now $Script:Now
            $Result.Eligible | Should -BeFalse
            ($Result.Reasons -join ' ') | Should -Match 'less than the 3 required'
        }

        It 'fails a version deps.dev does not know' {
            (Test-DependabotReputation -Dependency (New-Dependency -Name 'Unknown.Package') -Ecosystem 'nuget' -Policy $Script:Policy -Now $Script:Now).Eligible | Should -BeFalse
        }
    }

    Context 'a GitHub Action' {
        It 'passes a release old enough from a repository with a good Scorecard, owner/repository only' {
            Mock Invoke-DependabotApi -ParameterFilter { $Uri -like '*/repos/github/codeql-action/releases/tags/v3.2.1' } { New-ApiResponse -Content ([PSCustomObject]@{ draft = $false; prerelease = $false; published_at = $Script:Now.AddDays(-10).ToString('o') }) }
            Mock Invoke-DependabotApi -ParameterFilter { $Uri -eq 'https://api.deps.dev/v3/projects/github.com%2Fgithub%2Fcodeql-action' } { New-ApiResponse -Content ([PSCustomObject]@{ scorecard = (New-Scorecard) }) }
            (Test-DependabotReputation -Dependency (New-Dependency -Name 'github/codeql-action/init' -Version '3.2.1') -Ecosystem 'github_actions' -Policy $Script:Policy -Now $Script:Now).Eligible | Should -BeTrue
        }

        It 'fails a version without a published release, since its age is unknown' {
            Mock Invoke-DependabotApi -ParameterFilter { $Uri -like 'https://api.deps.dev/*' } { New-ApiResponse -Content ([PSCustomObject]@{ scorecard = (New-Scorecard) }) }
            $Result = Test-DependabotReputation -Dependency (New-Dependency -Name 'actions/checkout' -Version '7.1.0') -Ecosystem 'github_actions' -Policy $Script:Policy -Now $Script:Now
            $Result.Eligible | Should -BeFalse
            ($Result.Reasons -join ' ') | Should -Match 'no published GitHub release'
        }

        It 'fails a prerelease' {
            Mock Invoke-DependabotApi -ParameterFilter { $Uri -like '*/releases/tags/v7.1.0' } { New-ApiResponse -Content ([PSCustomObject]@{ draft = $false; prerelease = $true; published_at = $Script:Now.AddDays(-10).ToString('o') }) }
            Mock Invoke-DependabotApi -ParameterFilter { $Uri -like 'https://api.deps.dev/*' } { New-ApiResponse -Content ([PSCustomObject]@{ scorecard = (New-Scorecard) }) }
            (Test-DependabotReputation -Dependency (New-Dependency -Name 'actions/checkout' -Version '7.1.0') -Ecosystem 'github_actions' -Policy $Script:Policy -Now $Script:Now).Eligible | Should -BeFalse
        }
    }
}

Describe 'Get-DependabotNextStep' -Tag 'Unit' {
    It 'returns <Expected> for an <Ecosystem> pull request (eligible: <Eligible>, lock in files: <HasLock>, lock synced: <Synced>)' -ForEach @(
        @{ Ecosystem = 'nuget'; Eligible = $false; HasLock = $false; Synced = $false; Expected = 'none' }
        @{ Ecosystem = 'nuget'; Eligible = $true; HasLock = $false; Synced = $false; Expected = 'sync-lock' }
        @{ Ecosystem = 'nuget'; Eligible = $true; HasLock = $true; Synced = $false; Expected = 'validate' }
        @{ Ecosystem = 'nuget'; Eligible = $true; HasLock = $false; Synced = $true; Expected = 'validate' }
        @{ Ecosystem = 'github_actions'; Eligible = $true; HasLock = $false; Synced = $false; Expected = 'validate' }
    ) {
        $Files = @('Build/Dependencies/Dependencies.csproj')
        if ($HasLock) { $Files += 'OmadaWeb.PS/DependencyLock.psd1' }
        $Evaluation = [PSCustomObject]@{ Ecosystem = $Ecosystem; Eligible = $Eligible; Files = $Files }
        Get-DependabotNextStep -Evaluation $Evaluation -Policy $Script:Policy -LockSynced:$Synced | Should -Be $Expected
    }
}

Describe 'Invoke-DependabotApi' -Tag 'Unit' {
    BeforeAll {
        $Script:SavedToken = $env:GITHUB_TOKEN
        $env:GITHUB_TOKEN = 'test-token'
    }
    AfterAll {
        $env:GITHUB_TOKEN = $Script:SavedToken
    }

    It 'sends the GITHUB_TOKEN to api.github.com and parses the JSON it gets back' {
        Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '[{"number":1},{"number":2}]' } }
        $Response = Invoke-DependabotApi -Uri 'https://api.github.com/repos/o/r/pulls'
        $Response.StatusCode | Should -Be 200
        @($Response.Content).Count | Should -Be 2
        Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $Headers['Authorization'] -eq 'Bearer test-token' }
    }

    It 'never sends the GITHUB_TOKEN anywhere else' {
        Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }
        $null = Invoke-DependabotApi -Uri 'https://api.deps.dev/v3/projects/x'
        Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { -not $Headers.ContainsKey('Authorization') }
    }

    It 'returns an HTTP error status as an answer rather than throwing' {
        Mock Invoke-WebRequest {
            $Exception = New-Object System.Exception 'Not Found'
            $Exception | Add-Member -NotePropertyName Response -NotePropertyValue ([PSCustomObject]@{ StatusCode = 404 })
            throw $Exception
        }
        (Invoke-DependabotApi -Uri 'https://api.github.com/repos/o/r/releases/tags/v1').StatusCode | Should -Be 404
    }

    It 'still throws when there was no HTTP response at all' {
        Mock Invoke-WebRequest { throw (New-Object System.Exception 'No such host') }
        { Invoke-DependabotApi -Uri 'https://api.github.com/repos/o/r' } | Should -Throw '*No such host*'
    }
}

Describe 'Format-DependabotReport and Set-DependabotComment' -Tag 'Unit' {
    BeforeAll {
        $Script:Evaluation = [PSCustomObject]@{
            Eligible     = $false
            HeadSha      = 'abc123'
            Reasons      = @('`x`: Scorecard 5.0 for github.com/a/b is below the minimum of 7.0')
            Dependencies = @([PSCustomObject]@{ Name = 'x'; Version = '1.2.0'; UpdateType = 'version-update:semver-minor'; ProjectKey = 'github.com/a/b'; Score = 5.0; PublishedAt = $Script:Now; Eligible = $false })
        }
    }

    It 'starts with the marker, says what happens next, and is stable for the same evaluation' {
        $First = Format-DependabotReport -Evaluation $Script:Evaluation -NextStep 'none'
        $First | Should -BeLike '<!-- dependabot-validation -->*'
        $First | Should -Match 'Manual review required'
        $First | Should -Match '\| `x` \| 1\.2\.0 \| semver-minor \| github\.com/a/b \| 5\.0 \| 2026-10-12 \| fail \|'
        Format-DependabotReport -Evaluation $Script:Evaluation -NextStep 'none' | Should -BeExactly $First
        Format-DependabotReport -Evaluation $Script:Evaluation -NextStep 'validate' | Should -Match 'A maintainer reviews the result and merges'
        Format-DependabotReport -Evaluation $Script:Evaluation -NextStep 'sync-lock' | Should -Match 'hashes are being refreshed first'
    }

    It 'creates the comment when the pull request has none yet' {
        Mock Invoke-DependabotApi -ParameterFilter { $Method -in 'Post', 'Patch' } { New-ApiResponse -StatusCode 201 }
        Mock Invoke-DependabotApi -ParameterFilter { $Uri -like '*/issues/3/comments?per_page=100' } { New-ApiResponse -Content @([PSCustomObject]@{ id = 1; user = [PSCustomObject]@{ login = 'someone' }; body = 'hello' }) }
        Set-DependabotComment -Repository 'o/r' -Number 3 -Body 'new body'
        Should -Invoke Invoke-DependabotApi -Times 1 -ParameterFilter { $Method -eq 'Post' -and $Body.body -eq 'new body' }
    }

    It 'writes nothing when its own comment already says the same, line endings aside' {
        Mock Invoke-DependabotApi -ParameterFilter { $Method -in 'Post', 'Patch' } { New-ApiResponse -StatusCode 201 }
        $Body = "<!-- dependabot-validation -->`nsame"
        Mock Invoke-DependabotApi -ParameterFilter { $Uri -like '*/issues/3/comments?per_page=100' } { New-ApiResponse -Content @([PSCustomObject]@{ id = 9; user = [PSCustomObject]@{ login = 'github-actions[bot]' }; body = "<!-- dependabot-validation -->`r`nsame" }) }
        Set-DependabotComment -Repository 'o/r' -Number 3 -Body $Body
        Should -Invoke Invoke-DependabotApi -Times 0 -ParameterFilter { $Method -in 'Post', 'Patch' }
    }

    It 'edits its own comment in place when the verdict changed' {
        Mock Invoke-DependabotApi -ParameterFilter { $Method -in 'Post', 'Patch' } { New-ApiResponse -StatusCode 200 }
        Mock Invoke-DependabotApi -ParameterFilter { $Uri -like '*/issues/3/comments?per_page=100' } { New-ApiResponse -Content @([PSCustomObject]@{ id = 9; user = [PSCustomObject]@{ login = 'github-actions[bot]' }; body = "<!-- dependabot-validation -->`nold" }) }
        Set-DependabotComment -Repository 'o/r' -Number 3 -Body "<!-- dependabot-validation -->`nnew"
        Should -Invoke Invoke-DependabotApi -Times 1 -ParameterFilter { $Method -eq 'Patch' -and $Uri -like '*/issues/comments/9' }
        Should -Invoke Invoke-DependabotApi -Times 0 -ParameterFilter { $Method -eq 'Post' }
    }
}

Describe 'Get-DependabotEvaluation' -Tag 'Unit' {
    It 'judges every dependency of an untouched Dependabot pull request and reports the major update in it' {
        Mock Invoke-DependabotApi -ParameterFilter { $Uri -like '*/pulls/5/commits*' } { New-ApiResponse -Content @(New-Commit -Message $Script:NuGetMessage) }
        Mock Invoke-DependabotApi -ParameterFilter { $Uri -like '*/pulls/5/files*' } { New-ApiResponse -Content @(New-PrFile 'Build/Dependencies/Dependencies.csproj') }
        Mock Test-DependabotReputation { [PSCustomObject]@{ Name = $Dependency.Name; Eligible = ($Dependency.UpdateType -ne 'version-update:semver-major'); Reasons = @(if ($Dependency.UpdateType -eq 'version-update:semver-major') { 'major' }) } }

        $PullRequest = [PSCustomObject]@{ number = 5; user = [PSCustomObject]@{ login = 'dependabot[bot]' }; head = [PSCustomObject]@{ ref = 'dependabot/nuget/Build/Dependencies/multi-1'; sha = 'h5' } }
        $Evaluation = Get-DependabotEvaluation -Repository 'o/r' -PullRequest $PullRequest -Policy $Script:Policy -Now $Script:Now
        $Evaluation.Ecosystem | Should -Be 'nuget'
        $Evaluation.Eligible | Should -BeFalse
        $Evaluation.Reasons | Should -Contain '`System.Runtime.CompilerServices.Unsafe`: major'
        Should -Invoke Test-DependabotReputation -Times 3
    }

    It 'does not judge reputation for a pull request whose provenance already failed' {
        Mock Invoke-DependabotApi -ParameterFilter { $Uri -like '*/pulls/6/commits*' } { New-ApiResponse -Content @((New-Commit -Message $Script:NuGetMessage), (New-Commit -Login 'someone')) }
        Mock Invoke-DependabotApi -ParameterFilter { $Uri -like '*/pulls/6/files*' } { New-ApiResponse -Content @(New-PrFile 'Build/Dependencies/Dependencies.csproj') }
        Mock Test-DependabotReputation { throw 'should not be called' }

        $PullRequest = [PSCustomObject]@{ number = 6; user = [PSCustomObject]@{ login = 'dependabot[bot]' }; head = [PSCustomObject]@{ ref = 'dependabot/nuget/Build/Dependencies/x'; sha = 'h6' } }
        (Get-DependabotEvaluation -Repository 'o/r' -PullRequest $PullRequest -Policy $Script:Policy -Now $Script:Now).Eligible | Should -BeFalse
    }

    It 'rejects a pull request that Dependabot did not open, whatever its branch is called' {
        Mock Invoke-DependabotApi -ParameterFilter { $Uri -like '*/pulls/7/commits*' } { New-ApiResponse -Content @(New-Commit -Message $Script:NuGetMessage) }
        Mock Invoke-DependabotApi -ParameterFilter { $Uri -like '*/pulls/7/files*' } { New-ApiResponse -Content @(New-PrFile 'Build/Dependencies/Dependencies.csproj') }
        $PullRequest = [PSCustomObject]@{ number = 7; user = [PSCustomObject]@{ login = 'someone' }; head = [PSCustomObject]@{ ref = 'dependabot/nuget/fake'; sha = 'h7' } }
        $Evaluation = Get-DependabotEvaluation -Repository 'o/r' -PullRequest $PullRequest -Policy $Script:Policy -Now $Script:Now
        $Evaluation.Eligible | Should -BeFalse
        $Evaluation.Reasons | Should -Contain 'the pull request was not opened by Dependabot'
    }
}
