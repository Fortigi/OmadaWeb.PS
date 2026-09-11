param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

# Issue #82. A consumer that runs requests on a background runspace had no supported way to reuse a
# session it had already authenticated: the worker imports its own module instance, so its session
# table starts empty and it would try to sign in interactively.
#
# These tests cover the two halves of the pair in one place, because most of what is worth asserting
# is the round trip rather than either command alone: what Export-OmadaSession hands out must be
# something Import-OmadaSession can put back, and must be nothing a reader could take a token from.

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    $Script:TokenValue = 'SUPER-SECRET-TOKEN-VALUE'
    $Script:TestBaseUrl = 'https://tenant.omada.cloud'

    # Puts an authenticated session on the module's session table without signing in, which is the
    # state Export-OmadaSession exists to read. The cookie never goes near the disk, so the tests
    # neither depend on nor disturb the user's real encrypted cookie cache.
    function Set-TestSession {
        param(
            [string]$UserName = '',
            [object]$Expires = $null
        )

        InModuleScope 'OmadaWeb.PS' -Parameters @{ UserName = $UserName; Expires = $Expires; TokenValue = $Script:TokenValue; BaseUrl = $Script:TestBaseUrl } {
            param($UserName, $Expires, $TokenValue, $BaseUrl)

            $Key = "tenant.omada.cloud::webview2::{0}" -f $UserName.ToLowerInvariant()
            $SessionContext = Get-OmadaSessionContext -Key $Key -AuthorityHost 'tenant.omada.cloud'
            $SessionContext.BaseUrl = $BaseUrl
            $SessionContext.WebView2Used = $true
            $SessionContext.LastSessionType = 'Normal'
            $SessionContext.UserName = $(if ([string]::IsNullOrWhiteSpace($UserName)) { $null } else { $UserName })

            $Cookie = [PSCustomObject]@{
                name   = 'oisauthtoken'
                value  = $TokenValue
                domain = 'tenant.omada.cloud'
            }
            if ($null -ne $Expires) {
                $Cookie | Add-Member -NotePropertyName 'expires' -NotePropertyValue $Expires
            }
            $SessionContext.AuthCookie = $Cookie
        }
    }

    function Clear-TestSessions {
        InModuleScope 'OmadaWeb.PS' { $Script:OmadaSessions.Clear() }
    }
}

