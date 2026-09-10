function Get-EntraTenantMismatchDetail {
    <#
    .SYNOPSIS
        Reads the identifiers Entra ID names when it refuses a sign-in from another tenant.

    .DESCRIPTION
        A federated sign-in that fails because the account belongs to a different tenant than the
        application comes back through Omada's logon page as one long sentence:

            OpenIdConnectMessage.Error was not null, indicating an error. Error: 'invalid_request'.
            Error_Description (may be empty): 'AADSTS50178: User account '{EUII Hidden}' from
            identity provider 'https://sts.windows.net/<tenant id>/' does not exist in tenant
            '<tenant name>' and cannot access the application '<application id>'(<application name>)
            in that tenant. ... Trace ID: <guid> Correlation ID: <guid> Timestamp: <utc>'

        Everything a person needs in order to act on it is in there, and none of it is where they
        can see it: the tenant the account came from, the tenant and application it was refused by,
        and the correlation ID that finds the attempt in the sign-in logs. This function lifts those
        out so the refusal can be reported as facts instead of as one wall of quoted text.

        WHAT IT CANNOT RECOVER

        The account name. Entra deliberately replaces it with the literal '{EUII Hidden}', because
        the sentence is rendered by the application and end-user identifiable information does not
        belong there. AccountNameWithheld records that this happened, so the caller can say the name
        is withheld by Entra rather than leave a reader hunting for a name that was never sent - and
        point at the correlation ID, which is how the account is looked up in the tenant that
        refused it.

        WHY THE PATTERNS ARE LOOSE

        The numbers and identifiers are stable across languages, the sentence around them is not, and
        neither is the shape of what Entra quotes. The tenant identifier is taken as the last
        identifier-shaped segment of the issuer URL rather than as a strict GUID, because the same
        clause carries a v2.0 issuer ('.../<tenant id>/v2.0') as well as the classic one, and because
        a value that does not parse as a GUID is still worth reporting. Anything that cannot be found
        is left null rather than guessed at, and HasDetail says whether anything was found at all.

    .PARAMETER Message
        The error text read off the Omada logon page.

    .OUTPUTS
        PSCustomObject with the members HasDetail, AccountTenantId, ResourceTenant, ApplicationId,
        ApplicationName, TraceId, CorrelationId, Timestamp and AccountNameWithheld.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message
    )

    $Detail = [pscustomobject]@{
        HasDetail           = $false
        AccountTenantId     = $null
        ResourceTenant      = $null
        ApplicationId       = $null
        ApplicationName     = $null
        TraceId             = $null
        CorrelationId       = $null
        Timestamp           = $null
        AccountNameWithheld = $false
    }

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $Detail
    }

    # The page text arrives with the line breaks and indentation of the markup around it, exactly as
    # Test-OmadaLogonPageError receives it, so the patterns below can assume single spaces.
    $Text = ($Message -replace '\s+', ' ').Trim()

    # The issuer of the account's own tenant. Quoted as a URL, so the identifier is the last segment
    # that looks like one - which is the tenant id for both 'https://sts.windows.net/<id>/' and
    # 'https://login.microsoftonline.com/<id>/v2.0'.
    $IssuerMatch = [regex]::Match($Text, "(?i)identity provider\s+'([^']+)'")
    if ($IssuerMatch.Success) {
        $Segment = @($IssuerMatch.Groups[1].Value -split '/' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $Identifier = @($Segment | Where-Object { $_ -match '^[0-9a-fA-F][0-9a-fA-F-]{7,}$' })
        if ($Identifier.Count -gt 0) {
            $Detail.AccountTenantId = $Identifier[-1]
        }
        elseif ($Segment.Count -gt 0) {
            $Detail.AccountTenantId = $Segment[-1]
        }
    }

    $TenantMatch = [regex]::Match($Text, "(?i)does not exist in tenant\s+'([^']*)'")
    if ($TenantMatch.Success -and -not [string]::IsNullOrWhiteSpace($TenantMatch.Groups[1].Value)) {
        $Detail.ResourceTenant = $TenantMatch.Groups[1].Value
    }

    # The application is quoted as '<id>'(<display name>), and the display name is free text that
    # routinely contains brackets of its own - "Contoso (Omada)" is the shape this was written
    # against. Closing on the ')' that precedes 'in that tenant' therefore keeps the whole name; the
    # fallback exists for a sentence in another language, where the trailing clause reads
    # differently but the brackets do not move.
    $ApplicationMatch = [regex]::Match($Text, "(?i)application\s+'([^']+)'\s*\((.+?)\)\s*in that tenant")
    if (-not $ApplicationMatch.Success) {
        $ApplicationMatch = [regex]::Match($Text, "(?i)application\s+'([^']+)'\s*\(([^)]*)\)")
    }
    if (-not $ApplicationMatch.Success) {
        $ApplicationMatch = [regex]::Match($Text, "(?i)application\s+'([^']+)'")
    }
    if ($ApplicationMatch.Success) {
        $Detail.ApplicationId = $ApplicationMatch.Groups[1].Value
        if ($ApplicationMatch.Groups.Count -gt 2 -and -not [string]::IsNullOrWhiteSpace($ApplicationMatch.Groups[2].Value)) {
            $Detail.ApplicationName = $ApplicationMatch.Groups[2].Value.Trim()
        }
    }

    $TraceMatch = [regex]::Match($Text, "(?i)Trace ID:\s*([^\s']+)")
    if ($TraceMatch.Success) {
        $Detail.TraceId = $TraceMatch.Groups[1].Value
    }

    $CorrelationMatch = [regex]::Match($Text, "(?i)Correlation ID:\s*([^\s']+)")
    if ($CorrelationMatch.Success) {
        $Detail.CorrelationId = $CorrelationMatch.Groups[1].Value
    }

    # Reported as Entra wrote it - it is UTC, and re-formatting it would only invite a reader to
    # compare it against a local clock.
    $TimestampMatch = [regex]::Match($Text, "(?i)Timestamp:\s*(\d{4}-\d{2}-\d{2}[ T][\d:.]+Z?)")
    if ($TimestampMatch.Success) {
        $Detail.Timestamp = $TimestampMatch.Groups[1].Value.Trim()
    }

    $Detail.AccountNameWithheld = $Text -match '(?i)\{EUII Hidden\}'

    # A plain loop rather than a pipeline: HasDetail is a boolean the callers branch on, and a
    # pipeline that filters to nothing yields $null instead of $false - which is the difference
    # between "no detail" and a terminating error under StrictMode.
    foreach ($Value in @($Detail.AccountTenantId, $Detail.ResourceTenant, $Detail.ApplicationId, $Detail.TraceId, $Detail.CorrelationId)) {
        if (-not [string]::IsNullOrWhiteSpace($Value)) {
            $Detail.HasDetail = $true
            break
        }
    }

    return $Detail
}
