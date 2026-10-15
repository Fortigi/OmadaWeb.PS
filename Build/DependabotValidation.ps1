<#
    Functions behind reputation-gated validation of Dependabot pull requests
    (.github/workflows/dependabot-validation.yml). Policy in Build/DependabotValidation.psd1, which
    explains every threshold.

    Dot-sourced by Build/Invoke-DependabotValidation.ps1 and by
    Tests/Unit/DependabotValidation.Tests.ps1. Like the rest of this repository it runs on Windows
    PowerShell 5.1 as well as PowerShell 7: no -SkipHttpErrorCheck, no -AdditionalChildPath, and JSON
    dates are accepted both as the DateTime PowerShell 7 turns them into and as the plain string
    Windows PowerShell leaves them. Members that a response may lack are read through
    Get-DependabotProperty, so the code also holds under Set-StrictMode -Version Latest.

    These functions only DECIDE - whether a pull request is eligible, and whether its lock file still
    needs refreshing first - and say why in one comment on the pull request. Starting the lock refresh
    or PR Validation is left to the workflow.

    All network access goes through Invoke-DependabotApi, which is what the tests mock.
#>

$Script:DependabotCommentMarker = '<!-- dependabot-validation -->'

function Get-DependabotProperty {
    <#
    .SYNOPSIS
        The value of a member that may be absent - $null instead of a StrictMode error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }
    $Property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $Property) {
        return $null
    }
    return $Property.Value
}

function Get-DependabotPolicy {
    <#
    .SYNOPSIS
        Reads Build/DependabotValidation.psd1.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return (Import-PowerShellDataFile -Path $Path)
}

function Invoke-DependabotApi {
    <#
    .SYNOPSIS
        One REST call. An HTTP error status is an answer, not an exception: it returns StatusCode and
        Content either way, so a 404 means "no such release" rather than a failed run. Only a failure
        to get any HTTP response at all throws.
    .DESCRIPTION
        The GITHUB_TOKEN is attached only to requests for api.github.com - never to deps.dev or any
        other host a URL might point at.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [ValidateSet('Get', 'Post', 'Patch')]
        [string]$Method = 'Get',

        [object]$Body
    )

    $Headers = @{ 'User-Agent' = 'OmadaWeb.PS-dependabot-validation' }
    if (([uri]$Uri).Host -eq 'api.github.com') {
        $Headers['Accept'] = 'application/vnd.github+json'
        $Headers['X-GitHub-Api-Version'] = '2022-11-28'
        if (-not [string]::IsNullOrEmpty($env:GITHUB_TOKEN)) {
            $Headers['Authorization'] = 'Bearer {0}' -f $env:GITHUB_TOKEN
        }
    }

    $Request = @{
        Uri             = $Uri
        Method          = $Method
        Headers         = $Headers
        UseBasicParsing = $true
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $Request['Body'] = [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 10 -Compress))
        $Request['ContentType'] = 'application/json; charset=utf-8'
    }

    $StatusCode = 0
    $Text = $null
    try {
        $Response = Invoke-WebRequest @Request
        $StatusCode = [int]$Response.StatusCode
        $Text = [string]$Response.Content
    }
    catch {
        # Windows PowerShell throws a WebException, PowerShell 7 an HttpResponseException; both carry
        # the response, with a StatusCode, when there was one.
        $HttpResponse = Get-DependabotProperty -InputObject $_.Exception -Name 'Response'
        if ($null -eq $HttpResponse) {
            throw
        }
        $StatusCode = [int](Get-DependabotProperty -InputObject $HttpResponse -Name 'StatusCode')
        if ($null -ne $_.ErrorDetails) {
            $Text = $_.ErrorDetails.Message
        }
    }

    $Content = $null
    if (-not [string]::IsNullOrWhiteSpace($Text)) {
        try {
            # Assigned before use: Windows PowerShell's ConvertFrom-Json emits a JSON array as one
            # object, and only an assignment keeps that from being wrapped in a second array.
            $Content = $Text | ConvertFrom-Json
        }
        catch {
            $Content = $Text
        }
    }
    return [PSCustomObject]@{
        StatusCode = $StatusCode
        Content    = $Content
    }
}

