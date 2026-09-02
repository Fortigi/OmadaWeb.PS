#Requires -Version 7.0

<#
.SYNOPSIS
    Provisions the Entra ID objects the scheduled sign-in canary needs, in a tenant you control.
.DESCRIPTION
    The canary (roadmap E5, issue #33) signs in to Microsoft Entra ID once a day with a real account
    in a real browser, so that a change to Microsoft's sign-in page is reported by CI instead of by
    the first user who hits it. That needs three things in a tenant: an account that can sign in with
    a password and nothing else, an application to sign in to, and a documented reason why the
    account is not challenged for multi-factor authentication.

    This script creates all three, and is safe to run again: every object is looked up before it is
    created, and an existing one is updated in place rather than duplicated.

    WHAT IT CREATES

      1. A canary user in the tenant's initial domain, with a freshly generated password, no licence,
         no directory role and no group membership. Signing in is the only thing it can do.
      2. A public-client application registration whose only redirect URI is the loopback address the
         canary listens on, requesting the delegated permissions openid, profile and User.Read - and
         with admin consent granted for them. The consent matters: an unconsented application shows a
         consent screen, the sign-in automation does not recognize that screen, and the canary would
         go red for a reason that has nothing to do with Microsoft changing anything.
      3. A Conditional Access policy that blocks the canary account from every application except the
         canary one. This is the containment: the account is powerless elsewhere by policy, not
         merely by holding no permissions.

    WHAT IT DOES ABOUT MFA

      An interactive approval cannot be automated, so the canary account has to be exempt. The
      exemption is made explicit rather than left implicit:

        - Security defaults are reported, and disabled only if you pass -DisableSecurityDefaults.
        - Every existing Conditional Access policy that requires multi-factor authentication gets the
          canary account added to its excluded users, so the exemption is a reviewable entry on each
          policy rather than an absence somebody has to infer.

      Both are reported in the summary, so a tenant where MFA is still enforced on this account is
      visible before the canary is ever scheduled.

    WHAT IT DOES NOT DO

      It does not write your tenant's identifiers anywhere. The values the workflow needs are
      returned to you as an object, or pushed straight into GitHub with -GitHubRepository so they
      never appear on screen at all. Nothing in this repository records them.

    LICENSING

      Conditional Access needs Microsoft Entra ID P1 (a P2 trial includes it). Without it, pass
      -SkipConditionalAccess: the account is then contained only by holding no permissions, which is
      weaker, and the summary says so. See docs/entra-canary.md.
.PARAMETER UserPrincipalNamePrefix
    Mailbox part of the canary account's user principal name. The tenant's initial
    <tenant>.onmicrosoft.com domain is appended.
.PARAMETER ApplicationDisplayName
    Display name of the app registration the canary signs in to.
.PARAMETER Port
    Loopback port the canary listens on, which determines the registered redirect URI. Entra ignores
    the port when matching a localhost redirect URI on a public client, so this mainly has to agree
    with OMADAWEBPS_CANARY_PORT in the workflow.
.PARAMETER AllowedIpRange
    CIDR ranges the canary account is allowed to sign in from. When supplied, a named location is
    created and a second Conditional Access policy blocks the account from anywhere else.

    Deliberately a list you supply rather than a switch that fetches GitHub's ranges: GitHub-hosted
    runners publish thousands of CIDRs, which exceeds the 2000 ranges Entra allows in one named
    location, and they change without notice. IP restriction is therefore worth having on a
    self-hosted or fixed-egress runner and is impractical on a GitHub-hosted one. Left empty, the
    containment policy alone is relied on.
.PARAMETER DisableSecurityDefaults
    Turns security defaults off if they are on. Without this the script only reports them, because
    turning them off changes the security posture of the whole tenant and that is not a side effect
    a provisioning script should have on its own.
.PARAMETER SkipConditionalAccess
    Skips every Conditional Access change, for a tenant without Entra ID P1. The account is then
    contained only by holding no permissions.
.PARAMETER GitHubRepository
    An owner/repo to push the four canary secrets into, using the GitHub CLI, so the values are never
    displayed. Requires 'gh' on PATH and an authenticated session. Without it the values are returned
    to you and nothing is sent anywhere.
.PARAMETER EnvironmentName
    GitHub environment the secrets are written to when -GitHubRepository is used.
.EXAMPLE
    Connect-MgGraph -Scopes 'User.ReadWrite.All','Application.ReadWrite.All','DelegatedPermissionGrant.ReadWrite.All','Directory.Read.All','Policy.Read.All','Policy.ReadWrite.ConditionalAccess','User-PasswordProfile.ReadWrite.All'
    ./Build/New-EntraCanaryConfiguration.ps1 -WhatIf

    Shows every object that would be created or changed, without touching the tenant. The script
    names any scope that is missing rather than failing part-way through.
.EXAMPLE
    ./Build/New-EntraCanaryConfiguration.ps1 -GitHubRepository 'Fortigi/OmadaWeb.PS'

    Provisions the tenant and writes the four secrets straight into the 'entra-canary' environment,
    so no credential is ever rendered to the console.
.EXAMPLE
    ./Build/New-EntraCanaryConfiguration.ps1 -SkipConditionalAccess

    Provisions a tenant without Entra ID P1. The summary will state that the account is not contained
    by policy.
.NOTES
    Requires the Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Applications
    and Microsoft.Graph.Identity.SignIns modules, and an existing Connect-MgGraph session holding the
    scopes listed in the first example.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-z0-9][a-z0-9._-]*$')]
    [string]$UserPrincipalNamePrefix = "omadaweb-canary",

    [ValidateNotNullOrEmpty()]
    [string]$ApplicationDisplayName = "OmadaWeb.PS Sign-in Canary",

    [ValidateRange(1024, 65535)]
    [int]$Port = 8400,

    [string[]]$AllowedIpRange = @(),

    [switch]$DisableSecurityDefaults,

    [switch]$SkipConditionalAccess,

    [string]$GitHubRepository,

    [ValidateNotNullOrEmpty()]
    [string]$EnvironmentName = "entra-canary"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Microsoft Graph's well-known application ID, and the ids of the three delegated permissions the
