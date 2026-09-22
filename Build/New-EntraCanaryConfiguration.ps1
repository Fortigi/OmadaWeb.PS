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
      4. The two app registrations the service-principal canary needs, shaped the way Omada's OAuth
         documentation describes a customer's tenant: a resource application carrying the Application
         ID URI and exposing an application role - the stand-in for the OpenID Connect application
         Omada is configured with - and a separate OAuth client application holding the credentials,
         because the OIDC registration is explicitly not allowed to. The client is granted the
         resource's application role, and holds both a client secret and a certificate so every
         credential form the module documents is exercised.
         See https://documentation.omadaidentity.com/docs/getting-started/authentication-sso/oauth/

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
.PARAMETER ResourceApplicationDisplayName
    Display name of the app registration that stands in for the one Omada is configured with. It is
    the resource a client-credentials token is issued for.
.PARAMETER OAuthClientApplicationDisplayName
    Display name of the confidential client the service-principal canary authenticates as.
.PARAMETER SkipServicePrincipalCanary
    Skips the two service-principal app registrations and their credentials, for a tenant where only
    the sign-in canary is wanted.
.PARAMETER RotateServicePrincipalCredential
    Replaces the OAuth client's secret and certificate instead of keeping the existing ones.

    Not the default, because a secret's value can be read only at creation: rotating without
    -GitHubRepository would invalidate the credential GitHub is holding and hand the replacement to
    nobody. With it, rotation and publication happen in the same run.
.PARAMETER ServicePrincipalCredentialMonths
    How long a newly created client secret and certificate are valid for.
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
    Connect-MgGraph -Scopes 'User.ReadWrite.All','Application.ReadWrite.All','DelegatedPermissionGrant.ReadWrite.All','AppRoleAssignment.ReadWrite.All','Directory.Read.All','Policy.Read.All','Policy.ReadWrite.ConditionalAccess','User-PasswordProfile.ReadWrite.All'
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

    [ValidateNotNullOrEmpty()]
    [string]$ResourceApplicationDisplayName = "OmadaWeb.PS Canary OData Resource",

    [ValidateNotNullOrEmpty()]
    [string]$OAuthClientApplicationDisplayName = "OmadaWeb.PS Canary OAuth Client",

    [switch]$SkipServicePrincipalCanary,

    [switch]$RotateServicePrincipalCredential,

    [ValidateRange(1, 24)]
    [int]$ServicePrincipalCredentialMonths = 12,

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

# The application role the resource exposes and the client is granted. The id is written out rather
# than generated per run for the same reason the Graph permission ids above are: re-running has to
# find the role it created last time rather than add a second one beside it.
$CanaryAppRole = @{
    Id                 = "3f9c1d4e-6b2a-4c58-9d13-7a5e8f0b2c64"
    AllowedMemberTypes = @("Application")
    DisplayName        = "OmadaWeb.PS canary OData reader"
    Description        = "Granted to the canary OAuth client so a client-credentials token carries a role, the way an Omada OData client's token does."
    Value              = "OmadaWeb.Canary.Read"
    IsEnabled          = $true
}

# Both credentials the OAuth client holds are labelled, so a run can find the ones it created without
# touching a credential somebody added by hand.
$CanaryCredentialName = "OmadaWeb.PS canary"

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