function ConvertTo-DependabotUtcDate {
    <#
    .SYNOPSIS
        A JSON timestamp as UTC, whether ConvertFrom-Json already made it a DateTime (PowerShell 7) or
        left it a string (Windows PowerShell).
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    if ($Value -is [datetime]) {
        return ([datetimeoffset]$Value).UtcDateTime
    }
    return [datetimeoffset]::Parse([string]$Value, [cultureinfo]::InvariantCulture).UtcDateTime
}

function Get-DependabotEcosystem {
    <#
    .SYNOPSIS
        The ecosystem segment of a Dependabot branch name: dependabot/<ecosystem>/..., for example
        github_actions or nuget. $null for any other branch.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    if ($BranchName -match '^dependabot/(?<Ecosystem>[^/]+)/') {
        return $Matches['Ecosystem']
    }
    return $null
}

function ConvertFrom-DependabotCommitMessage {
    <#
    .SYNOPSIS
        The dependencies a Dependabot commit updates, from the metadata block it ends every commit
        message with - the block dependabot/fetch-metadata parses:

            ---
            updated-dependencies:
            - dependency-name: Example.Package
              dependency-version: 1.2.3
              dependency-type: direct:production
              update-type: version-update:semver-minor
            ...

        When an older message carries no dependency-version, the version is taken from its
        "Updates `x` from a to b" or "Bumps x from a to b." line instead.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    $Block = [regex]::Match($Message, '(?ms)^updated-dependencies:[ \t]*\r?$(?<Body>.*?)^\.\.\.[ \t]*\r?$')
    if (-not $Block.Success) {
        return @()
    }

    $Quotes = [char[]]@([char]39, [char]34)
    $Dependencies = New-Object System.Collections.Generic.List[hashtable]
    $Current = $null
    foreach ($Line in ($Block.Groups['Body'].Value -split '\r?\n')) {
        if ($Line -match '^\s*-\s+dependency-name:\s*(?<Value>.+?)\s*$') {
            $Current = @{
                Name           = $Matches['Value'].Trim($Quotes)
                Version        = $null
                DependencyType = $null
                UpdateType     = $null
            }
            $Dependencies.Add($Current)
            continue
        }
        if ($null -eq $Current -or $Line -notmatch '^\s+(?<Key>[a-z-]+):\s*(?<Value>.+?)\s*$') {
            continue
        }
        $Value = $Matches['Value'].Trim($Quotes)
        switch ($Matches['Key']) {
            'dependency-version' { $Current.Version = $Value }
            'dependency-type' { $Current.DependencyType = $Value }
            'update-type' { $Current.UpdateType = $Value }
        }
    }

    foreach ($Dependency in $Dependencies) {
        if ([string]::IsNullOrEmpty($Dependency.Version)) {
            $Name = [regex]::Escape($Dependency.Name)
            $Line = [regex]::Match($Message, ('(?m)^Updates `{0}` (?:from \S+ )?to (?<To>\S+?)\.?\s*$' -f $Name))
            if (-not $Line.Success) {
                $Line = [regex]::Match($Message, ('(?m)^Bumps \[?{0}\]?(?:\([^)]*\))? from \S+ to (?<To>\S+?)\.?\s*$' -f $Name))
            }
            if ($Line.Success) {
                $Dependency.Version = $Line.Groups['To'].Value
            }
        }
        [PSCustomObject]$Dependency
    }
}

function Get-DependabotScorecard {
    <#
    .SYNOPSIS
        The OpenSSF Scorecard deps.dev holds for a project key such as github.com/seleniumhq/selenium,
        or $null when it has none.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectKey
    )

    foreach ($Candidate in @($ProjectKey, $ProjectKey.ToLowerInvariant()) | Select-Object -Unique) {
        $Response = Invoke-DependabotApi -Uri ('https://api.deps.dev/v3/projects/{0}' -f [uri]::EscapeDataString($Candidate))
        $Scorecard = Get-DependabotProperty -InputObject $Response.Content -Name 'scorecard'
        if ($Response.StatusCode -eq 200 -and $null -ne $Scorecard) {
            return $Scorecard
        }
    }
    return $null
}

