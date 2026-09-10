function Get-OmadaSignInAccount {
    <#
    .SYNOPSIS
        Answers which account a browser sign-in should use, and whether to ask instead.

    .DESCRIPTION
        Two things decide that, and they arrive by different routes: -UserName is put on the session
        by Invoke-BrowserAuthentication, while -Credential carries a user name of its own and has done
        since long before there was a session to put anything on. Asking the session for one and
        forgetting the other is how a sign-in ends up driving nothing at all, so the question is asked
        in exactly one place - here - and everything that needs the answer calls it.

        Both members are read through the property bag rather than directly. A session context is a
        PSCustomObject, and under the StrictMode the test suite runs with, reading a member that is not
        there is a terminating error rather than $null. That matters for more than tidiness: this is
        called from a WinForms timer handler, where a terminating error is not a failed sign-in but a
        window that stops responding.

    .PARAMETER SessionContext
        The session the sign-in belongs to.

    .OUTPUTS
        PSCustomObject with the members UserName - the account, or $null when nobody named one - and
        SelectAccount, true when the caller asked to be shown the picker instead.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [AllowNull()]
        $SessionContext
    )

    $Account = [pscustomobject]@{
        UserName      = $null
        SelectAccount = $false
    }

    if ($null -eq $SessionContext) {
        return $Account
    }

    $UserNameProperty = $SessionContext.PSObject.Properties["UserName"]
    if ($null -ne $UserNameProperty -and -not [string]::IsNullOrWhiteSpace($UserNameProperty.Value)) {
        $Account.UserName = ([string]$UserNameProperty.Value).Trim()
    }
    else {
        # -Credential names the account as well, and a session built before -UserName existed - or by
        # anything that sets the credential directly - carries it nowhere else.
        $CredentialProperty = $SessionContext.PSObject.Properties["Credential"]
        if ($null -ne $CredentialProperty -and $null -ne $CredentialProperty.Value -and -not [string]::IsNullOrWhiteSpace($CredentialProperty.Value.UserName)) {
            $Account.UserName = $CredentialProperty.Value.UserName.Trim()
        }
    }

    $SelectAccountProperty = $SessionContext.PSObject.Properties["SelectAccount"]
    if ($null -ne $SelectAccountProperty -and $null -ne $SelectAccountProperty.Value) {
        $Account.SelectAccount = [bool]$SelectAccountProperty.Value
    }

    return $Account
}
