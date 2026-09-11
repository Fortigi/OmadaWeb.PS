param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    # Get-OmadaCookieCacheFilePath.Tests.ps1 already covers where the cache file goes and how a
    # file left behind by an older version is migrated. This file covers what goes *into* it and
    # what comes back out - the read and write paths themselves, which nothing exercised.

    $Script:SampleCookie = [pscustomobject]@{
        name     = "oisauthtoken"
        value    = "a-real-looking-bearer-value-0123456789"
        domain   = "tenant.omada.cloud"
        path     = "/"
        expires  = $null
        httpOnly = $true
        secure   = $true
        sameSite = "Lax"
    }

    function New-CookieFilePath {
        Join-Path ([System.IO.Path]::GetTempPath()) ("omadaCookieTest_{0}.cookie" -f ([guid]::NewGuid().ToString("N")))
    }

    function Get-RawFileText {
        param([string]$Path)
        $Bytes = [System.IO.File]::ReadAllBytes($Path)
        # Both spellings a .NET string could reach a file in, so "the secret is not in there" is
        # a claim about the bytes rather than about one encoding.
        @{
            Utf8  = [System.Text.Encoding]::UTF8.GetString($Bytes)
            Utf16 = [System.Text.Encoding]::Unicode.GetString($Bytes)
        }
    }
}