function Get-DependabotNuGetProvenance {
    <#
    .SYNOPSIS
        When a NuGet package version was published, and the source repository deps.dev links it to.
        $null when deps.dev does not know the version at all.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    # nuget.org ids are case-insensitive; deps.dev may key them either way, so try both.
    foreach ($Candidate in @($Name, $Name.ToLowerInvariant()) | Select-Object -Unique) {
        $Uri = 'https://api.deps.dev/v3/systems/nuget/packages/{0}/versions/{1}' -f [uri]::EscapeDataString($Candidate), [uri]::EscapeDataString($Version)
        $Response = Invoke-DependabotApi -Uri $Uri
        if ($Response.StatusCode -ne 200) {
            continue
        }
        $Source = @(Get-DependabotProperty -InputObject $Response.Content -Name 'relatedProjects') |
            Where-Object { $null -ne $_ -and (Get-DependabotProperty -InputObject $_ -Name 'relationType') -eq 'SOURCE_REPO' } |
            Select-Object -First 1
        $PublishedAt = Get-DependabotProperty -InputObject $Response.Content -Name 'publishedAt'
        return [PSCustomObject]@{
            PublishedAt = $(if ($PublishedAt) { ConvertTo-DependabotUtcDate -Value $PublishedAt } else { $null })
            ProjectKey  = $(if ($Source) { Get-DependabotProperty -InputObject (Get-DependabotProperty -InputObject $Source -Name 'projectKey') -Name 'id' } else { $null })
        }
    }
    return $null
}

function Get-DependabotActionRelease {
    <#
    .SYNOPSIS
        The published GitHub release behind an action version, or $null. Dependabot reports the
        version without a leading v for most actions while the tag usually has one, so both spellings
        are tried. published_at is set by GitHub, so unlike a commit date it cannot be backdated.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $Tags = if ($Version -like 'v*') { @($Version, $Version.Substring(1)) } else { @("v$Version", $Version) }
    foreach ($Tag in $Tags) {
        $Response = Invoke-DependabotApi -Uri ('https://api.github.com/repos/{0}/releases/tags/{1}' -f $Repository, [uri]::EscapeDataString($Tag))
        if ($Response.StatusCode -eq 200 -and -not (Get-DependabotProperty -InputObject $Response.Content -Name 'draft')) {
            return [PSCustomObject]@{
                Tag         = $Tag
                PublishedAt = ConvertTo-DependabotUtcDate -Value (Get-DependabotProperty -InputObject $Response.Content -Name 'published_at')
                Prerelease  = [bool](Get-DependabotProperty -InputObject $Response.Content -Name 'prerelease')
            }
        }
    }
    return $null
}

function Test-DependabotScorecard {
    <#
    .SYNOPSIS
        Why a Scorecard falls short of the Reputation policy - an empty list when it does not.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Scorecard,

        [Parameter(Mandatory = $true)]
        [string]$ProjectKey,

        [Parameter(Mandatory = $true)]
        [hashtable]$Policy,

        [Parameter(Mandatory = $true)]
        [datetime]$Now
    )

    if ($null -eq $Scorecard) {
        return @("deps.dev has no OpenSSF Scorecard for $ProjectKey")
    }

    $Reasons = New-Object System.Collections.Generic.List[string]
    $Score = [double](Get-DependabotProperty -InputObject $Scorecard -Name 'overallScore')
    if ($Score -lt [double]$Policy.MinimumOverallScore) {
        $Reasons.Add(('Scorecard {0} for {1} is below the minimum of {2}' -f $Score.ToString('0.0', [cultureinfo]::InvariantCulture), $ProjectKey, ([double]$Policy.MinimumOverallScore).ToString('0.0', [cultureinfo]::InvariantCulture)))
    }

    $Date = Get-DependabotProperty -InputObject $Scorecard -Name 'date'
    if ($null -eq $Date) {
        $Reasons.Add(('Scorecard for {0} carries no date' -f $ProjectKey))
    }
    else {
        $Age = ($Now - (ConvertTo-DependabotUtcDate -Value $Date)).TotalDays
        if ($Age -gt $Policy.MaximumScorecardAgeDays) {
            $Reasons.Add(('Scorecard for {0} is {1} days old, more than the {2} allowed' -f $ProjectKey, [math]::Round($Age), $Policy.MaximumScorecardAgeDays))
        }
    }

    foreach ($CheckName in @($Policy.MinimumCheckScore.Keys | Sort-Object)) {
        $Minimum = [int]$Policy.MinimumCheckScore[$CheckName]
        $Check = @(Get-DependabotProperty -InputObject $Scorecard -Name 'checks') |
            Where-Object { $null -ne $_ -and (Get-DependabotProperty -InputObject $_ -Name 'name') -eq $CheckName } |
            Select-Object -First 1
        if ($null -eq $Check) {
            $Reasons.Add(('Scorecard for {0} has no {1} check' -f $ProjectKey, $CheckName))
        }
        elseif ([int](Get-DependabotProperty -InputObject $Check -Name 'score') -lt $Minimum) {
            $Reasons.Add(('Scorecard check {0} for {1} is {2}, below the minimum of {3}' -f $CheckName, $ProjectKey, [int](Get-DependabotProperty -InputObject $Check -Name 'score'), $Minimum))
        }
    }
    return $Reasons.ToArray()
}