function Set-CanaryResourceApplication {
    <#
    .SYNOPSIS
        Creates or updates the app registration that stands in for the one Omada is configured with.
    .DESCRIPTION
        Omada's OAuth documentation describes two registrations, and this is the first of them: the
        OpenID Connect application. It is the resource - it carries the Application ID URI a client
        asks for a token for, and it exposes the application role that ends up in that token. Omada
        is explicit that this registration cannot be used with client secret grants, so it holds no
        credentials here either.

        requestedAccessTokenVersion is set to 2 because that is what Omada's setup instructions say
        to set it to, and it decides which claims the token carries: the canary asserts on 'azp' and
        a 'ver' of 2.0, neither of which a v1 token has.

        The Application ID URI uses the api://<application id> form, which is what an on-premises
        installation uses. Identity Cloud uses the Omada host name instead - the module reaches both
        the same way, through -EntraApplicationIdUri.
    .PARAMETER DisplayName
        Display name of the resource app registration.
    .PARAMETER AppRole
        The application role to expose, as a Graph appRole object.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [hashtable]$AppRole
    )

    $Existing = @(Get-MgApplication -Filter ("displayName eq '{0}'" -f (ConvertTo-ODataLiteral -Value $DisplayName)) -ErrorAction SilentlyContinue)

    if ($Existing.Count -gt 0) {
        $Application = $Existing[0]

        # The role is matched by id rather than by value, so a run that follows a renamed role updates
        # it instead of adding a second one that Entra would refuse for a duplicate value.
        $RegisteredRole = @($Application.AppRoles | Where-Object { $_.Id -eq $AppRole.Id })
        if ($RegisteredRole.Count -eq 0) {
            if ($PSCmdlet.ShouldProcess($DisplayName, ("Expose the application role {0}" -f $AppRole.Value))) {
                Update-MgApplication -ApplicationId $Application.Id -AppRoles @($Application.AppRoles + $AppRole)
                "Added the application role to the existing resource application." | Write-Host -ForegroundColor Green
            }
        }
        else {
            "Resource application already exposes the application role." | Write-Host
        }
    }
    else {
        if (-not $PSCmdlet.ShouldProcess($DisplayName, "Create the canary resource application registration")) {
            return $null
        }

        $Application = New-MgApplication -DisplayName $DisplayName `
            -SignInAudience "AzureADMyOrg" `
            -AppRoles @($AppRole) `
            -Api @{ RequestedAccessTokenVersion = 2 }

        # The identifier URI needs the application id, which only exists once the application does.
        Update-MgApplication -ApplicationId $Application.Id -IdentifierUris @(("api://{0}" -f $Application.AppId))
        $Application = Get-MgApplication -ApplicationId $Application.Id

        "Created the canary resource application registration." | Write-Host -ForegroundColor Green
    }

    if ($null -eq $Application) {
        return $null
    }

    $ServicePrincipal = @(Get-MgServicePrincipal -Filter ("appId eq '{0}'" -f $Application.AppId) -ErrorAction SilentlyContinue)
    if ($ServicePrincipal.Count -eq 0) {
        if ($PSCmdlet.ShouldProcess($DisplayName, "Create the resource service principal")) {
            $null = New-MgServicePrincipal -AppId $Application.AppId
            "Created the resource service principal." | Write-Host -ForegroundColor Green
        }
    }

    return $Application
}

function Set-CanaryOAuthClientApplication {
    <#
    .SYNOPSIS
        Creates or updates the confidential client that authenticates with the client-credentials grant.
    .DESCRIPTION
        The second of Omada's two registrations: one OAuth client application per client that connects,
        holding the credentials the main OIDC registration is not allowed to hold.

        It is a confidential client - no redirect URI, no public-client flag - and it asks for exactly
        one thing: the application role the resource exposes. Type 'Role' rather than 'Scope', because
        a client-credentials token carries application permissions and never delegated ones.
    .PARAMETER DisplayName
        Display name of the client app registration.
    .PARAMETER ResourceAppId
        The resource application's application (client) id.
    .PARAMETER AppRoleId
        The id of the application role to request from that resource.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string]$ResourceAppId,

        [Parameter(Mandatory)]
        [string]$AppRoleId
    )

    $RequiredResourceAccess = @{
        ResourceAppId  = $ResourceAppId
        ResourceAccess = @(
            @{
                Id   = $AppRoleId
                Type = "Role"
            }
        )
    }

    $Existing = @(Get-MgApplication -Filter ("displayName eq '{0}'" -f (ConvertTo-ODataLiteral -Value $DisplayName)) -ErrorAction SilentlyContinue)

    if ($Existing.Count -gt 0) {
        $Application = $Existing[0]

        $RequestsRole = @($Application.RequiredResourceAccess | Where-Object { $_.ResourceAppId -eq $ResourceAppId })
        if ($RequestsRole.Count -eq 0) {
            if ($PSCmdlet.ShouldProcess($DisplayName, "Request the application role from the resource")) {
                Update-MgApplication -ApplicationId $Application.Id -RequiredResourceAccess @($RequiredResourceAccess)
                "Added the application permission to the existing OAuth client." | Write-Host -ForegroundColor Green
            }
        }
        else {
            "OAuth client already requests the application role." | Write-Host
        }
    }
    else {
        if (-not $PSCmdlet.ShouldProcess($DisplayName, "Create the canary OAuth client application registration")) {
            return $null
        }

        $Application = New-MgApplication -DisplayName $DisplayName `
            -SignInAudience "AzureADMyOrg" `
            -RequiredResourceAccess @($RequiredResourceAccess)

        "Created the canary OAuth client application registration." | Write-Host -ForegroundColor Green
    }

    if ($null -eq $Application) {
        return $null
    }

    $ServicePrincipal = @(Get-MgServicePrincipal -Filter ("appId eq '{0}'" -f $Application.AppId) -ErrorAction SilentlyContinue)
    if ($ServicePrincipal.Count -eq 0) {
        if ($PSCmdlet.ShouldProcess($DisplayName, "Create the OAuth client service principal")) {
            $null = New-MgServicePrincipal -AppId $Application.AppId
            "Created the OAuth client service principal." | Write-Host -ForegroundColor Green
        }
    }

    return $Application
}

function Grant-CanaryAppRole {
    <#
    .SYNOPSIS
        Grants the OAuth client the resource's application role - the admin consent for it.
    .DESCRIPTION
        Requesting a role in a registration is not holding it. Without this assignment Entra either
        refuses the token or, where the resource does not require assignment, issues one carrying no
        roles at all - which authenticates nothing at Omada and would let the canary pass while
        proving less than it claims. The canary asserts the role is in the token for that reason.
    .PARAMETER ClientAppId
        Application (client) id of the OAuth client.
    .PARAMETER ResourceAppId
        Application (client) id of the resource.
    .PARAMETER AppRoleId
        The application role being granted.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ClientAppId,

        [Parameter(Mandatory)]
        [string]$ResourceAppId,

        [Parameter(Mandatory)]
        [string]$AppRoleId
    )

    $ClientServicePrincipal = @(Get-MgServicePrincipal -Filter ("appId eq '{0}'" -f $ClientAppId) -ErrorAction SilentlyContinue)
    $ResourceServicePrincipal = @(Get-MgServicePrincipal -Filter ("appId eq '{0}'" -f $ResourceAppId) -ErrorAction SilentlyContinue)

    if ($ClientServicePrincipal.Count -eq 0 -or $ResourceServicePrincipal.Count -eq 0) {
        "Skipping the app role grant: the service principals do not exist yet (expected with -WhatIf)." | Write-Warning
        return $false
    }

    $Existing = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ClientServicePrincipal[0].Id -ErrorAction SilentlyContinue |
            Where-Object { $_.AppRoleId -eq $AppRoleId -and $_.ResourceId -eq $ResourceServicePrincipal[0].Id })

    if ($Existing.Count -gt 0) {
        "Application role already granted." | Write-Host
        return $true
    }

    if (-not $PSCmdlet.ShouldProcess($AppRoleId, "Grant the application role to the canary OAuth client")) {
        return $false
    }

    $null = New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ClientServicePrincipal[0].Id `
        -PrincipalId $ClientServicePrincipal[0].Id `
        -ResourceId $ResourceServicePrincipal[0].Id `
        -AppRoleId $AppRoleId

    "Granted the application role, so a client-credentials token carries it." | Write-Host -ForegroundColor Green
    return $true
}

