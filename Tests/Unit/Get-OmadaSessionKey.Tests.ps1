param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-OmadaSessionKey' -Tag 'Unit' {
    It 'Should return the same key for identical inputs' {
        InModuleScope 'OmadaWeb.PS' {
            $Uri = [System.Uri]::new('https://example.omada.cloud')
            $Key1 = Get-OmadaSessionKey -Uri $Uri -AuthenticationType 'WebView2'
            $Key2 = Get-OmadaSessionKey -Uri $Uri -AuthenticationType 'WebView2'
            $Key1 | Should -Be $Key2
        }
    }

    It 'Should return an empty identity segment when neither Credential nor SessionKey is supplied' {
        InModuleScope 'OmadaWeb.PS' {
            $Key = Get-OmadaSessionKey -Uri ([System.Uri]::new('https://example.omada.cloud')) -AuthenticationType 'WebView2'
            $Key | Should -Be 'example.omada.cloud::webview2::'
        }
    }

    It 'Should include a non-default port in the key' {
        InModuleScope 'OmadaWeb.PS' {
            $Key = Get-OmadaSessionKey -Uri ([System.Uri]::new('https://example.omada.cloud:8443')) -AuthenticationType 'WebView2'
            $Key | Should -Be 'example.omada.cloud:8443::webview2::'
        }
    }

    It 'Should return a different key for a different AuthenticationType' {
        InModuleScope 'OmadaWeb.PS' {
            $Uri = [System.Uri]::new('https://example.omada.cloud')
            $Key1 = Get-OmadaSessionKey -Uri $Uri -AuthenticationType 'WebView2'
            $Key2 = Get-OmadaSessionKey -Uri $Uri -AuthenticationType 'OAuth'
            $Key1 | Should -Not -Be $Key2
        }
    }

    It 'Should return a different key for a different host' {
        InModuleScope 'OmadaWeb.PS' {
            $Key1 = Get-OmadaSessionKey -Uri ([System.Uri]::new('https://tenant-a.omada.cloud')) -AuthenticationType 'WebView2'
            $Key2 = Get-OmadaSessionKey -Uri ([System.Uri]::new('https://tenant-b.omada.cloud')) -AuthenticationType 'WebView2'
            $Key1 | Should -Not -Be $Key2
        }
    }

    It 'Should return a different key for a different Credential username' {
        InModuleScope 'OmadaWeb.PS' {
            $Uri = [System.Uri]::new('https://example.omada.cloud')
            $CredentialA = New-Object System.Management.Automation.PSCredential('user-a', (ConvertTo-SecureString 'x' -AsPlainText -Force))
            $CredentialB = New-Object System.Management.Automation.PSCredential('user-b', (ConvertTo-SecureString 'x' -AsPlainText -Force))
            $Key1 = Get-OmadaSessionKey -Uri $Uri -AuthenticationType 'Basic' -Credential $CredentialA
            $Key2 = Get-OmadaSessionKey -Uri $Uri -AuthenticationType 'Basic' -Credential $CredentialB
            $Key1 | Should -Not -Be $Key2
        }
    }

    It 'Should return a different key for a different explicit SessionKey when no Credential is supplied' {
        InModuleScope 'OmadaWeb.PS' {
            $Uri = [System.Uri]::new('https://example.omada.cloud')
            $Key1 = Get-OmadaSessionKey -Uri $Uri -AuthenticationType 'WebView2' -SessionKey 'user-a'
            $Key2 = Get-OmadaSessionKey -Uri $Uri -AuthenticationType 'WebView2' -SessionKey 'user-b'
            $Key1 | Should -Not -Be $Key2
        }
    }

    It 'Should prefer Credential over SessionKey when both are supplied' {
        InModuleScope 'OmadaWeb.PS' {
            $Uri = [System.Uri]::new('https://example.omada.cloud')
            $Credential = New-Object System.Management.Automation.PSCredential('user-a', (ConvertTo-SecureString 'x' -AsPlainText -Force))
            $KeyWithSessionKeyOnly = Get-OmadaSessionKey -Uri $Uri -AuthenticationType 'WebView2' -SessionKey 'user-a'
            $KeyWithBoth = Get-OmadaSessionKey -Uri $Uri -AuthenticationType 'WebView2' -Credential $Credential -SessionKey 'ignored'
            $KeyWithBoth | Should -Be $KeyWithSessionKeyOnly
        }
    }

    It 'Should be case-insensitive for host, auth type, and session key' {
        InModuleScope 'OmadaWeb.PS' {
            $Key1 = Get-OmadaSessionKey -Uri ([System.Uri]::new('https://EXAMPLE.omada.cloud')) -AuthenticationType 'WebView2' -SessionKey 'User-A'
            $Key2 = Get-OmadaSessionKey -Uri ([System.Uri]::new('https://example.omada.cloud')) -AuthenticationType 'webview2' -SessionKey 'user-a'
            $Key1 | Should -Be $Key2
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