function Test-DependabotReputation {
    <#
    .SYNOPSIS
        Judges one updated dependency against the policy: update type, release age, and the OpenSSF
        Scorecard of its source repository. Eligible only when nothing fell short.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Dependency,

        [Parameter(Mandatory = $true)]
        [string]$Ecosystem,

        [Parameter(Mandatory = $true)]
        [hashtable]$Policy,

        [Parameter(Mandatory = $true)]
        [datetime]$Now
    )

    $Reasons = New-Object System.Collections.Generic.List[string]
    $Result = [ordered]@{
        Name        = $Dependency.Name
        Version     = $Dependency.Version
        UpdateType  = $Dependency.UpdateType
        ProjectKey  = $null
        Score       = $null
        PublishedAt = $null
        Eligible    = $false
        Reasons     = $Reasons
    }

    if ($Dependency.UpdateType -notin $Policy.AllowedUpdateTypes) {
        $Reasons.Add(("update type '{0}' is not eligible for automatic validation" -f $Dependency.UpdateType))
        return [PSCustomObject]$Result
    }
    if ([string]::IsNullOrEmpty($Dependency.Version)) {
        $Reasons.Add('the Dependabot commit does not say which version it updates to')
        return [PSCustomObject]$Result
    }

    switch ($Ecosystem) {
        'github_actions' {
            $Segments = $Dependency.Name -split '/'
            if ($Segments.Count -lt 2) {
                $Reasons.Add(("'{0}' is not an owner/repository action reference" -f $Dependency.Name))
                break
            }
            $Repository = '{0}/{1}' -f $Segments[0], $Segments[1]
            $Result.ProjectKey = 'github.com/{0}' -f $Repository
            $Release = Get-DependabotActionRelease -Repository $Repository -Version $Dependency.Version
            if ($null -eq $Release) {
                $Reasons.Add(('{0} has no published GitHub release for {1}, so its age cannot be established' -f $Repository, $Dependency.Version))
            }
            elseif ($Release.Prerelease) {
                $Reasons.Add(('{0} {1} is a prerelease' -f $Repository, $Release.Tag))
            }
            else {
                $Result.PublishedAt = $Release.PublishedAt
            }
        }
        'nuget' {
            $Provenance = Get-DependabotNuGetProvenance -Name $Dependency.Name -Version $Dependency.Version
            if ($null -eq $Provenance) {
                $Reasons.Add(('deps.dev does not know {0} {1}' -f $Dependency.Name, $Dependency.Version))
                break
            }
            $Result.PublishedAt = $Provenance.PublishedAt
            $Result.ProjectKey = $Provenance.ProjectKey
            if ($null -eq $Provenance.PublishedAt) {
                $Reasons.Add(('deps.dev reports no publication date for {0} {1}' -f $Dependency.Name, $Dependency.Version))
            }
            if ([string]::IsNullOrEmpty($Provenance.ProjectKey)) {
                $Reasons.Add(('deps.dev links {0} to no source repository, so there is no Scorecard to judge it by' -f $Dependency.Name))
            }
        }
        default {
            $Reasons.Add(("ecosystem '{0}' has no reputation source" -f $Ecosystem))
        }
    }

    if ($null -ne $Result.PublishedAt) {
        $AgeDays = ($Now - $Result.PublishedAt).TotalDays
        if ($AgeDays -lt $Policy.MinimumReleaseAgeDays) {
            $Reasons.Add(('{0} {1} was published {2} days ago, less than the {3} required' -f $Dependency.Name, $Dependency.Version, $AgeDays.ToString('0.0', [cultureinfo]::InvariantCulture), $Policy.MinimumReleaseAgeDays))
        }
    }

    if (-not [string]::IsNullOrEmpty($Result.ProjectKey)) {
        $Scorecard = Get-DependabotScorecard -ProjectKey $Result.ProjectKey
        if ($null -ne $Scorecard) {
            $Result.Score = [double](Get-DependabotProperty -InputObject $Scorecard -Name 'overallScore')
        }
        foreach ($Reason in (Test-DependabotScorecard -Scorecard $Scorecard -ProjectKey $Result.ProjectKey -Policy $Policy.Reputation -Now $Now)) {
            $Reasons.Add($Reason)
        }
    }

    $Result.Eligible = ($Reasons.Count -eq 0)
    return [PSCustomObject]$Result
}

