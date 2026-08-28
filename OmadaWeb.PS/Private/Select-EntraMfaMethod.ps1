function Select-EntraMfaMethod {
    <#
    .SYNOPSIS
        Picks which verification method to use on the Entra ID 'choose a way to sign in' screen.

    .DESCRIPTION
        When an account has more than one verification method registered, Entra ID renders a picker
        and waits. Left alone the sign-in simply stops there, which is one of the silent stalls issue
        #18 exists to remove. The page ships the offered methods as the 'arrUserProofs' array in its
        embedded $Config object, and each entry names its method in 'authMethodId' - a fixed
        identifier such as 'PhoneAppNotification', not the localized sentence shown to the user. That
        identifier is what this function chooses by, so the choice is the same on a tenant served in
        Dutch as on one served in English.

        The default is the most secure method the account actually offers, in the order below. An
        Authenticator push - the number-match approval - is preferred over a code the user has to
        read and type, which is preferred over a code sent by SMS, which is preferred over a voice
        call. Weaker methods are not skipped, only ranked last, so an account that has nothing else
        registered still signs in.

        A method this function does not know is ranked behind every method it does. That is
        deliberate: Microsoft adds methods, and an unknown identifier is at least as likely to be
        something better as something worse, but choosing it would mean automating a screen whose
        behavior has never been seen here.

        -PreferredMethod overrides the ranking. When the account does not offer that method the
        override is reported once and the ranking decides instead, because failing a sign-in over a
        preference would be a worse answer than signing in by the best available means.

    .PARAMETER Proof
        The arrUserProofs entries read off the page. Each is expected to carry an authMethodId.

    .PARAMETER PreferredMethod
        The authMethodId the caller asked for through -PreferredMfaMethod, when there was one.

    .OUTPUTS
        PSCustomObject with the members Index, AuthMethodId, IsPreferred and IsDefault, or $null when
        the page offered no methods to choose from.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Proof,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$PreferredMethod
    )

    $Offered = @($Proof | Where-Object { $null -ne $_ })
    if ($Offered.Count -eq 0) {
        return $null
    }

    # Most secure first. The numbers are only an ordering, so a method added between two of these
    # later can be given a rank without renumbering the rest.
    $Rank = @{
        "PhoneAppNotification"       = 10
        "PhoneAppOTP"                = 20
        "OneWaySMS"                  = 30
        "TwoWayVoiceMobile"          = 40
        "TwoWayVoiceAlternateMobile" = 50
        "TwoWayVoiceOffice"          = 60
        "ConsolidatedTelephony"      = 70
    }

    $Candidate = [System.Collections.Generic.List[psobject]]::new()
    for ($Index = 0; $Index -lt $Offered.Count; $Index++) {
        $AuthMethodId = ""
        if ($null -ne $Offered[$Index].authMethodId) {
            $AuthMethodId = [string]$Offered[$Index].authMethodId
        }

        $MethodRank = 999
        foreach ($Known in $Rank.Keys) {
            if ($AuthMethodId -eq $Known) {
                $MethodRank = $Rank[$Known]
                break
            }
        }

        $IsDefault = $false
        if ($null -ne $Offered[$Index].isDefault) {
            $IsDefault = [bool]$Offered[$Index].isDefault
        }

        $Candidate.Add([pscustomobject]@{
                Index        = $Index
                AuthMethodId = $AuthMethodId
                IsPreferred  = $false
                IsDefault    = $IsDefault
                Rank         = $MethodRank
            })
    }

    if (-not [string]::IsNullOrWhiteSpace($PreferredMethod)) {
        $Wanted = @($Candidate | Where-Object { $_.AuthMethodId -eq $PreferredMethod })
        if ($Wanted.Count -gt 0) {
            $Wanted[0].IsPreferred = $true
            return ($Wanted[0] | Select-Object -Property Index, AuthMethodId, IsPreferred, IsDefault)
        }

        # The timer that drives this ticks every 150 ms, so the warning is issued once per sign-in
        # rather than once per look at the page.
        if (-not $Script:PreferredMfaMethodWarningIssued) {
            $Script:PreferredMfaMethodWarningIssued = $true
            "The verification method '{0}' asked for with -PreferredMfaMethod is not offered by this account. Available: {1}. Continuing with the most secure method that is offered." -f $PreferredMethod, (($Candidate.AuthMethodId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ", ") | Write-Warning
        }
    }

    # Sorting on Index as well keeps the choice reproducible when two methods share a rank, which is
    # what an account with two unknown methods produces.
    $Chosen = $Candidate | Sort-Object -Property Rank, Index | Select-Object -First 1

    return ($Chosen | Select-Object -Property Index, AuthMethodId, IsPreferred, IsDefault)
}
