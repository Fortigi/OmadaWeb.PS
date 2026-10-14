param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    $Script:RepositoryRoot = Split-Path $(Split-Path $PSScriptRoot)
    $Script:WorkflowsPath = Join-Path $Script:RepositoryRoot -ChildPath '.github\workflows'

    $Script:WorkflowFiles = @(Get-ChildItem -Path $Script:WorkflowsPath -Filter '*.yml' -File) +
        @(Get-ChildItem -Path $Script:WorkflowsPath -Filter '*.yaml' -File)

    # Matches a `uses:` step reference and captures the action, the ref it is pinned to, and the
    # trailing comment. The `@` is required, so a local action (`uses: ./some/path`) never matches:
    # it is this repository's own code, checked out with the workflow, and has nothing to pin.
    $Script:UsesPattern = '^\s*(?:-\s*)?uses:\s*(?<Action>\S+?)@(?<Ref>\S+)\s*(?:#\s*(?<Comment>.*))?$'

    $Script:UsesLines = @(foreach ($File in $Script:WorkflowFiles) {
            $LineNumber = 0
            foreach ($Line in Get-Content -LiteralPath $File.FullName) {
                $LineNumber++
                if ($Line -match $Script:UsesPattern) {
                    [PSCustomObject]@{
                        File    = $File.Name
                        Line    = $LineNumber
                        Action  = $Matches['Action']
                        Ref     = $Matches['Ref']
                        Comment = $Matches['Comment']
                        Raw     = $Line.Trim()
                    }
                }
            }
        })
}

Describe 'Workflow action pins' -Tag 'Unit' {

    It 'Should find workflow files and action references to check' {
        $Script:WorkflowFiles.Count | Should -BeGreaterThan 0 -Because 'this test exists to guard .github/workflows'
        $Script:UsesLines.Count | Should -BeGreaterThan 0 -Because 'every workflow in this repository uses at least one action'
    }

    It 'Should pin every action to a full 40-character commit SHA, not a mutable tag or branch' {
        # A tag can be moved after review; a commit SHA cannot. A moved tag on a workflow that holds
        # a write-scoped token - releasing to the PowerShell Gallery, pushing to Dependabot branches -
        # runs whatever the tag now points at with that token.
        $Unpinned = @($Script:UsesLines | Where-Object { $_.Ref -notmatch '^[0-9a-f]{40}$' })
        $Detail = ($Unpinned | ForEach-Object { '{0}:{1}  {2}' -f $_.File, $_.Line, $_.Raw }) -join "`n"
        $Unpinned | Should -BeNullOrEmpty -Because "only a commit SHA is immutable`n$Detail"
    }

    It 'Should carry a trailing version comment next to every pinned SHA' {
        # The comment is what makes the SHA reviewable, and what Dependabot rewrites together with the
        # SHA on every bump - without it Dependabot cannot tell which release a SHA belongs to.
        $Uncommented = @($Script:UsesLines | Where-Object {
                $_.Ref -match '^[0-9a-f]{40}$' -and ([string]::IsNullOrWhiteSpace($_.Comment) -or $_.Comment -notmatch '^v\d+\.\d+\.\d+')
            })
        $Detail = ($Uncommented | ForEach-Object { '{0}:{1}  {2}' -f $_.File, $_.Line, $_.Raw }) -join "`n"
        $Uncommented | Should -BeNullOrEmpty -Because "the SHA pin needs a '# vX.Y.Z' comment for review and for Dependabot`n$Detail"
    }
}
