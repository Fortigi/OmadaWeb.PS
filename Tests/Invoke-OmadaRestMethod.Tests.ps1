param(
    [string]$ModulePath = (Join-Path $(Split-Path $PSScriptRoot) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop -Prefix Test

    $RandomPort = Get-Random -Minimum 17000 -Maximum 19000

    . (Join-Path $PSScriptRoot 'Start-WebServer.ps1') -Action Start -Port $RandomPort -Force | Out-Null
    Start-Sleep -Seconds 2
    $Uri = "http://localhost:{0}/" -f $RandomPort

    InModuleScope 'OmadaWeb.PS' {
        if ($env:TF_BUILD -eq 'True' -or $env:TF_BUILD -eq $true) {
            #Skip WebView2 login in CI/CD pipelines
            Mock -ModuleName OmadaWeb.PS Start-WebView2Login { $Script:OmadaWebAuthCookie = [pscustomobject]@{
                    name     = "oisauthtoken"
                    value    = "test-cookie-value"
                    domain   = "localhost"
                    path     = "/"
                    expires  = $null
                    httpOnly = $true
                    secure   = $false
                    sameSite = "Lax"
                }
                $Script:UserAgent = "test-user-agent"
            } -Verifiable
        }
    }
}

Describe 'Invoke-TestOmadaRestMethod' {
    Context 'Function Definition' {
        It 'Should have Invoke-(Test)OmadaODataMethod alias' {
            (Get-Alias Invoke-TestOmadaODataMethod).ReferencedCommand.Name | Should -Eq 'Invoke-TestOmadaRestMethod'
        }

        It 'Should have CmdletBinding attribute' {
            (Get-Command Invoke-TestOmadaRestMethod).CmdletBinding | Should -Be $true
        }

        It 'Should have DefaultParameterSetName set to StandardMethod' {
            $cmd = Get-Command Invoke-TestOmadaRestMethod
            $cmd.DefaultParameterSet | Should -Be 'StandardMethod'
        }
    }

    Context 'Process Block - Success' {
        It 'Should return result from Invoke-(Test)OmadaRestMethod' {
            $result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType None
            $result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRestMethod using None Authentication' {
            $Result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType None -Verbose
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRestMethod using Basic Authentication' {
            $Credential = (New-Object System.Management.Automation.PSCredential("user", (ConvertTo-SecureString "password" -AsPlainText -Force)))
            $result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType Basic -Credential $Credential -AllowUnencryptedAuthentication
            $result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRestMethod using Windows Authentication' {
            $Credential = (New-Object System.Management.Automation.PSCredential("user", (ConvertTo-SecureString "password" -AsPlainText -Force)))
            $result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType Windows -Credential $Credential -AllowUnencryptedAuthentication
            $result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRestMethod using Integrated Authentication' {
            $result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType Integrated -AllowUnencryptedAuthentication
            $result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRestMethod using Browser Authentication using WebDriver/Selenium' {
            $result = Invoke-TestOmadaRestMethod -Uri $Uri -ForceAuthentication
            $result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRestMethod using Browser Authentication using WebDriver/Selenium -InPrivate' {
            $Result = Invoke-TestOmadaRestMethod -Uri $Uri -ForceAuthentication -InPrivate -Verbose
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRestMethod using Browser Authentication using WebView2' {
            $result = Invoke-TestOmadaRestMethod -Uri $Uri -UseWebView2 -ForceAuthentication
            $result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaRestMethod using Browser Authentication using WebView2 -InPrivate' {
            $Result = Invoke-TestOmadaRestMethod -Uri $Uri -UseWebView2 -ForceAuthentication -InPrivate -Verbose
            $Result | Should -Be "OK"
        }

        It 'Should read cookie previous from exported cookie file' {
            $CookieObject = [PSCustomObject]@{
                OmadaWebAuthCookie = [pscustomobject]@{
                    name     = "oisauthtoken"
                    value    = "test-cookie-value"
                    domain   = "localhost"
                    path     = "/"
                    expires  = $null
                    httpOnly = $true
                    secure   = $false
                    sameSite = "Lax"
                }
            }
            $CookiePath = Join-Path $Env:Temp 'localhost.cookie'
            $CookieObject | Export-Clixml -Path $CookiePath -Force
            $Result = Invoke-TestOmadaRestMethod -Uri $Uri -AuthenticationType None -CookiePath $Env:Temp -Verbose
            Get-Item $CookiePath | Remove-Item -Force
            $Result | Should -Be "OK"
        }

        It 'Should create cookie file when using CookiePath parameter using WebDriver/Selenium' {
            $CookiePath = Join-Path $Env:Temp 'localhost.cookie'
            try { Get-Item $CookiePath | Remove-Item -Force } catch { }
            Test-Path $CookiePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaRestMethod -Uri $Uri -CookiePath $Env:Temp -Verbose -ForceAuthentication | Out-Null
            Test-Path $CookiePath -PathType Leaf | Should -Be $true
        }

        It 'Should create cookie file when using CookiePath parameter using WebDriver/Selenium -InPrivate' {
            $CookiePath = Join-Path $Env:Temp 'localhost.cookie'
            try { Get-Item $CookiePath | Remove-Item -Force } catch { }
            Test-Path $CookiePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaRestMethod -Uri $Uri -CookiePath $Env:Temp -Verbose -ForceAuthentication -InPrivate | Out-Null
            Test-Path $CookiePath -PathType Leaf | Should -Be $true
        }

        It 'Should create cookie file when using CookiePath parameter using WebView2' {
            $CookiePath = Join-Path $Env:Temp 'localhost.cookie'
            try { Get-Item $CookiePath | Remove-Item -Force } catch { }
            Test-Path $CookiePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaRestMethod -Uri $Uri -CookiePath $Env:Temp -UseWebView2 -Verbose -ForceAuthentication | Out-Null
            Test-Path $CookiePath -PathType Leaf | Should -Be $true
        }

        It 'Should create cookie file when using CookiePath parameter using WebView2 -InPrivate' {
            $CookiePath = Join-Path $Env:Temp 'localhost.cookie'
            try { Get-Item $CookiePath | Remove-Item -Force } catch { }
            Test-Path $CookiePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaRestMethod -Uri $Uri -CookiePath $Env:Temp -UseWebView2 -Verbose -ForceAuthentication -InPrivate | Out-Null
            Test-Path $CookiePath -PathType Leaf | Should -Be $true
        }

        It 'Should create cached cookie file when using CookiePath parameter using WebView2' {
            $CookieCacheFilePath = Join-Path $Env:Temp -ChildPath (([System.Guid]([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($(( [System.Uri]::New($Uri)).Authority))))).Guid -replace "-", "")
            try { Get-Item $CookieCacheFilePath | Remove-Item -Force } catch { }
            Test-Path $CookieCacheFilePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaRestMethod -Uri $Uri -UseWebView2 -Verbose -ForceAuthentication | Out-Null
            Test-Path $CookieCacheFilePath -PathType Leaf | Should -Be $true
            try { Get-Item $CookieCacheFilePath | Remove-Item -Force } catch { }
        }

        It 'Should not create cached cookie file when using CookiePath parameter using WebView2' {
            $CookieCacheFilePath = Join-Path $Env:Temp -ChildPath (([System.Guid]([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($(( [System.Uri]::New($Uri)).Authority))))).Guid -replace "-", "")
            try { Get-Item $CookieCacheFilePath | Remove-Item -Force } catch { }
            Test-Path $CookieCacheFilePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaRestMethod -Uri $Uri -UseWebView2 -Verbose -ForceAuthentication -SkipCookieCache | Out-Null
            Test-Path $CookieCacheFilePath -PathType Leaf | Should -Be $false
            try { Get-Item $CookieCacheFilePath | Remove-Item -Force } catch { }
        }
    }

    Context 'Process Block - Error Handling' {
        It 'Should throw terminating error when Invoke-OmadaRestMethod fails' {
            InModuleScope 'OmadaWeb.PS' {
                Mock Invoke-OmadaRestMethod { throw "Test Error" }
            }
            { Invoke-TestOmadaRestMethod -Uri "http://localhost" -ErrorAction Stop } | Should -Throw
        }

        It 'Should throw terminating error when -WebSession is used' {
            { Invoke-TestOmadaRestMethod -Uri $Uri -ErrorAction Stop  -Verbose -WebSession null } | Should -Throw
        }
        It 'Should throw terminating error when -Authentication is used' {
            $Credential = (New-Object System.Management.Automation.PSCredential("user", (ConvertTo-SecureString "password" -AsPlainText -Force)))
            { Invoke-TestOmadaRestMethod -Uri $Uri -ErrorAction Stop  -Verbose -Authentication Basic -Credential $Credential } | Should -Throw
        }
        It 'Should throw terminating error when -SessionVariable is used' {
            { Invoke-TestOmadaRestMethod -Uri $Uri -ErrorAction Stop  -Verbose -SessionVariable session } | Should -Throw
        }
        It 'Should throw terminating error when -UseDefaultCredentials is used' {
            { Invoke-TestOmadaRestMethod -Uri $Uri -ErrorAction Stop  -Verbose -UseDefaultCredentials } | Should -Throw
        }
        It 'Should throw terminating error when -UseBasicParsing is used' {
            { Invoke-TestOmadaRestMethod -Uri $Uri -ErrorAction Stop  -Verbose -UseBasicParsing } | Should -Throw
        }
    }
}

AfterAll {
    . (Join-Path $PSScriptRoot 'Start-WebServer.ps1') -Port $RandomPort -Action Stop -Force | Out-Null
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}