function Test-DependabotProvenance {
    <#
    .SYNOPSIS
        Whether a pull request is still purely Dependabot's bump plus this repository's own signed
        workflow commits, and touches nothing outside the files its ecosystem may change.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Commit,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$File,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Ecosystem,

        [Parameter(Mandatory = $true)]
        [hashtable]$Policy
    )

    $Reasons = New-Object System.Collections.Generic.List[string]
    $EcosystemPolicy = $null
    if (-not [string]::IsNullOrEmpty($Ecosystem) -and $Policy.Ecosystems.ContainsKey($Ecosystem)) {
        $EcosystemPolicy = $Policy.Ecosystems[$Ecosystem]
    }
    if ($null -eq $EcosystemPolicy) {
        $Reasons.Add(("ecosystem '{0}' is not configured for automatic validation" -f $Ecosystem))
        return [PSCustomObject]@{ Eligible = $false; Reasons = $Reasons.ToArray() }
    }

    $Login = { param($Item) Get-DependabotProperty -InputObject (Get-DependabotProperty -InputObject $Item -Name 'author') -Name 'login' }

    if ($Commit.Count -eq 0) {
        $Reasons.Add('the pull request has no commits')
    }
    elseif ((& $Login $Commit[0]) -ne 'dependabot[bot]') {
        $Reasons.Add('the first commit is not Dependabot''s')
    }
    foreach ($Item in $Commit) {
        $Author = & $Login $Item
        $Sha = [string](Get-DependabotProperty -InputObject $Item -Name 'sha')
        $ShortSha = $Sha.Substring(0, [Math]::Min(7, $Sha.Length))
        $Verified = Get-DependabotProperty -InputObject (Get-DependabotProperty -InputObject (Get-DependabotProperty -InputObject $Item -Name 'commit') -Name 'verification') -Name 'verified'
        if ([string]::IsNullOrEmpty($Author)) {
            $Reasons.Add(('commit {0} is not attributed to any GitHub account' -f $ShortSha))
        }
        elseif ($Author -notin $EcosystemPolicy.TrustedCommitAuthors) {
            $Reasons.Add(("commit {0} is authored by '{1}', not by a trusted bot" -f $ShortSha, $Author))
        }
        elseif (-not $Verified) {
            $Reasons.Add(('commit {0} by {1} has no signature GitHub verified' -f $ShortSha, $Author))
        }
    }

    foreach ($Item in $File) {
        $Name = [string](Get-DependabotProperty -InputObject $Item -Name 'filename')
        $Status = [string](Get-DependabotProperty -InputObject $Item -Name 'status')
        if ($Status -ne 'modified') {
            $Reasons.Add(('{0} is {1}; only modified files are expected' -f $Name, $Status))
            continue
        }
        $Allowed = @($EcosystemPolicy.AllowedFiles | Where-Object { $Name -match $_ }).Count -gt 0
        if (-not $Allowed) {
            $Reasons.Add(('{0} is outside the files a {1} update may change' -f $Name, $Ecosystem))
        }
    }

    return [PSCustomObject]@{
        Eligible = ($Reasons.Count -eq 0)
        Reasons  = $Reasons.ToArray()
    }
}