function Set-CanaryClientSecret {
    <#
    .SYNOPSIS
        Adds a client secret to the OAuth client, or reports the one already there.
    .DESCRIPTION
        Entra shows a secret's value once, at creation, and never again - so a run that leaves an
        existing secret alone has nothing to publish, and a run that creates one must publish it or
        the value is lost. That is why this returns the value only when it actually created one, and
        why rotation is a deliberate switch rather than something every run does: rotating without
        -GitHubRepository would invalidate the secret GitHub is holding and hand the replacement to
        nobody.
    .PARAMETER ApplicationObjectId
        The application's object id (not its application id).
    .PARAMETER DisplayName
        Label for the credential, so a later run finds the one it created.
    .PARAMETER Months
        How long a newly created secret is valid for.
    .PARAMETER Rotate
        Replace an existing secret instead of keeping it.
    .OUTPUTS
        A hashtable with Value (empty when nothing was created), EndDateTime and Created.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ApplicationObjectId,

        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [int]$Months,

        [switch]$Rotate
    )

    $Result = @{
        Value       = ""
        EndDateTime = $null
        Created     = $false
    }

    $Application = Get-MgApplication -ApplicationId $ApplicationObjectId
    $Ours = @($Application.PasswordCredentials | Where-Object { $_.DisplayName -eq $DisplayName })

    if ($Ours.Count -gt 0 -and -not $Rotate) {
        $Result.EndDateTime = @($Ours | Sort-Object -Property EndDateTime -Descending)[0].EndDateTime
        "Client secret already exists and expires {0:yyyy-MM-dd}. Pass -RotateServicePrincipalCredential to replace it." -f $Result.EndDateTime | Write-Host
        return $Result
    }

    if (-not $PSCmdlet.ShouldProcess($DisplayName, "Add a client secret to the canary OAuth client")) {
        return $Result
    }

    foreach ($Credential in $Ours) {
        Remove-MgApplicationPassword -ApplicationId $ApplicationObjectId -KeyId $Credential.KeyId
        "Removed the previous client secret." | Write-Host
    }

    $Added = Add-MgApplicationPassword -ApplicationId $ApplicationObjectId -PasswordCredential @{
        DisplayName = $DisplayName
        EndDateTime = [datetime]::UtcNow.AddMonths($Months)
    }

    $Result.Value = $Added.SecretText
    $Result.EndDateTime = $Added.EndDateTime
    $Result.Created = $true

    "Created a client secret valid until {0:yyyy-MM-dd}." -f $Added.EndDateTime | Write-Host -ForegroundColor Green
    return $Result
}