# canary application asks for. Written out rather than looked up by name: these are stable, and
# resolving them by display name would make provisioning depend on the language of the tenant.
$GraphApplicationId = "00000003-0000-0000-c000-000000000000"
$GraphDelegatedPermission = [ordered]@{
    "openid"    = "37f7f235-527c-4136-accd-4a02d197296e"
    "profile"   = "14dad69e-099b-42c9-810b-d002981feec1"
    "User.Read" = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"
}

$ContainmentPolicyName = "OmadaWeb.PS canary - block every application except the canary"
$LocationPolicyName = "OmadaWeb.PS canary - block sign-in from outside the allowed ranges"
$NamedLocationName = "OmadaWeb.PS canary runner egress"

function Assert-GraphSession {
    <#
    .SYNOPSIS
        Fails early and legibly when the Graph session cannot do what follows.
    .DESCRIPTION
        Half-provisioning a tenant and stopping on a missing scope leaves objects behind that the
        operator then has to reason about. Checking the scopes up front costs one call and turns that
        into a message naming exactly what to reconnect with.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$RequiredScope
    )

    foreach ($ModuleName in @("Microsoft.Graph.Authentication", "Microsoft.Graph.Users", "Microsoft.Graph.Applications", "Microsoft.Graph.Identity.SignIns")) {
        if (-not (Get-Module -Name $ModuleName -ListAvailable)) {
            "The module '{0}' is not installed. Install it with: Install-Module {0} -Scope CurrentUser" -f $ModuleName | Write-Error -ErrorAction "Stop"
        }

        Import-Module -Name $ModuleName -ErrorAction Stop
    }

    $Context = Get-MgContext
    if ($null -eq $Context) {
        "Not connected to Microsoft Graph. Run: Connect-MgGraph -Scopes '{0}'" -f ($RequiredScope -join "','") | Write-Error -ErrorAction "Stop"
    }

    $MissingScope = @($RequiredScope | Where-Object { $_ -notin $Context.Scopes })
    if ($MissingScope.Count -gt 0) {
        "The current Microsoft Graph session is missing the scope(s) {0}. Reconnect with: Connect-MgGraph -Scopes '{1}'" -f ($MissingScope -join ", "), ($RequiredScope -join "','") | Write-Error -ErrorAction "Stop"
    }

    return $Context
}