function Get-DependabotNextStep {
    <#
    .SYNOPSIS
        What the workflow does for an evaluated pull request: nothing, refresh the lock file first, or
        start PR Validation.
    .DESCRIPTION
        LockSynced is passed when the lock refresh itself asked for this evaluation. It then never
        asks for another refresh, whatever the files say, so the two workflows cannot start each other
        in a loop.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Evaluation,

        [Parameter(Mandatory = $true)]
        [hashtable]$Policy,

        [switch]$LockSynced
    )

    if (-not $Evaluation.Eligible) {
        return 'none'
    }
    $LockFile = ''
    if ($Policy.Ecosystems.ContainsKey([string]$Evaluation.Ecosystem)) {
        $LockFile = [string]$Policy.Ecosystems[[string]$Evaluation.Ecosystem].LockFile
    }
    if (-not $LockSynced -and -not [string]::IsNullOrEmpty($LockFile) -and $LockFile -notin $Evaluation.Files) {
        return 'sync-lock'
    }
    return 'validate'
}

function Format-DependabotReport {
    <#
    .SYNOPSIS
        The markdown for the pull request comment and the job summary. Free of timestamps and run ids,
        so an unchanged evaluation produces an identical body and the comment is not rewritten.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Evaluation,

        [Parameter(Mandatory = $true)]
        [ValidateSet('none', 'sync-lock', 'validate')]
        [string]$NextStep
    )

    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add($Script:DependabotCommentMarker)
    $Lines.Add('### Dependabot validation')
    $Lines.Add('')
    switch ($NextStep) {
        'validate' { $Lines.Add('**Eligible.** PR Validation was started for this head. A maintainer reviews the result and merges; nothing here merges on its own.') }
        'sync-lock' { $Lines.Add('**Eligible.** The pinned hashes are being refreshed first; PR Validation starts once they are committed.') }
        default { $Lines.Add('**Manual review required.** This pull request does not meet the policy for automatic validation; a maintainer reviews it and comments `/validate` as usual.') }
    }
    $Lines.Add('')

    if (@($Evaluation.Dependencies).Count -gt 0) {
        $Lines.Add('| Dependency | Version | Update type | Source repository | Scorecard | Published | Result |')
        $Lines.Add('|---|---|---|---|---|---|---|')
        foreach ($Dependency in $Evaluation.Dependencies) {
            $Lines.Add(('| `{0}` | {1} | {2} | {3} | {4} | {5} | {6} |' -f
                    $Dependency.Name,
                    $Dependency.Version,
                    ([string]$Dependency.UpdateType -replace '^version-update:', ''),
                    $(if ($Dependency.ProjectKey) { $Dependency.ProjectKey } else { '-' }),
                    $(if ($null -ne $Dependency.Score) { ([double]$Dependency.Score).ToString('0.0', [cultureinfo]::InvariantCulture) } else { '-' }),
                    $(if ($Dependency.PublishedAt) { $Dependency.PublishedAt.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture) } else { '-' }),
                    $(if ($Dependency.Eligible) { 'pass' } else { 'fail' })))
        }
        $Lines.Add('')
    }

    if (@($Evaluation.Reasons).Count -gt 0) {
        $Lines.Add('Why:')
        $Lines.Add('')
        foreach ($Reason in $Evaluation.Reasons) {
            $Lines.Add(('- {0}' -f $Reason))
        }
        $Lines.Add('')
    }

    $Lines.Add(('<sub>Evaluated head `{0}` against `Build/DependabotValidation.psd1`. Scorecard data: deps.dev (OpenSSF Scorecard).</sub>' -f $Evaluation.HeadSha))
    return ($Lines -join "`n")
}