Describe 'Export-OmadaSession' -Tag 'Unit' {
    BeforeEach {
        Clear-TestSessions
    }

    Context 'An authenticated session' {
        It 'Should return a state object that names the environment but not the account or the token' {
            Set-TestSession -Expires ([datetime]::UtcNow.AddMinutes(10))

            $State = Export-OmadaSession -Uri $Script:TestBaseUrl

            $State.PSObject.TypeNames | Should -Contain 'OmadaWeb.PS.SessionState'
            $State.BaseUrl | Should -Be $Script:TestBaseUrl
            $State.StateVersion | Should -Be 1
            $State.SessionId | Should -Not -BeNullOrEmpty

            # The whole object, not just the protected half: a caller may well log or display this,
            # and the point of the design is that doing so gives nothing away.
            $Rendered = $State | Format-List | Out-String
            $Rendered | Should -Not -BeLike ("*{0}*" -f $Script:TokenValue)
            $State.ProtectedState | Should -Not -BeLike ("*{0}*" -f $Script:TokenValue)
        }

        It 'Should not name the account anywhere in the state' {
            # The session key ends in the account name, and the module deliberately keeps that out
            # of its own logs by hashing it. A state object a caller passes around gets the same
            # treatment, so the key travels inside the protected half rather than beside it.
            Set-TestSession -UserName 'someone@example.com' -Expires ([datetime]::UtcNow.AddMinutes(10))

            $State = Export-OmadaSession -Uri $Script:TestBaseUrl -UserName 'someone@example.com'

            ($State | Format-List | Out-String) | Should -Not -BeLike '*someone@example.com*'
        }

        It 'Should report the cookie expiry it found' {
            $Expires = [datetime]::UtcNow.AddMinutes(10)
            Set-TestSession -Expires $Expires

            (Export-OmadaSession -Uri $Script:TestBaseUrl).ExpiresOn | Should -Be $Expires.ToUniversalTime()
        }

        It 'Should report no expiry for a session cookie that does not declare one' {
            Set-TestSession

            (Export-OmadaSession -Uri $Script:TestBaseUrl).ExpiresOn | Should -BeNullOrEmpty
        }

        It 'Should export the session belonging to the account that was named' {
            Set-TestSession -UserName 'someone@example.com' -Expires ([datetime]::UtcNow.AddMinutes(10))

            $Named = Export-OmadaSession -Uri $Script:TestBaseUrl -UserName 'someone@example.com'

            # A different account against the same environment is a different session, and there is
            # none - so asking for it must fail rather than hand back the one that does exist.
            { Export-OmadaSession -Uri $Script:TestBaseUrl -UserName 'someone-else@example.com' -ErrorAction Stop } | Should -Throw
            $Named.SessionId | Should -Not -BeNullOrEmpty
        }
    }

    Context 'No session to export' {
        It 'Should fail clearly when nothing has been authenticated' {
            $Failure = { Export-OmadaSession -Uri $Script:TestBaseUrl -ErrorAction Stop } | Should -Throw -PassThru

            $Failure.FullyQualifiedErrorId | Should -BeLike 'OmadaSessionExpired*'
            $Failure.Exception | Should -BeOfType [System.Security.Authentication.AuthenticationException]
        }

        It 'Should not create a session as a side effect of being asked for one' {
            { Export-OmadaSession -Uri $Script:TestBaseUrl -ErrorAction Stop } | Should -Throw

            # Get-OmadaSessionContext creates a context when it does not find one, which would turn
            # "you are not signed in" into an export that looks fine and fails in the worker.
            $Count = InModuleScope 'OmadaWeb.PS' { $Script:OmadaSessions.Count }
            $Count | Should -Be 0
        }

        It 'Should fail when a session exists but holds no cookie' {
            InModuleScope 'OmadaWeb.PS' {
                $SessionContext = Get-OmadaSessionContext -Key 'tenant.omada.cloud::webview2::' -AuthorityHost 'tenant.omada.cloud'
                $SessionContext.BaseUrl = 'https://tenant.omada.cloud'
            }

            $Failure = { Export-OmadaSession -Uri $Script:TestBaseUrl -ErrorAction Stop } | Should -Throw -PassThru
            $Failure.FullyQualifiedErrorId | Should -BeLike 'OmadaSessionExpired*'
        }

        It 'Should refuse to export a session whose cookie has already expired' {
            Set-TestSession -Expires ([datetime]::UtcNow.AddMinutes(-1))

            $Failure = { Export-OmadaSession -Uri $Script:TestBaseUrl -ErrorAction Stop } | Should -Throw -PassThru
            $Failure.FullyQualifiedErrorId | Should -BeLike 'OmadaSessionExpired*'
        }

        It 'Should refuse -UserName together with -Credential' {
            Set-TestSession -UserName 'someone@example.com' -Expires ([datetime]::UtcNow.AddMinutes(10))
            $Credential = [System.Management.Automation.PSCredential]::new('someone-else@example.com', (ConvertTo-SecureString 'x' -AsPlainText -Force))

            { Export-OmadaSession -Uri $Script:TestBaseUrl -UserName 'someone@example.com' -Credential $Credential -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Cannot combine -UserName with -Credential*'
        }
    }
}

Describe 'Import-OmadaSession' -Tag 'Unit' {
    BeforeEach {
        Clear-TestSessions
    }

    Context 'A round trip' {
        It 'Should seed a session that carries the same cookie' {
            Set-TestSession -Expires ([datetime]::UtcNow.AddMinutes(10))
            $State = Export-OmadaSession -Uri $Script:TestBaseUrl

            # Standing in for the worker runspace: the same module, with no session of its own.
            Clear-TestSessions
            Import-OmadaSession -State $State

            $Seeded = InModuleScope 'OmadaWeb.PS' { $Script:OmadaSessions.Values | Select-Object -First 1 }
            $Seeded.AuthCookie.value | Should -Be $Script:TokenValue
            $Seeded.BaseUrl | Should -Be $Script:TestBaseUrl
            $Seeded.Seeded | Should -BeTrue
        }

        It 'Should seed it under the same key the original session used' {
            Set-TestSession -UserName 'someone@example.com' -Expires ([datetime]::UtcNow.AddMinutes(10))
            $State = Export-OmadaSession -Uri $Script:TestBaseUrl -UserName 'someone@example.com'

            Clear-TestSessions
            Import-OmadaSession -State $State

            # The key is what makes the worker's next request find this session instead of signing
            # in, so it has to survive the round trip exactly.
            $Keys = InModuleScope 'OmadaWeb.PS' { @($Script:OmadaSessions.Keys) }
            $Keys | Should -Contain 'tenant.omada.cloud::webview2::someone@example.com'
        }

        It 'Should carry across which engine the session runs on' {
            Set-TestSession -Expires ([datetime]::UtcNow.AddMinutes(10))
            $State = Export-OmadaSession -Uri $Script:TestBaseUrl

            Clear-TestSessions
            Import-OmadaSession -State $State

            $Seeded = InModuleScope 'OmadaWeb.PS' { $Script:OmadaSessions.Values | Select-Object -First 1 }
            $Seeded.WebView2Used | Should -BeTrue
            $Seeded.LastSessionType | Should -Be 'Normal'
        }

        It 'Should return nothing without -PassThru, and a summary with it' {
            Set-TestSession -Expires ([datetime]::UtcNow.AddMinutes(10))
            $State = Export-OmadaSession -Uri $Script:TestBaseUrl

            Clear-TestSessions
            Import-OmadaSession -State $State | Should -BeNullOrEmpty

            Clear-TestSessions
            $Summary = Import-OmadaSession -State $State -PassThru
            $Summary.SessionId | Should -Be $State.SessionId
            $Summary.BaseUrl | Should -Be $Script:TestBaseUrl
            $Summary.AllowInteractiveAuthentication | Should -BeFalse
        }

        It 'Should accept the state from the pipeline' {
            Set-TestSession -Expires ([datetime]::UtcNow.AddMinutes(10))
            $State = Export-OmadaSession -Uri $Script:TestBaseUrl

            Clear-TestSessions
            ($State | Import-OmadaSession -PassThru).SessionId | Should -Be $State.SessionId
        }
    }

    Context 'The seeded session may not sign in' {
        It 'Should refuse interactive authentication by default' {
            # The heart of the issue: a worker runspace has no desktop to put a sign-in window on
            # and nobody watching it, so the refusal is a property of the session rather than
            # something every call has to remember to ask for.
            Set-TestSession -Expires ([datetime]::UtcNow.AddMinutes(10))
            $State = Export-OmadaSession -Uri $Script:TestBaseUrl

            Clear-TestSessions
            Import-OmadaSession -State $State

            $Seeded = InModuleScope 'OmadaWeb.PS' { $Script:OmadaSessions.Values | Select-Object -First 1 }
            $Seeded.NoInteractiveAuthentication | Should -BeTrue
        }

        It 'Should allow it when the caller asks for it' {
            Set-TestSession -Expires ([datetime]::UtcNow.AddMinutes(10))
            $State = Export-OmadaSession -Uri $Script:TestBaseUrl

            Clear-TestSessions
            Import-OmadaSession -State $State -AllowInteractiveAuthentication

            $Seeded = InModuleScope 'OmadaWeb.PS' { $Script:OmadaSessions.Values | Select-Object -First 1 }
            $Seeded.NoInteractiveAuthentication | Should -BeFalse
        }

        It 'Should stop a seeded session from reaching either browser engine' {
            # Asserted against the function every browser sign-in passes through, with no cookie on
            # the session: without the seeded flag this is precisely where a window would open.
            Mock Get-DataFromWebView2 -ModuleName 'OmadaWeb.PS' {}
            Mock Get-DataFromWebDriver -ModuleName 'OmadaWeb.PS' {}

            $Failure = InModuleScope 'OmadaWeb.PS' {
                $SessionContext = Get-OmadaSessionContext -Key 'tenant.omada.cloud::webview2::' -AuthorityHost 'tenant.omada.cloud'
                $SessionContext.BaseUrl = 'https://tenant.omada.cloud'
                $SessionContext.AuthCookie = $null
                $SessionContext.Seeded = $true
                $SessionContext.NoInteractiveAuthentication = $true

                $RequestContext = New-OmadaRequestContext -BoundParams @{ Headers = @{}; AuthenticationType = 'WebView2' } -Session (New-Object Microsoft.PowerShell.Commands.WebRequestSession) -SessionContext $SessionContext

                try {
                    Invoke-BrowserAuthentication -RequestContext $RequestContext
                    $null
                }
                catch {
                    $PSItem
                }
            }

            $Failure | Should -Not -BeNullOrEmpty
            $Failure.FullyQualifiedErrorId | Should -BeLike 'OmadaSessionExpired*'
            $Failure.Exception | Should -BeOfType [System.Security.Authentication.AuthenticationException]
            # The message has to say the session was imported, or the caller reads it as their own
            # session having expired and goes looking in the wrong runspace.
            $Failure.Exception.Message | Should -BeLike '*imported*'

            Should -Invoke Get-DataFromWebView2 -ModuleName 'OmadaWeb.PS' -Times 0 -Exactly
            Should -Invoke Get-DataFromWebDriver -ModuleName 'OmadaWeb.PS' -Times 0 -Exactly
        }
    }

    Context 'A state that cannot be used' {
        It 'Should refuse a session whose cookie has already expired' {
            Set-TestSession -Expires ([datetime]::UtcNow.AddMinutes(10))
            $State = Export-OmadaSession -Uri $Script:TestBaseUrl
            # Exported while it was still alive, handed over, and dead by the time it arrives - the
            # ordinary way this fails, given how short an Omada session cookie lives.
            $State.ExpiresOn = [datetime]::UtcNow.AddMinutes(-1)

            Clear-TestSessions
            $Failure = { Import-OmadaSession -State $State -ErrorAction Stop } | Should -Throw -PassThru

            $Failure.FullyQualifiedErrorId | Should -BeLike 'OmadaSessionExpired*'
            $Failure.Exception | Should -BeOfType [System.Security.Authentication.AuthenticationException]

            # Nothing was seeded: a runspace handed a dead session is left with no session at all,
            # rather than one that looks usable until the first request comes back 401.
            $Count = InModuleScope 'OmadaWeb.PS' { $Script:OmadaSessions.Count }
            $Count | Should -Be 0
        }

        It 'Should refuse a state whose protected half cannot be read' {
            Set-TestSession -Expires ([datetime]::UtcNow.AddMinutes(10))
            $State = Export-OmadaSession -Uri $Script:TestBaseUrl
            # Stands in for a state exported by another user or on another machine: the protection
            # is bound to both, so neither can be decrypted here, and nor can this.
            $State.ProtectedState = '01000000deadbeef'

            Clear-TestSessions
            $Failure = { Import-OmadaSession -State $State -ErrorAction Stop } | Should -Throw -PassThru

            $Failure.FullyQualifiedErrorId | Should -BeLike 'OmadaSessionStateUnreadable*'
            $Failure.Exception | Should -BeOfType [System.Security.Cryptography.CryptographicException]
        }

        It 'Should refuse a state whose shape it does not know' {
            Set-TestSession -Expires ([datetime]::UtcNow.AddMinutes(10))
            $State = Export-OmadaSession -Uri $Script:TestBaseUrl
            $State.StateVersion = 2

            Clear-TestSessions
            { Import-OmadaSession -State $State -ErrorAction Stop } | Should -Throw -ExpectedMessage '*state version 2*'
        }

        It 'Should refuse an object that did not come from Export-OmadaSession' {
            { Import-OmadaSession -State ([PSCustomObject]@{ BaseUrl = 'https://tenant.omada.cloud' }) -ErrorAction Stop } | Should -Throw
        }
    }
}

AfterAll {
    InModuleScope 'OmadaWeb.PS' { $Script:OmadaSessions.Clear() }
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
