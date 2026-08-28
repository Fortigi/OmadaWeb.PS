param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    $Script:Credential = New-Object System.Management.Automation.PSCredential('someone@contoso.com', (ConvertTo-SecureString 'password' -AsPlainText -Force))

    # No listener is started on purpose. The check under test runs before any request is made, so a
    # test that reached the network would be testing something else.
    $Script:Uri = 'http://localhost:19999/api/unit-test'
}

Describe 'Invoke-OmadaRequest -PreferredMfaMethod validation' -Tag 'Unit' {

    # -PreferredMfaMethod drives the Entra ID sign-in screens, which only the WebView2 engine
    # automates. Every other authentication type would accept the parameter and quietly do nothing
    # with it, and a preference that silently does nothing is worse than one that is refused.
    It 'Refuses -PreferredMfaMethod with -AuthenticationType <AuthenticationType>' -TestCases @(
        @{ AuthenticationType = 'Basic' }
        @{ AuthenticationType = 'Windows' }
        @{ AuthenticationType = 'Integrated' }
        @{ AuthenticationType = 'None' }
    ) {
        {
            Invoke-OmadaRestMethod -Uri $Script:Uri -AuthenticationType $AuthenticationType -Credential $Script:Credential -PreferredMfaMethod 'PhoneAppOTP' -ErrorAction Stop
        } | Should -Throw -ExpectedMessage '*-PreferredMfaMethod only applies to -AuthenticationType WebView2*'
    }

    It 'Names the authentication type that was supplied' {
        {
            Invoke-OmadaRestMethod -Uri $Script:Uri -AuthenticationType 'Basic' -Credential $Script:Credential -PreferredMfaMethod 'PhoneAppOTP' -ErrorAction Stop
        } | Should -Throw -ExpectedMessage "*got 'Basic'*"
    }

    It 'Refuses before any request is made' {
        # Nothing listens on the port above, so a call that got as far as the network would fail
        # with a connection error rather than with the parameter error.
        {
            Invoke-OmadaRestMethod -Uri $Script:Uri -AuthenticationType 'Basic' -Credential $Script:Credential -PreferredMfaMethod 'PhoneAppOTP' -ErrorAction Stop
        } | Should -Throw -ExpectedMessage '*-PreferredMfaMethod*'
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