Describe 'Omada cookie cache - write path' -Tag 'Unit' {

    It 'should report success and leave a file behind' {
        $Path = New-CookieFilePath
        try {
            $Written = InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path; CookieA = $Script:SampleCookie } {
                Export-OmadaCookieFile -Path $PathA -AuthCookie $CookieA
            }
            $Written | Should -Be $true
            Test-Path -Path $Path | Should -Be $true
        }
        finally { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }
    }

    It 'should not leave the cookie value readable in the file' {
        # The whole point of the protected format (issue #21): the file holds a bearer token, and
        # a copy of it taken off the machine must be worthless.
        $Path = New-CookieFilePath
        try {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path; CookieA = $Script:SampleCookie } {
                Export-OmadaCookieFile -Path $PathA -AuthCookie $CookieA | Out-Null
            }

            $Raw = Get-RawFileText -Path $Path
            $Raw.Utf8 | Should -Not -Match "a-real-looking-bearer-value-0123456789"
            $Raw.Utf16 | Should -Not -Match "a-real-looking-bearer-value-0123456789"
            $Raw.Utf8 | Should -Not -Match "oisauthtoken"
        }
        finally { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }
    }

    It 'should write the single-SecureString document the cache-file test recognises' {
        $Path = New-CookieFilePath
        try {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path; CookieA = $Script:SampleCookie } {
                Export-OmadaCookieFile -Path $PathA -AuthCookie $CookieA | Out-Null
            }

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path } {
                Test-OmadaCookieCacheFile -Path $PathA
            } | Should -Be $true
        }
        finally { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }
    }

    It 'should overwrite a cookie file that is already there' {
        $Path = New-CookieFilePath
        try {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path; CookieA = $Script:SampleCookie } {
                Export-OmadaCookieFile -Path $PathA -AuthCookie $CookieA | Out-Null
                $Second = $CookieA.PSObject.Copy()
                $Second.value = "second-value"
                Export-OmadaCookieFile -Path $PathA -AuthCookie $Second | Out-Null
            }

            (InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path } { Import-OmadaCookieFile -Path $PathA }).value |
                Should -Be "second-value"
        }
        finally { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }
    }

    It 'should warn and report failure rather than throw when the folder does not exist' {
        # A cookie that cannot be cached costs a sign-in, not a failed request, so this must never
        # take the caller's request down with it.
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) ("omadaCookieNoSuchFolder_{0}\x.cookie" -f ([guid]::NewGuid().ToString("N")))

        $Warnings = $null
        $Result = InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path; CookieA = $Script:SampleCookie } {
            Export-OmadaCookieFile -Path $PathA -AuthCookie $CookieA
        } -WarningVariable Warnings

        $Result | Should -Be $false
        # The warning is half the contract: without it the cookie silently stops being cached and
        # every later call pays for a sign-in with nothing said about why.
        $Warnings | Should -Not -BeNullOrEmpty
        ($Warnings -join " ") | Should -Match "Unable to write the cookie file"
    }

    It 'should accept a null cookie without throwing' {
        $Path = New-CookieFilePath
        try {
            { InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path } {
                    Export-OmadaCookieFile -Path $PathA -AuthCookie $null | Out-Null
                } } | Should -Not -Throw
        }
        finally { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Omada cookie cache - read path' -Tag 'Unit' {

    It 'should read back exactly what the write path stored' {
        $Path = New-CookieFilePath
        try {
            $ReadBack = InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path; CookieA = $Script:SampleCookie } {
                Export-OmadaCookieFile -Path $PathA -AuthCookie $CookieA | Out-Null
                Import-OmadaCookieFile -Path $PathA
            }

            $ReadBack.name | Should -Be "oisauthtoken"
            $ReadBack.value | Should -Be "a-real-looking-bearer-value-0123456789"
            $ReadBack.domain | Should -Be "tenant.omada.cloud"
            $ReadBack.path | Should -Be "/"
            $ReadBack.httpOnly | Should -Be $true
            $ReadBack.secure | Should -Be $true
            $ReadBack.sameSite | Should -Be "Lax"
        }
        finally { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }
    }

    It 'should survive a cookie value full of characters XML would otherwise eat' {
        $Path = New-CookieFilePath
        try {
            $Awkward = 'a<b>c&d"e''f/g+h=i%20j'
            $ReadBack = InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path; ValueA = $Awkward } {
                $Cookie = [pscustomobject]@{
                    name = "oisauthtoken"; value = $ValueA; domain = "tenant.omada.cloud"
                    path = "/"; expires = $null; httpOnly = $true; secure = $true; sameSite = "Lax"
                }
                Export-OmadaCookieFile -Path $PathA -AuthCookie $Cookie | Out-Null
                Import-OmadaCookieFile -Path $PathA
            }

            $ReadBack.value | Should -BeExactly $Awkward
        }
        finally { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }
    }

    It 'should answer "no cookie" for a file that is not there' {
        $Path = New-CookieFilePath
        InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path } {
            Import-OmadaCookieFile -Path $PathA
        } | Should -BeNullOrEmpty
    }

    It 'should answer "no cookie" for a corrupt file rather than throwing' {
        $Path = New-CookieFilePath
        try {
            Set-Content -Path $Path -Value "this is not clixml at all" -Encoding UTF8

            $Result = $null
            { $Result = InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path } {
                    Import-OmadaCookieFile -Path $PathA
                } } | Should -Not -Throw
            $Result | Should -BeNullOrEmpty
        }
        finally { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }
    }

    It 'should answer "no cookie" for a truncated protected file' {
        $Path = New-CookieFilePath
        try {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path; CookieA = $Script:SampleCookie } {
                Export-OmadaCookieFile -Path $PathA -AuthCookie $CookieA | Out-Null
            }
            $Text = Get-Content -Path $Path -Raw
            Set-Content -Path $Path -Value $Text.Substring(0, [int]($Text.Length / 2)) -NoNewline

            $Result = $null
            { $Result = InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path } {
                    Import-OmadaCookieFile -Path $PathA
                } } | Should -Not -Throw
            $Result | Should -BeNullOrEmpty
        }
        finally { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }
    }

    It 'should refuse an unprotected file written by a version that predates issue #21' {
        # The old -CookiePath format: a bare Clixml of the cookie object, with the token readable.
        # It is deliberately not migrated - reading it would be reading the very format this
        # change set out to stop producing.
        $Path = New-CookieFilePath
        try {
            [PSCustomObject]@{ OmadaWebAuthCookie = $Script:SampleCookie } | Export-Clixml -Path $Path -Force

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path } {
                Import-OmadaCookieFile -Path $PathA
            } | Should -BeNullOrEmpty
        }
        finally { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }
    }

    It 'should refuse a same-named file that is some other SecureString entirely' {
        # Test-OmadaCookieCacheFile accepts the shape, and the payload then fails to deserialize.
        # Either way the answer has to be "no cookie", not a half-built object.
        $Path = New-CookieFilePath
        try {
            ConvertTo-SecureString -String "not a serialized cookie" -AsPlainText -Force | Export-Clixml -Path $Path -Force

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path } {
                Import-OmadaCookieFile -Path $PathA
            } | Should -BeNullOrEmpty
        }
        finally { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Omada cookie cache - Test-OmadaCookieCacheFile' -Tag 'Unit' {

    It 'should recognise a file the write path produced' {
        $Path = New-CookieFilePath
        try {
            InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path; CookieA = $Script:SampleCookie } {
                Export-OmadaCookieFile -Path $PathA -AuthCookie $CookieA | Out-Null
                Test-OmadaCookieCacheFile -Path $PathA
            } | Should -Be $true
        }
        finally { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }
    }

    It 'should reject an unrelated Clixml file that happens to share the name' {
        $Path = New-CookieFilePath
        try {
            [PSCustomObject]@{ Something = "else" } | Export-Clixml -Path $Path -Force

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path } {
                Test-OmadaCookieCacheFile -Path $PathA
            } | Should -Be $false
        }
        finally { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }
    }

    It 'should reject a file that is not XML at all' {
        $Path = New-CookieFilePath
        try {
            Set-Content -Path $Path -Value "plain text" -Encoding UTF8

            InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $Path } {
                Test-OmadaCookieCacheFile -Path $PathA
            } | Should -Be $false
        }
        finally { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }
    }
}