function ConvertTo-ODataLiteral {
    <#
    .SYNOPSIS
        Escapes a value for use inside a single-quoted OData string literal.
    .DESCRIPTION
        OData escapes an apostrophe by doubling it. Without this, a display name or a user principal
        name containing one produces a filter Graph cannot parse, the lookup fails, and this script -
        whose whole contract is to be idempotent - concludes the object does not exist and creates a
        second one. A near-duplicate app registration in a tenant is a nuisance to unpick, and the
        run that produced it reported success.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    return $Value.Replace("'", "''")
}

function New-CanaryPassword {
    <#
    .SYNOPSIS
        Generates the canary account's password.
    .DESCRIPTION
        Drawn from a cryptographic RNG with rejection sampling rather than from Get-Random: the
        modulo bias of the obvious approach is small, but this value is the only thing standing in
        front of a real directory account and there is no reason to accept any bias at all.

        The alphabet excludes characters that are easy to lose in transit through a shell or a YAML
        file, because the same string has to survive being pasted into a GitHub secret.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [ValidateRange(16, 256)]
        [int]$Length = 48
    )

    $Alphabet = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789-_.~".ToCharArray()
    $Password = [System.Text.StringBuilder]::new()
    $RandomNumberGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        # The largest multiple of the alphabet size that fits in a byte. Anything above it is drawn
        # again, which is what keeps every character equally likely.
        $Limit = [byte](256 - (256 % $Alphabet.Length))
        $Buffer = [byte[]]::new(1)
        while ($Password.Length -lt $Length) {
            $RandomNumberGenerator.GetBytes($Buffer)
            if ($Buffer[0] -ge $Limit) {
                continue
            }

            $null = $Password.Append($Alphabet[$Buffer[0] % $Alphabet.Length])
        }
    }
    finally {
        $RandomNumberGenerator.Dispose()
    }

    return $Password.ToString()
}

