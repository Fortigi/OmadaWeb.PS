param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Naming the account a sign-in uses' -Tag 'Unit' {

    BeforeAll {
        InModuleScope 'OmadaWeb.PS' {
            # Same fixture shape as NoInteractiveAuthentication.Tests.ps1.
            function Script:New-TestRequestContext {
                param(
                    [hashtable]$BoundParams,
                    [string]$Key,
                    [string]$BaseUrl = 'http://localhost:19000/'
                )

                $SessionContext = Get-OmadaSessionContext -Key $Key
                $SessionContext.BaseUrl = $BaseUrl

                # A usable cookie, so Invoke-BrowserAuthentication takes its "already signed in"
                # branch. The account is resolved before that branch is chosen, which is what these
                # tests are about - and no browser is opened to find that out.
                $SessionContext.AuthCookie = [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'cookie-value'; domain = ([System.Uri]::new($BaseUrl)).Host }

                # Invoke-BrowserAuthentication ends by writing the cookie cache, whose path
                # Invoke-OmadaRequest normally fills in. These tests are about the account it resolves
                # on the way there, and a unit test has no business writing one, so the caching is
                # switched off rather than pointed somewhere.
                if (-not $BoundParams.ContainsKey("SkipCookieCache")) {
                    $BoundParams["SkipCookieCache"] = $true
                }

                return New-OmadaRequestContext -BoundParams $BoundParams -Session ([Microsoft.PowerShell.Commands.WebRequestSession]::new()) -SessionContext $SessionContext
            }
        }
    }

    Context 'Refusing to guess which account was meant' {
        It 'Should refuse -UserName together with -Credential' {
            # Two names for the account, and honouring either would silently discard the other.
            { Invoke-OmadaRestMethod -Uri 'http://localhost:19000/api/thing' -AuthenticationType 'WebView2' -UserName 'a@example.com' -Credential (New-Object System.Management.Automation.PSCredential('b@example.com', (ConvertTo-SecureString 'x' -AsPlainText -Force))) -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Cannot combine -UserName with -Credential*'
        }

        It 'Should refuse -SelectAccount together with -UserName' {
            # Entra ID takes an account name or an account picker, never both.
            { Invoke-OmadaRestMethod -Uri 'http://localhost:19000/api/thing' -AuthenticationType 'WebView2' -UserName 'a@example.com' -SelectAccount -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Cannot combine -SelectAccount with an account name*'
        }

        It 'Should refuse -SelectAccount together with the user name of a credential' {
            { Invoke-OmadaRestMethod -Uri 'http://localhost:19000/api/thing' -AuthenticationType 'WebView2' -SelectAccount -Credential (New-Object System.Management.Automation.PSCredential('b@example.com', (ConvertTo-SecureString 'x' -AsPlainText -Force))) -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Cannot combine -SelectAccount with an account name*'
        }

        It 'Should refuse an account name for an authentication type that cannot act on it' {
            # Every type but WebView2 would accept the parameter and quietly do nothing with it.
            { Invoke-OmadaRestMethod -Uri 'http://localhost:19000/api/thing' -AuthenticationType 'Basic' -UserName 'a@example.com' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*-UserName only applies to -AuthenticationType WebView2*'
        }

        It 'Should refuse the account picker for an authentication type that cannot show one' {
            { Invoke-OmadaRestMethod -Uri 'http://localhost:19000/api/thing' -AuthenticationType 'None' -SelectAccount -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*-SelectAccount only applies to -AuthenticationType WebView2*'
        }
    }

    Context 'Resolving the account onto the session' {
        It 'Should take the account from -UserName' {
            InModuleScope 'OmadaWeb.PS' {
                $RequestContext = New-TestRequestContext -Key 'unit-test-account-username' -BoundParams @{
                    AuthenticationType = 'WebView2'
                    Headers            = @{}
                    Uri                = 'http://localhost:19000/'
                    UserName           = '  mark@example.com  '
                }

                Invoke-BrowserAuthentication -RequestContext $RequestContext | Out-Null

                $RequestContext.SessionContext.UserName | Should -Be 'mark@example.com'
                $RequestContext.SessionContext.SelectAccount | Should -BeFalse
            }
        }

        It 'Should take the account from the user name of a credential' {
            InModuleScope 'OmadaWeb.PS' {
                $RequestContext = New-TestRequestContext -Key 'unit-test-account-credential' -BoundParams @{
                    AuthenticationType = 'WebView2'
                    Headers            = @{}
                    Uri                = 'http://localhost:19000/'
                    Credential         = New-Object System.Management.Automation.PSCredential('mark@example.com', (ConvertTo-SecureString 'x' -AsPlainText -Force))
                }

                Invoke-BrowserAuthentication -RequestContext $RequestContext | Out-Null

                $RequestContext.SessionContext.UserName | Should -Be 'mark@example.com'
            }
        }

        It 'Should take a credential that carries no password at all' {
            # The whole point of the passwordless path: the account is named, the password is not,
            # and the sign-in waits in the open window for whatever Entra asks for.
            InModuleScope 'OmadaWeb.PS' {
                $RequestContext = New-TestRequestContext -Key 'unit-test-account-nopassword' -BoundParams @{
                    AuthenticationType = 'WebView2'
                    Headers            = @{}
                    Uri                = 'http://localhost:19000/'
                    Credential         = New-Object System.Management.Automation.PSCredential('mark@example.com', ([System.Security.SecureString]::new()))
                }

                Invoke-BrowserAuthentication -RequestContext $RequestContext | Out-Null

                $RequestContext.SessionContext.UserName | Should -Be 'mark@example.com'
                $RequestContext.SessionContext.Credential.GetNetworkCredential().Password | Should -BeNullOrEmpty
            }
        }

        It 'Should leave the account unset when nobody named one' {
            # This is the default, and it has to stay indistinguishable from the behaviour before
            # these parameters existed: the browser decides.
            InModuleScope 'OmadaWeb.PS' {
                $RequestContext = New-TestRequestContext -Key 'unit-test-account-none' -BoundParams @{
                    AuthenticationType = 'WebView2'
                    Headers            = @{}
                    Uri                = 'http://localhost:19000/'
                }

                Invoke-BrowserAuthentication -RequestContext $RequestContext | Out-Null

                $RequestContext.SessionContext.UserName | Should -BeNullOrEmpty
                $RequestContext.SessionContext.SelectAccount | Should -BeFalse
            }
        }

        It 'Should record that the account picker was asked for' {
            InModuleScope 'OmadaWeb.PS' {
                $RequestContext = New-TestRequestContext -Key 'unit-test-account-picker' -BoundParams @{
                    AuthenticationType = 'WebView2'
                    Headers            = @{}
                    Uri                = 'http://localhost:19000/'
                    SelectAccount      = $true
                }

                Invoke-BrowserAuthentication -RequestContext $RequestContext | Out-Null

                $RequestContext.SessionContext.SelectAccount | Should -BeTrue
            }
        }
    }

    Context 'Keeping the parameters out of the web request' {
        It 'Should not forward them to the underlying web cmdlet' {
            InModuleScope 'OmadaWeb.PS' {
                $RequestContext = New-TestRequestContext -Key 'unit-test-account-not-forwarded' -BoundParams @{
                    AuthenticationType = 'WebView2'
                    Headers            = @{}
                    Uri                = 'http://localhost:19000/'
                    UserName           = 'mark@example.com'
                    SelectAccount      = $false
                }

                $Parameter = Set-RequestParameter -RequestContext $RequestContext

                $Parameter.Keys | Should -Not -Contain 'UserName'
                $Parameter.Keys | Should -Not -Contain 'SelectAccount'
            }
        }
    }
}