function Set-CanaryClientCertificate {
    <#
    .SYNOPSIS
        Generates a self-signed certificate, registers its public half, and returns the PFX.
    .DESCRIPTION
        The certificate is created in this process with .NET's CertificateRequest rather than with
        New-SelfSignedCertificate, so it never enters a certificate store on the machine that
        provisions the tenant: the only copies are the public half, which goes to Entra, and the PFX,
        which goes straight into a GitHub secret.

        Only the public half is ever uploaded. The private key is what the module uses to sign the
        client assertion that the canary exists to prove Microsoft still accepts, and it stays in the
        PFX.
    .PARAMETER ApplicationObjectId
        The application's object id (not its application id).
    .PARAMETER DisplayName
        Label for the credential, so a later run finds the one it created.
    .PARAMETER Months
        How long a newly created certificate is valid for.
    .PARAMETER Password
        Password protecting the returned PFX.
    .PARAMETER Rotate
        Replace an existing certificate instead of keeping it.
    .OUTPUTS
        A hashtable with Pfx (base64, empty when nothing was created), NotAfter, Thumbprint and Created.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password', Justification = 'X509Certificate2.Export takes the PFX password as a plain string, and the same value is handed to "gh secret set". A SecureString here would be converted straight back on both sides, so it would add ceremony without shortening the plaintext lifetime. The value is generated in this process, never written to disk, and never rendered unless the operator asks for it.')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ApplicationObjectId,

        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [int]$Months,

        [Parameter(Mandatory)]
        [string]$Password,

        [switch]$Rotate
    )

    $Result = @{
        Pfx        = ""
        NotAfter   = $null
        Thumbprint = ""
        Created    = $false
    }

    $Application = Get-MgApplication -ApplicationId $ApplicationObjectId
    $Ours = @($Application.KeyCredentials | Where-Object { $_.DisplayName -eq $DisplayName })

    if ($Ours.Count -gt 0 -and -not $Rotate) {
        $Newest = @($Ours | Sort-Object -Property EndDateTime -Descending)[0]
        $Result.NotAfter = $Newest.EndDateTime
        "Client certificate already registered and expires {0:yyyy-MM-dd}. Pass -RotateServicePrincipalCredential to replace it." -f $Result.NotAfter | Write-Host
        return $Result
    }

    if (-not $PSCmdlet.ShouldProcess($DisplayName, "Register a client certificate on the canary OAuth client")) {
        return $Result
    }

    $Key = [System.Security.Cryptography.RSA]::Create(2048)
    try {
        $Request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            ("CN={0}" -f $DisplayName),
            $Key,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

        # Backdated by a few minutes so a clock difference between this machine and Entra cannot make
        # a certificate that is not valid yet.
        $Certificate = $Request.CreateSelfSigned([System.DateTimeOffset]::UtcNow.AddMinutes(-5), [System.DateTimeOffset]::UtcNow.AddMonths($Months))
        try {
            # Replaces the collection rather than appending to it: our own previous certificate is
            # what is being rotated away, and leaving it registered would keep a credential alive that
            # nothing holds the key for any more.
            $Others = @($Application.KeyCredentials | Where-Object { $_.DisplayName -ne $DisplayName } | ForEach-Object {
                    @{
                        Type        = $_.Type
                        Usage       = $_.Usage
                        Key         = $_.Key
                        DisplayName = $_.DisplayName
                    }
                })

            $NewCredential = @{
                Type        = "AsymmetricX509Cert"
                Usage       = "Verify"
                Key         = $Certificate.RawData
                DisplayName = $DisplayName
            }

            Update-MgApplication -ApplicationId $ApplicationObjectId -KeyCredentials @($Others + $NewCredential)

            $Result.Pfx = [Convert]::ToBase64String($Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $Password))
            $Result.NotAfter = $Certificate.NotAfter
            $Result.Thumbprint = $Certificate.Thumbprint
            $Result.Created = $true

            "Registered a client certificate ({0}) valid until {1:yyyy-MM-dd}." -f $Certificate.Thumbprint, $Certificate.NotAfter | Write-Host -ForegroundColor Green
        }
        finally {
            $Certificate.Dispose()
        }
    }
    finally {
        $Key.Dispose()
    }

    return $Result
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
        "User-PasswordProfile.ReadWrite.All",
        # Security defaults are read on every run, including under -SkipConditionalAccess, because
        # they are a tenant-wide switch rather than a Conditional Access policy.
        "Policy.Read.All"
    )
    if (-not $SkipConditionalAccess) {
        $RequiredScope += "Policy.ReadWrite.ConditionalAccess"
    }

    # Granting an application role to a service principal is its own scope: Application.ReadWrite.All
    # registers the request, and only this assigns it.
    if (-not $SkipServicePrincipalCanary) {
        $RequiredScope += "AppRoleAssignment.ReadWrite.All"
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

    # The service-principal canary's half of the tenant: the two registrations Omada's OAuth
    # documentation describes, and the role grant between them. Entirely separate from the sign-in
    # canary above - no user, no browser, no Conditional Access - so it is skippable on its own.
    $ResourceApplication = $null
    $OAuthClientApplication = $null
    $AppRoleGranted = $false
    $ClientSecretResult = @{ Value = ""; EndDateTime = $null; Created = $false }
    $ClientCertificateResult = @{ Pfx = ""; NotAfter = $null; Thumbprint = ""; Created = $false }
    $CertificatePassword = ""

    if ($SkipServicePrincipalCanary) {
        "Skipping the service-principal canary objects (-SkipServicePrincipalCanary)." | Write-Host -ForegroundColor Yellow
    }
    else {
        $ResourceApplication = Set-CanaryResourceApplication -DisplayName $ResourceApplicationDisplayName -AppRole $CanaryAppRole

        if ($null -ne $ResourceApplication) {
            $OAuthClientApplication = Set-CanaryOAuthClientApplication -DisplayName $OAuthClientApplicationDisplayName -ResourceAppId $ResourceApplication.AppId -AppRoleId $CanaryAppRole.Id
        }

        if ($null -ne $OAuthClientApplication) {
            $AppRoleGranted = Grant-CanaryAppRole -ClientAppId $OAuthClientApplication.AppId -ResourceAppId $ResourceApplication.AppId -AppRoleId $CanaryAppRole.Id

            $ClientSecretResult = Set-CanaryClientSecret -ApplicationObjectId $OAuthClientApplication.Id `
                -DisplayName $CanaryCredentialName `
                -Months $ServicePrincipalCredentialMonths `
                -Rotate:$RotateServicePrincipalCredential

            # The PFX password is generated per certificate and shares its lifetime: it protects a file
            # that only ever exists inside a GitHub secret and the runner that decodes it.
            $CertificatePassword = New-CanaryPassword
            $ClientCertificateResult = Set-CanaryClientCertificate -ApplicationObjectId $OAuthClientApplication.Id `
                -DisplayName $CanaryCredentialName `
                -Months $ServicePrincipalCredentialMonths `
                -Password $CertificatePassword `
                -Rotate:$RotateServicePrincipalCredential
        }
    }

    $SecurityDefaults = "Not checked"
    $MfaExemption = @()
    $Contained = $false
    $LocationRestricted = $false

    # Security defaults are read whether or not Conditional Access is being touched. They are not a
    # Conditional Access policy - they are a tenant-wide switch that enforces MFA registration on
    # every account - and a canary account cannot answer that prompt. Reporting them only in the
    # Conditional Access branch meant that -SkipConditionalAccess hid the single most likely reason
    # for a canary that cannot sign in, and silently ignored -DisableSecurityDefaults along with it.
    if ($SkipConditionalAccess) {
        "Skipping every Conditional Access change (-SkipConditionalAccess)." | Write-Host -ForegroundColor Yellow
    }

    $SecurityDefaults = Get-CanarySecurityDefaultsState -Disable:$DisableSecurityDefaults

    if (-not $SkipConditionalAccess) {
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

    if ($null -ne $OAuthClientApplication) {
        $Secret['CANARY_SP_CLIENT_ID'] = $OAuthClientApplication.AppId
        $Secret['CANARY_SP_RESOURCE_URI'] = @($ResourceApplication.IdentifierUris)[0]
        $Secret['CANARY_SP_RESOURCE_CLIENT_ID'] = $ResourceApplication.AppId
        $Secret['CANARY_SP_APP_ROLE'] = $CanaryAppRole.Value

        # Only published when this run actually created them. A secret's value cannot be read back
        # after creation and a certificate's private key is never uploaded, so publishing an empty
        # string for a credential that was deliberately left in place would overwrite a working
        # GitHub secret with nothing.
        if ($ClientSecretResult.Created) {
            $Secret['CANARY_SP_CLIENT_SECRET'] = $ClientSecretResult.Value
            $Secret['CANARY_SP_SECRET_EXPIRY'] = "{0:yyyy-MM-ddTHH:mm:ssZ}" -f $ClientSecretResult.EndDateTime
        }

        if ($ClientCertificateResult.Created) {
            $Secret['CANARY_SP_CERT_PFX_BASE64'] = $ClientCertificateResult.Pfx
            $Secret['CANARY_SP_CERT_PASSWORD'] = $CertificatePassword
        }
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

    if ($SkipServicePrincipalCanary) {
        "  Service-principal canary: skipped" | Write-Host
    }
    else {
        "  Resource application    : {0}" -f $ResourceApplicationDisplayName | Write-Host
        "  OAuth client application: {0}" -f $OAuthClientApplicationDisplayName | Write-Host
        "  Application role granted: {0}" -f $AppRoleGranted | Write-Host
        "  Client secret expires   : {0}" -f $(if ($null -eq $ClientSecretResult.EndDateTime) { "not created" } else { "{0:yyyy-MM-dd}" -f $ClientSecretResult.EndDateTime }) | Write-Host
        "  Certificate expires     : {0}" -f $(if ($null -eq $ClientCertificateResult.NotAfter) { "not created" } else { "{0:yyyy-MM-dd}" -f $ClientCertificateResult.NotAfter }) | Write-Host
    }

    "" | Write-Host

    if ([string]::IsNullOrWhiteSpace($GitHubRepository)) {
        "The values below belong in the '{0}' GitHub environment and nowhere else. They are returned rather than printed - assign the result and read what you need, or re-run with -GitHubRepository to have them set for you without ever being displayed:" -f $EnvironmentName | Write-Host -ForegroundColor Yellow
        $Secret.Keys | Sort-Object | ForEach-Object { "  {0}" -f $_ | Write-Host }
        "" | Write-Host
    }

    if ($SecurityDefaults -eq "Enabled") {
        "The canary will fail while security defaults are enabled: every sign-in is challenged for MFA registration, which cannot be automated." | Write-Warning
    }

    if (-not $Contained -and -not $SkipConditionalAccess) {
        "The canary account is NOT contained by a Conditional Access policy. It holds no permissions, but nothing stops it signing in to other applications. See docs/entra-canary.md." | Write-Warning
    }

    # The canary account's password is reset on every run - the directory will not hand an existing
    # one back, so there is nothing else this script could do. Without -GitHubRepository, though, the
    # new password goes no further than the object returned to the operator, while the environment
    # keeps the old one: the tenant and GitHub now disagree, and the next scheduled run fails with
    # AADSTS50126 - "the user name or password is wrong" - hours later, reading like a broken account
    # rather than a half-finished provisioning run. Said here, while the person who caused it is still
    # looking at the screen.
    if ([string]::IsNullOrWhiteSpace($GitHubRepository) -and $null -ne $User) {
        "The canary account's password has just been reset, and the '{0}' GitHub environment still holds the previous one. Set CANARY_PASSWORD from the returned object, or re-run with -GitHubRepository <owner/repo>, or the sign-in canary will fail on its next run." -f $EnvironmentName | Write-Warning
    }

    if (-not $SkipServicePrincipalCanary -and -not $AppRoleGranted -and $null -ne $OAuthClientApplication) {
        "The canary OAuth client was NOT granted the resource's application role. Its tokens will carry no role, and the service-principal canary asserts that they do. See docs/entra-canary.md." | Write-Warning
    }

    # An expiry that is already close is worth saying now rather than leaving for the workflow to
    # annotate on the morning it matters.
    foreach ($Expiry in @(
            @{ Name = "client secret"; Moment = $ClientSecretResult.EndDateTime },
            @{ Name = "client certificate"; Moment = $ClientCertificateResult.NotAfter }
        )) {
        if ($null -ne $Expiry.Moment -and [datetime]$Expiry.Moment -lt [datetime]::UtcNow.AddDays(30)) {
            "The canary {0} expires {1:yyyy-MM-dd}. Re-run with -RotateServicePrincipalCredential -GitHubRepository <owner/repo> to replace it before the canary goes red." -f $Expiry.Name, $Expiry.Moment | Write-Warning
        }
    }

    return [pscustomobject]$Secret
}
catch {
    $PSCmdlet.ThrowTerminatingError($PSItem)
}