function Set-CanaryUser {
    <#
    .SYNOPSIS
        Creates the canary account, or resets the password of the one already there.
    .DESCRIPTION
        The password is reset on every run rather than reused. The script cannot read an existing
        password back out of the directory, so the alternative would be returning secrets it does not
        actually know - and a canary configured from those would fail on its first run.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password', Justification = 'Microsoft Graph takes the new password as a plain string inside passwordProfile, and the same value has to be handed to "gh secret set". A SecureString here would be converted straight back on both sides, so it would add ceremony without shortening the plaintext lifetime. The value is generated in this process, never written to disk, and never rendered unless the operator asks for it.')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '', Justification = 'A PSCredential would be the wrong shape: this function is creating the account whose password it is setting, not authenticating with it. There is no credential to pass, only a user principal name and the password being assigned to it.')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$UserPrincipalName,

        [Parameter(Mandatory)]
        [string]$Password
    )

    $PasswordProfile = @{
        Password                      = $Password
        ForceChangePasswordNextSignIn = $false
    }

    $Existing = @(Get-MgUser -Filter ("userPrincipalName eq '{0}'" -f (ConvertTo-ODataLiteral -Value $UserPrincipalName)) -ErrorAction SilentlyContinue)
    if ($Existing.Count -gt 0) {
        if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Reset the canary account password")) {
            Update-MgUser -UserId $Existing[0].Id -PasswordProfile $PasswordProfile -PasswordPolicies "DisablePasswordExpiration" -AccountEnabled:$true
            "Reset the password of the existing canary account." | Write-Host -ForegroundColor Green
        }

        return $Existing[0]
    }

    if (-not $PSCmdlet.ShouldProcess($UserPrincipalName, "Create the canary account")) {
        return $null
    }

    $User = New-MgUser -UserPrincipalName $UserPrincipalName `
        -DisplayName "OmadaWeb.PS Sign-in Canary" `
        -MailNickname $UserPrincipalName.Split("@")[0] `
        -AccountEnabled `
        -PasswordProfile $PasswordProfile `
        -PasswordPolicies "DisablePasswordExpiration"

    "Created the canary account." | Write-Host -ForegroundColor Green
    return $User
}

function Set-CanaryApplication {
    <#
    .SYNOPSIS
        Creates or updates the app registration and its service principal.
    .DESCRIPTION
        Registered as a public client with a single loopback redirect URI. It is a sign-in target and
        nothing else: it holds no credentials, exposes no API and is restricted to this tenant.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string]$RedirectUri,

        [Parameter(Mandatory)]
        [hashtable]$RequiredResourceAccess
    )

    $Existing = @(Get-MgApplication -Filter ("displayName eq '{0}'" -f (ConvertTo-ODataLiteral -Value $DisplayName)) -ErrorAction SilentlyContinue)
    if ($Existing.Count -gt 0) {
        $Application = $Existing[0]
        $RegisteredUri = @($Application.PublicClient.RedirectUris)
        if ($RedirectUri -notin $RegisteredUri) {
            if ($PSCmdlet.ShouldProcess($DisplayName, ("Add the redirect URI {0}" -f $RedirectUri))) {
                Update-MgApplication -ApplicationId $Application.Id -PublicClient @{ RedirectUris = @($RegisteredUri + $RedirectUri) }
                "Added the redirect URI to the existing application." | Write-Host -ForegroundColor Green
            }
        }
        else {
            "Application already registered with this redirect URI." | Write-Host
        }
    }
    else {
        if (-not $PSCmdlet.ShouldProcess($DisplayName, "Create the canary application registration")) {
            return $null
        }

        $Application = New-MgApplication -DisplayName $DisplayName `
            -SignInAudience "AzureADMyOrg" `
            -IsFallbackPublicClient `
            -PublicClient @{ RedirectUris = @($RedirectUri) } `
            -RequiredResourceAccess @($RequiredResourceAccess)

        "Created the canary application registration." | Write-Host -ForegroundColor Green
    }

    if ($null -eq $Application) {
        return $null
    }

    $ServicePrincipal = @(Get-MgServicePrincipal -Filter ("appId eq '{0}'" -f $Application.AppId) -ErrorAction SilentlyContinue)
    if ($ServicePrincipal.Count -eq 0) {
        if ($PSCmdlet.ShouldProcess($DisplayName, "Create the service principal")) {
            $null = New-MgServicePrincipal -AppId $Application.AppId
            "Created the service principal." | Write-Host -ForegroundColor Green
        }
    }

    return $Application
}

function Grant-CanaryAdminConsent {
    <#
    .SYNOPSIS
        Pre-consents the canary application's delegated permissions for the whole tenant.
    .DESCRIPTION
        Without this the first sign-in renders a consent screen. Resolve-EntraSignInScreen does not
        recognize it, the automation would stall on it, Switch-ToManualLogin would report a page it
        has never seen - and the canary would go red saying Microsoft changed something when in fact
        the tenant was simply not finished being set up.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ApplicationId,

        [Parameter(Mandatory)]
        [string]$GraphApplicationId,

        [Parameter(Mandatory)]
        [string]$Scope
    )

    $ClientServicePrincipal = @(Get-MgServicePrincipal -Filter ("appId eq '{0}'" -f $ApplicationId) -ErrorAction SilentlyContinue)
    $GraphServicePrincipal = @(Get-MgServicePrincipal -Filter ("appId eq '{0}'" -f $GraphApplicationId) -ErrorAction SilentlyContinue)

    if ($ClientServicePrincipal.Count -eq 0 -or $GraphServicePrincipal.Count -eq 0) {
        "Skipping admin consent: the service principals do not exist yet (expected with -WhatIf)." | Write-Warning
        return
    }

    $Existing = @(Get-MgOauth2PermissionGrant -Filter ("clientId eq '{0}' and consentType eq 'AllPrincipals'" -f $ClientServicePrincipal[0].Id) -ErrorAction SilentlyContinue |
            Where-Object { $_.ResourceId -eq $GraphServicePrincipal[0].Id })

    if ($Existing.Count -gt 0) {
        if ($Existing[0].Scope -eq $Scope) {
            "Admin consent already granted." | Write-Host
            return
        }

        if ($PSCmdlet.ShouldProcess($Scope, "Update the tenant-wide delegated permission grant")) {
            Update-MgOauth2PermissionGrant -OAuth2PermissionGrantId $Existing[0].Id -Scope $Scope
            "Updated the tenant-wide delegated permission grant." | Write-Host -ForegroundColor Green
        }

        return
    }

    if ($PSCmdlet.ShouldProcess($Scope, "Grant tenant-wide admin consent")) {
        $null = New-MgOauth2PermissionGrant -ClientId $ClientServicePrincipal[0].Id `
            -ConsentType "AllPrincipals" `
            -ResourceId $GraphServicePrincipal[0].Id `
            -Scope $Scope

        "Granted tenant-wide admin consent, so no consent screen is ever shown." | Write-Host -ForegroundColor Green
    }
}