function Set-DependabotComment {
    <#
    .SYNOPSIS
        Creates the pull request's validation comment, or edits the existing one when the body
        changed. One comment per pull request, never a new one per run.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [int]$Number,

        [Parameter(Mandatory = $true)]
        [string]$Body
    )

    $Comments = @((Invoke-DependabotApi -Uri ('https://api.github.com/repos/{0}/issues/{1}/comments?per_page=100' -f $Repository, $Number)).Content)
    $Existing = $Comments | Where-Object {
        $null -ne $_ -and
        (Get-DependabotProperty -InputObject (Get-DependabotProperty -InputObject $_ -Name 'user') -Name 'login') -eq 'github-actions[bot]' -and
        ([string](Get-DependabotProperty -InputObject $_ -Name 'body')).StartsWith($Script:DependabotCommentMarker)
    } | Select-Object -First 1

    if ($null -ne $Existing -and (([string]$Existing.body) -replace "`r`n", "`n") -eq $Body) {
        return
    }
    if (-not $PSCmdlet.ShouldProcess(('#{0}' -f $Number), 'Write validation comment')) {
        return
    }
    if ($null -ne $Existing) {
        $null = Invoke-DependabotApi -Method Patch -Uri ('https://api.github.com/repos/{0}/issues/comments/{1}' -f $Repository, $Existing.id) -Body @{ body = $Body }
    }
    else {
        $null = Invoke-DependabotApi -Method Post -Uri ('https://api.github.com/repos/{0}/issues/{1}/comments' -f $Repository, $Number) -Body @{ body = $Body }
    }
}

function Get-DependabotEvaluation {
    <#
    .SYNOPSIS
        Reads one Dependabot pull request and judges it against the policy: provenance first, then
        every dependency's reputation. Makes no changes.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$PullRequest,

        [Parameter(Mandatory = $true)]
        [hashtable]$Policy,

        [Parameter(Mandatory = $true)]
        [datetime]$Now
    )

    $Number = [int]$PullRequest.number
    $Branch = [string]$PullRequest.head.ref
    $Ecosystem = Get-DependabotEcosystem -BranchName $Branch
    $Commits = @((Invoke-DependabotApi -Uri ('https://api.github.com/repos/{0}/pulls/{1}/commits?per_page=100' -f $Repository, $Number)).Content)
    $Files = @((Invoke-DependabotApi -Uri ('https://api.github.com/repos/{0}/pulls/{1}/files?per_page=100' -f $Repository, $Number)).Content)

    $Reasons = New-Object System.Collections.Generic.List[string]
    if ([string](Get-DependabotProperty -InputObject (Get-DependabotProperty -InputObject $PullRequest -Name 'user') -Name 'login') -ne 'dependabot[bot]') {
        $Reasons.Add('the pull request was not opened by Dependabot')
    }
    $Provenance = Test-DependabotProvenance -Commit $Commits -File $Files -Ecosystem ([string]$Ecosystem) -Policy $Policy
    foreach ($Reason in $Provenance.Reasons) { $Reasons.Add($Reason) }

    $Dependencies = @()
    if ($Reasons.Count -eq 0) {
        $Message = [string](Get-DependabotProperty -InputObject (Get-DependabotProperty -InputObject $Commits[0] -Name 'commit') -Name 'message')
        $Parsed = @(ConvertFrom-DependabotCommitMessage -Message $Message)
        if ($Parsed.Count -eq 0) {
            $Reasons.Add('the Dependabot commit carries no updated-dependencies metadata')
        }
        $Dependencies = @(foreach ($Dependency in $Parsed) {
                Test-DependabotReputation -Dependency $Dependency -Ecosystem $Ecosystem -Policy $Policy -Now $Now
            })
        foreach ($Dependency in $Dependencies) {
            foreach ($Reason in $Dependency.Reasons) {
                $Reasons.Add(('`{0}`: {1}' -f $Dependency.Name, $Reason))
            }
        }
    }

    return [PSCustomObject]@{
        Number       = $Number
        Branch       = $Branch
        HeadSha      = [string]$PullRequest.head.sha
        Ecosystem    = $Ecosystem
        Eligible     = ($Reasons.Count -eq 0)
        Reasons      = $Reasons.ToArray()
        Dependencies = $Dependencies
        Files        = @($Files | ForEach-Object { [string](Get-DependabotProperty -InputObject $_ -Name 'filename') })
    }
}
