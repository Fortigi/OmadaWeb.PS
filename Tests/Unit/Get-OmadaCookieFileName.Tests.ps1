param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaCookieFileName' -Tag 'Unit' {
    It 'Should return the plain "<Authority>.cookie" name when no Credential or SessionKey is supplied' {
        InModuleScope 'OmadaWeb.PS' {
            $Name = Get-OmadaCookieFileName -Uri ([System.Uri]::new('http://localhost:19000/'))
            $Name | Should -Be 'localhost_19000.cookie'
        }
    }

    It 'Should append an identity hash suffix when a Credential is supplied' {
        InModuleScope 'OmadaWeb.PS' {
            $Credential = New-Object System.Management.Automation.PSCredential('user-a', (ConvertTo-SecureString 'x' -AsPlainText -Force))
            $Name = Get-OmadaCookieFileName -Uri ([System.Uri]::new('http://localhost:19000/')) -Credential $Credential
            $Name | Should -Not -Be 'localhost_19000.cookie'
            $Name | Should -BeLike 'localhost_19000_*.cookie'
        }
    }

    It 'Should append an identity hash suffix when a SessionKey is supplied' {
        InModuleScope 'OmadaWeb.PS' {
            $Name = Get-OmadaCookieFileName -Uri ([System.Uri]::new('http://localhost:19000/')) -SessionKey 'user-a'
            $Name | Should -BeLike 'localhost_19000_*.cookie'
        }
    }

    It 'Should produce different file names for two different SessionKey values, keeping -CookiePath sessions apart' {
        InModuleScope 'OmadaWeb.PS' {
            $Uri = [System.Uri]::new('http://localhost:19000/')
            $NameA = Get-OmadaCookieFileName -Uri $Uri -SessionKey 'user-a'
            $NameB = Get-OmadaCookieFileName -Uri $Uri -SessionKey 'user-b'
            $NameA | Should -Not -Be $NameB
        }
    }

    It 'Should produce the same file name for the same Credential username across calls (idempotent)' {
        InModuleScope 'OmadaWeb.PS' {
            $Uri = [System.Uri]::new('http://localhost:19000/')
            $Credential = New-Object System.Management.Automation.PSCredential('user-a', (ConvertTo-SecureString 'x' -AsPlainText -Force))
            $Name1 = Get-OmadaCookieFileName -Uri $Uri -Credential $Credential
            $Name2 = Get-OmadaCookieFileName -Uri $Uri -Credential $Credential
            $Name1 | Should -Be $Name2
        }
    }

    It 'Should prefer Credential over SessionKey when both are supplied, matching Get-OmadaSessionKey' {
        InModuleScope 'OmadaWeb.PS' {
            $Uri = [System.Uri]::new('http://localhost:19000/')
            $Credential = New-Object System.Management.Automation.PSCredential('user-a', (ConvertTo-SecureString 'x' -AsPlainText -Force))
            $NameCredentialOnly = Get-OmadaCookieFileName -Uri $Uri -Credential $Credential
            $NameBoth = Get-OmadaCookieFileName -Uri $Uri -Credential $Credential -SessionKey 'ignored'
            $NameBoth | Should -Be $NameCredentialOnly
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