function Get-CanarySecurityDefaultsState {
    <#
    .SYNOPSIS
        Reports whether security defaults are on, and turns them off only when asked to.
    .DESCRIPTION
        Security defaults enforce MFA registration on every account, which the canary cannot satisfy.
        Turning them off changes the posture of the entire tenant, so it is never a side effect: the
        state is reported, and only -DisableSecurityDefaults acts on it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Disable
    )

    $Policy = Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy -ErrorAction Stop
    if (-not $Policy.IsEnabled) {
        return "Disabled"
    }

    if (-not $Disable) {
        "Security defaults are ENABLED in this tenant. They enforce MFA registration on every account, which the canary cannot complete. Re-run with -DisableSecurityDefaults, or exempt the account another way, before scheduling the canary." | Write-Warning
        return "Enabled"
    }

    if ($PSCmdlet.ShouldProcess("Tenant security defaults", "Disable")) {
        Update-MgPolicyIdentitySecurityDefaultEnforcementPolicy -IsEnabled:$false
        "Disabled security defaults." | Write-Host -ForegroundColor Green
        return "Disabled"
    }

    return "Enabled"
}

function Add-CanaryMfaExemption {
    <#
    .SYNOPSIS
        Excludes the canary account from every Conditional Access policy that requires MFA.
    .DESCRIPTION
        This is the "documented conditional-access exemption" the issue asks for. Expressed as an
        exclusion on each MFA policy rather than as a permissive policy of its own, because a grant
        control is a requirement and never a waiver - a policy saying "this account may sign in
        without MFA" would not override one saying "everyone must use MFA".

        An empty tenant has no such policies, and the summary then says so rather than implying an
        exemption was applied.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$UserId
    )

    $Exempted = [System.Collections.Generic.List[string]]::new()
    foreach ($Policy in Get-MgIdentityConditionalAccessPolicy -All) {
        if ($Policy.State -eq "disabled") {
            continue
        }

        $BuiltInControl = @()
        if ($null -ne $Policy.GrantControls -and $null -ne $Policy.GrantControls.BuiltInControls) {
            $BuiltInControl = @($Policy.GrantControls.BuiltInControls)
        }

        if ("mfa" -notin $BuiltInControl) {
            continue
        }

        $ExcludedUser = @($Policy.Conditions.Users.ExcludeUsers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($UserId -in $ExcludedUser) {
            $Exempted.Add($Policy.DisplayName)
            continue
        }

        if ($PSCmdlet.ShouldProcess($Policy.DisplayName, "Exclude the canary account from this MFA policy")) {
            # The whole users condition is sent back, not just excludeUsers. A PATCH against a
            # Conditional Access policy replaces each condition object wholesale rather than merging
            # into it, so sending only the exclusion would silently empty includeUsers, includeGroups
            # and the rest - turning somebody's tenant-wide MFA requirement into a policy that
            # applies to nobody. That failure reports success and is invisible until an audit.
            $Users = @{
                IncludeUsers                 = @($Policy.Conditions.Users.IncludeUsers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                ExcludeUsers                 = @($ExcludedUser + $UserId)
                IncludeGroups                = @($Policy.Conditions.Users.IncludeGroups | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                ExcludeGroups                = @($Policy.Conditions.Users.ExcludeGroups | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                IncludeRoles                 = @($Policy.Conditions.Users.IncludeRoles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                ExcludeRoles                 = @($Policy.Conditions.Users.ExcludeRoles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                IncludeGuestsOrExternalUsers = $Policy.Conditions.Users.IncludeGuestsOrExternalUsers
                ExcludeGuestsOrExternalUsers = $Policy.Conditions.Users.ExcludeGuestsOrExternalUsers
            }

            Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $Policy.Id -Conditions @{ Users = $Users }
            $Exempted.Add($Policy.DisplayName)
        }
    }

    return $Exempted.ToArray()
}

function Set-CanaryConditionalAccessPolicy {
    <#
    .SYNOPSIS
        Creates or updates one Conditional Access policy by display name.
    .DESCRIPTION
        Idempotent by display name, which is what lets this script be re-run: a second call updates
        the policy it created the first time instead of adding a near-duplicate that an operator then
        has to tell apart from the original.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [hashtable]$Conditions,

        [Parameter(Mandatory)]
        [hashtable]$GrantControls
    )

    $Existing = @(Get-MgIdentityConditionalAccessPolicy -All | Where-Object { $_.DisplayName -eq $DisplayName })
    if ($Existing.Count -gt 0) {
        if ($PSCmdlet.ShouldProcess($DisplayName, "Update the Conditional Access policy")) {
            Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $Existing[0].Id -Conditions $Conditions -GrantControls $GrantControls -State "enabled"
            "Updated Conditional Access policy '{0}'." -f $DisplayName | Write-Host -ForegroundColor Green
        }

        return $Existing[0].Id
    }

    if (-not $PSCmdlet.ShouldProcess($DisplayName, "Create the Conditional Access policy")) {
        return $null
    }

    $Policy = New-MgIdentityConditionalAccessPolicy -DisplayName $DisplayName -State "enabled" -Conditions $Conditions -GrantControls $GrantControls
    "Created Conditional Access policy '{0}'." -f $DisplayName | Write-Host -ForegroundColor Green
    return $Policy.Id
}

function Set-CanaryNamedLocation {
    <#
    .SYNOPSIS
        Creates or updates the named location holding the allowed runner egress ranges.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string[]]$IpRange
    )

    # Entra allows 2000 ranges in one named location. Failing here beats letting Graph reject the
    # whole request with a message that does not name the cause.
    if ($IpRange.Count -gt 2000) {
        "A named location can hold at most 2000 IP ranges; {0} were supplied. GitHub-hosted runners publish far more than that, which is why -AllowedIpRange is only practical with a self-hosted or fixed-egress runner." -f $IpRange.Count | Write-Error -ErrorAction "Stop"
    }

    # The OData type has to match the address family. Sending an IPv6 range as an iPv4CidrRange is
    # rejected by Graph with an error that names neither the range nor the reason, so the family is
    # read from the address itself and a malformed entry is refused here, where it can be named.
    $IpRangeBody = @($IpRange | ForEach-Object {
            $Cidr = $_
            $Parts = $Cidr.Split("/")
            $Address = $null
            if ($Parts.Count -ne 2 -or -not [System.Net.IPAddress]::TryParse($Parts[0], [ref]$Address)) {
                "'{0}' is not a CIDR range. Supply ranges such as '203.0.113.0/24' or '2001:db8::/32'." -f $Cidr | Write-Error -ErrorAction "Stop"
            }

            $ODataType = "#microsoft.graph.iPv4CidrRange"
            if ($Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
                $ODataType = "#microsoft.graph.iPv6CidrRange"
            }

            @{
                "@odata.type" = $ODataType
                cidrAddress   = $Cidr
            }
        })

    $Body = @{
        "@odata.type" = "#microsoft.graph.ipNamedLocation"
        displayName   = $DisplayName
        isTrusted     = $false
        ipRanges      = $IpRangeBody
    }

    $Existing = @(Get-MgIdentityConditionalAccessNamedLocation -All | Where-Object { $_.DisplayName -eq $DisplayName })
    if ($Existing.Count -gt 0) {
        if ($PSCmdlet.ShouldProcess($DisplayName, "Update the named location")) {
            Update-MgIdentityConditionalAccessNamedLocation -NamedLocationId $Existing[0].Id -BodyParameter $Body
            "Updated named location '{0}'." -f $DisplayName | Write-Host -ForegroundColor Green
        }

        return $Existing[0].Id
    }

    if (-not $PSCmdlet.ShouldProcess($DisplayName, "Create the named location")) {
        return $null
    }

    $Location = New-MgIdentityConditionalAccessNamedLocation -BodyParameter $Body
    "Created named location '{0}'." -f $DisplayName | Write-Host -ForegroundColor Green
    return $Location.Id
}

function Publish-CanarySecret {
    <#
    .SYNOPSIS
        Writes the canary secrets into a GitHub environment without displaying them.
    .DESCRIPTION
        Each value is piped to 'gh secret set' on standard input rather than passed as an argument,
        so it never reaches a command line that a process listing or a shell history would record.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$EnvironmentName,

        [Parameter(Mandatory)]
        [hashtable]$Secret
    )

    if ($null -eq (Get-Command -Name "gh" -ErrorAction SilentlyContinue)) {
        "The GitHub CLI ('gh') is not on PATH, so the secrets were not published. Set them by hand from the returned object." | Write-Error -ErrorAction "Stop"
    }

    foreach ($Name in ($Secret.Keys | Sort-Object)) {
        if (-not $PSCmdlet.ShouldProcess(("{0} ({1}/{2})" -f $Name, $Repository, $EnvironmentName), "Set the GitHub secret")) {
            continue
        }

        # gh reads the value from standard input when --body is omitted, which keeps it off a command
        # line that a process listing or a shell history would record.
        $Secret[$Name] | & gh secret set $Name --repo $Repository --env $EnvironmentName
        if ($LASTEXITCODE -ne 0) {
            "Failed to set the GitHub secret '{0}' (gh exited with {1})." -f $Name, $LASTEXITCODE | Write-Error -ErrorAction "Stop"
        }

        "Set secret {0}." -f $Name | Write-Host -ForegroundColor Green
    }
}

try {
    $RequiredScope = @(
        "User.ReadWrite.All",
        "Application.ReadWrite.All",
        "DelegatedPermissionGrant.ReadWrite.All",
        # Get-MgOrganization is how the tenant's initial onmicrosoft.com domain is found, and it is
        # not covered by any of the scopes above.
        "Directory.Read.All",
        "User-PasswordProfile.ReadWrite.All"
    )
    if (-not $SkipConditionalAccess) {
        $RequiredScope += "Policy.Read.All"
        $RequiredScope += "Policy.ReadWrite.ConditionalAccess"
    }

    # Reading the security-defaults policy is covered by Policy.Read.All; turning it off is a
    # separate scope, and it is only asked for when the script is actually going to do that.
    if ($DisableSecurityDefaults) {
        $RequiredScope += "Policy.ReadWrite.SecurityDefaults"
    }

    $Context = Assert-GraphSession -RequiredScope $RequiredScope

    $Organization = Get-MgOrganization -ErrorAction Stop | Select-Object -First 1
    $InitialDomain = @($Organization.VerifiedDomains | Where-Object { $_.IsInitial })
    if ($InitialDomain.Count -eq 0) {
        "Could not determine the tenant's initial onmicrosoft.com domain." | Write-Error -ErrorAction "Stop"
    }

    $UserPrincipalName = "{0}@{1}" -f $UserPrincipalNamePrefix, $InitialDomain[0].Name
    $RedirectUri = "http://localhost:{0}/canary" -f $Port

    # Reported so an operator running this against the wrong directory notices before anything is
    # created. The tenant id is theirs and is deliberately not recorded anywhere by this repository.
    "Tenant : {0}" -f $Context.TenantId | Write-Host
    "Account: {0}" -f $UserPrincipalName | Write-Host
    "Redirect URI: {0}" -f $RedirectUri | Write-Host
    "" | Write-Host

    $Password = New-CanaryPassword
    $User = Set-CanaryUser -UserPrincipalName $UserPrincipalName -Password $Password

    $RequiredResourceAccess = @{
        ResourceAppId  = $GraphApplicationId
        ResourceAccess = @($GraphDelegatedPermission.Values | ForEach-Object {
                @{
                    Id   = $_
                    Type = "Scope"
                }
            })
    }

    $Application = Set-CanaryApplication -DisplayName $ApplicationDisplayName -RedirectUri $RedirectUri -RequiredResourceAccess $RequiredResourceAccess

    if ($null -ne $Application) {
        Grant-CanaryAdminConsent -ApplicationId $Application.AppId -GraphApplicationId $GraphApplicationId -Scope ($GraphDelegatedPermission.Keys -join " ")
    }

    $SecurityDefaults = "Not checked"
    $MfaExemption = @()
    $Contained = $false
    $LocationRestricted = $false

    if ($SkipConditionalAccess) {
        "Skipping every Conditional Access change (-SkipConditionalAccess)." | Write-Host -ForegroundColor Yellow
    }
    else {
        $SecurityDefaults = Get-CanarySecurityDefaultsState -Disable:$DisableSecurityDefaults
        if ($null -ne $User) {
            $MfaExemption = @(Add-CanaryMfaExemption -UserId $User.Id)

            if ($null -ne $Application) {
                $ContainmentId = Set-CanaryConditionalAccessPolicy -DisplayName $ContainmentPolicyName -Conditions @{
                    Users        = @{ IncludeUsers = @($User.Id) }
                    Applications = @{
                        IncludeApplications = @("All")
                        ExcludeApplications = @($Application.AppId)
                    }
                    ClientAppTypes = @("all")
                } -GrantControls @{
                    Operator        = "OR"
                    BuiltInControls = @("block")
                }
                $Contained = $null -ne $ContainmentId
            }

            if ($AllowedIpRange.Count -gt 0) {
                $LocationId = Set-CanaryNamedLocation -DisplayName $NamedLocationName -IpRange $AllowedIpRange
                if ($null -ne $LocationId) {
                    $null = Set-CanaryConditionalAccessPolicy -DisplayName $LocationPolicyName -Conditions @{
                        Users          = @{ IncludeUsers = @($User.Id) }
                        Applications   = @{ IncludeApplications = @("All") }
                        ClientAppTypes = @("all")
                        Locations      = @{
                            IncludeLocations = @("All")
                            ExcludeLocations = @($LocationId)
                        }
                    } -GrantControls @{
                        Operator        = "OR"
                        BuiltInControls = @("block")
                    }
                    $LocationRestricted = $true
                }
            }
        }
    }

    $Secret = @{
        CANARY_TENANT_ID = $Context.TenantId
        CANARY_CLIENT_ID = if ($null -eq $Application) { "" } else { $Application.AppId }
        CANARY_USERNAME  = $UserPrincipalName
        CANARY_PASSWORD  = $Password
    }

    if (-not [string]::IsNullOrWhiteSpace($GitHubRepository)) {
        Publish-CanarySecret -Repository $GitHubRepository -EnvironmentName $EnvironmentName -Secret $Secret
    }

    "" | Write-Host
    "Summary" | Write-Host -ForegroundColor Cyan
    "  Canary account          : {0}" -f $UserPrincipalName | Write-Host
    "  Application             : {0}" -f $ApplicationDisplayName | Write-Host
    "  Security defaults       : {0}" -f $SecurityDefaults | Write-Host
    "  MFA exemption applied to: {0}" -f $(if ($MfaExemption.Count -eq 0) { "no policy required MFA" } else { $MfaExemption -join ", " }) | Write-Host
    "  Contained by policy     : {0}" -f $Contained | Write-Host
    "  Restricted by IP        : {0}" -f $LocationRestricted | Write-Host
    "" | Write-Host

    if ([string]::IsNullOrWhiteSpace($GitHubRepository)) {
        "The four values below belong in the '{0}' GitHub environment and nowhere else. They are returned rather than printed - assign the result and read what you need, or re-run with -GitHubRepository to have them set for you without ever being displayed:" -f $EnvironmentName | Write-Host -ForegroundColor Yellow
        $Secret.Keys | Sort-Object | ForEach-Object { "  {0}" -f $_ | Write-Host }
        "" | Write-Host
    }

    if ($SecurityDefaults -eq "Enabled") {
        "The canary will fail while security defaults are enabled: every sign-in is challenged for MFA registration, which cannot be automated." | Write-Warning
    }

    if (-not $Contained -and -not $SkipConditionalAccess) {
        "The canary account is NOT contained by a Conditional Access policy. It holds no permissions, but nothing stops it signing in to other applications. See docs/entra-canary.md." | Write-Warning
    }

    return [pscustomobject]$Secret
}
catch {
    $PSCmdlet.ThrowTerminatingError($PSItem)
}
