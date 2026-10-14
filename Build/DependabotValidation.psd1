<#
    Policy for reputation-gated validation of Dependabot pull requests
    (.github/workflows/dependabot-validation.yml).

    A Dependabot pull request that meets ALL of the following gets PR Validation started for it
    automatically, instead of waiting for a maintainer to comment /validate. Nothing here merges: a
    maintainer still reviews the result and merges, and that merge is what starts release.yml, so no
    version reaches the PowerShell Gallery without a person deciding it should. A pull request that
    falls short gets a comment explaining why and is handled exactly as before.

    AllowedUpdateTypes   - the Dependabot update types eligible for automatic validation. Every
                           dependency in the pull request must have one of these - a pull request that
                           also carries a major update (Dependabot groups a dependency with the
                           transitive updates it needs) waits for a maintainer as a whole.

    MinimumReleaseAgeDays
                         - the new version must have been published at least this long ago: by the
                           GitHub release's published_at for an action, by the registry's publication
                           date via deps.dev for a NuGet package. Dependabot security updates are
                           raised the moment an advisory is published; this keeps them from being
                           validated automatically inside the window in which a compromised release is
                           typically caught and yanked. A maintainer can still /validate one at once.

    Reputation           - the OpenSSF Scorecard of the dependency's source repository, as published by
                           deps.dev (https://deps.dev). No Scorecard - for example a package whose
                           source repository deps.dev does not know - means no reputation, which means
                           a maintainer decides.
      MinimumOverallScore      - the weighted Scorecard score, 0-10.
      MaximumScorecardAgeDays  - a Scorecard older than this is treated as missing. deps.dev refreshes
                                 them weekly, so a stale one means the project dropped out of the scan.
      MinimumCheckScore        - per-check floors on top of the overall score. A check that is missing
                                 or inconclusive (-1) fails its floor. Dangerous-Workflow is the one that
                                 matters most for supply-chain attacks: a 0 means the project's own CI
                                 can be made to run attacker-controlled code.

    Ecosystems           - per Dependabot ecosystem (the second segment of its branch name):
      AllowedFiles         - the only files a pull request may touch, all of them modified rather than
                             added or removed.
      TrustedCommitAuthors - every commit must be authored by one of these accounts AND carry a
                             signature GitHub verified; the account alone is derived from an e-mail
                             address anyone can set. github-actions[bot] is the lock refresh in
                             .github/workflows/dependency-lock-sync.yml, which commits through the API
                             so that GitHub signs its commits.
      LockFile             - when set, the pull request is not validated until this file is part of it:
                             a NuGet bump without the refreshed hash cannot pass Update-DependencyLock
                             -Check, so the lock sync runs first.
#>
@{
    AllowedUpdateTypes    = @(
        'version-update:semver-patch'
        'version-update:semver-minor'
    )

    MinimumReleaseAgeDays = 3

    Reputation            = @{
        MinimumOverallScore     = 7.0
        MaximumScorecardAgeDays = 45
        MinimumCheckScore       = @{
            'Dangerous-Workflow' = 10
        }
    }

    Ecosystems            = @{
        github_actions = @{
            AllowedFiles         = @('^\.github/workflows/[^/]+\.ya?ml$')
            TrustedCommitAuthors = @('dependabot[bot]')
            LockFile             = ''
        }
        nuget          = @{
            AllowedFiles         = @(
                '^Build/Dependencies/(Legacy/)?[^/]+\.csproj$'
                '^Build/Dependencies\.psd1$'
                '^OmadaWeb\.PS/DependencyLock\.psd1$'
            )
            TrustedCommitAuthors = @('dependabot[bot]', 'github-actions[bot]')
            LockFile             = 'OmadaWeb.PS/DependencyLock.psd1'
        }
    }
}
