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

Describe 'Invoke-TestOmadaWebRequest' {
    Context 'Function Definition' {

        It 'Should have CmdletBinding attribute' {
            (Get-Command Invoke-TestOmadaWebRequest).CmdletBinding | Should -Be $true
        }

        It 'Should have DefaultParameterSetName set to StandardMethod' {
            $cmd = Get-Command Invoke-TestOmadaWebRequest
            $cmd.DefaultParameterSet | Should -Be 'StandardMethod'
        }
    }

    Context 'Process Block - Success' {
        It 'Should return result from Invoke-(Test)OmadaWebRequest' {
            $Result = Invoke-TestOmadaWebRequest -Uri $Uri -AuthenticationType None -SkipHttpErrorCheck -Verbose
            $Result.StatusCode | Should -Be 200
        }

        It 'Should return result from Invoke-(Test)OmadaWebRequest using None Authentication' {
            $Result = Invoke-TestOmadaWebRequest -Uri $Uri -AuthenticationType None -Verbose
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaWebRequest using Basic Authentication' {
            $Credential = (New-Object System.Management.Automation.PSCredential("user", (ConvertTo-SecureString "password" -AsPlainText -Force)))
            $Result = Invoke-TestOmadaWebRequest -Uri $Uri -AuthenticationType Basic -Credential $Credential -AllowUnencryptedAuthentication -Verbose
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaWebRequest using Windows Authentication' {
            $Credential = (New-Object System.Management.Automation.PSCredential("user", (ConvertTo-SecureString "password" -AsPlainText -Force)))
            $Result = Invoke-TestOmadaWebRequest -Uri $Uri -AuthenticationType Windows -Credential $Credential -AllowUnencryptedAuthentication -Verbose
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaWebRequest using Integrated Authentication' {
            $Result = Invoke-TestOmadaWebRequest -Uri $Uri -AuthenticationType Integrated -AllowUnencryptedAuthentication -Verbose
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaWebRequest using Browser Authentication using WebDriver/Selenium' {
            $Result = Invoke-TestOmadaWebRequest -Uri $Uri -ForceAuthentication -Verbose
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaWebRequest using Browser Authentication using WebDriver/Selenium -InPrivate' {
            $Result = Invoke-TestOmadaWebRequest -Uri $Uri -ForceAuthentication -InPrivate -Verbose
            $Result | Should -Be "OK"
        }


        Context 'Process Block - WebView2 Authentication' {
            BeforeAll {
                $Result = Invoke-TestOmadaWebRequest -Uri $Uri -UseWebView2 -ForceAuthentication -WarningVariable WarningOutput
            }
            It 'Should return result from Invoke-(Test)OmadaRestMethod using Browser Authentication using -UseWebView2' {
                $Result | Should -Be "OK"
            }
            It 'Should return warning that -UseWebView2 is deprecated' {
                $WarningOutput | Should -BeLike "*UseWebView2 is deprecated*"
            }
        }

        Context 'Process Block - WebView2 Authentication -InPrivate' {
            BeforeAll {
                $Result = Invoke-TestOmadaWebRequest -Uri $Uri -UseWebView2 -ForceAuthentication -InPrivate -WarningVariable WarningOutput -Verbose
            }
            It 'Should return result from Invoke-(Test)OmadaRestMethod using Browser Authentication using -UseWebView2 -InPrivate' {
                $Result | Should -Be "OK"

            }
            It 'Should return warning that -UseWebView2 is deprecated' {
                $WarningOutput | Should -BeLike "*UseWebView2 is deprecated*"
            }
        }

        It 'Should return result from Invoke-(Test)OmadaWebRequest using Browser Authentication using AuthenticationType WebView2' {
            $result = Invoke-TestOmadaWebRequest -Uri $Uri -AuthenticationType WebView2 -ForceAuthentication
            $result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaWebRequest using Browser Authentication using AuthenticationType WebView2 -InPrivate' {
            $Result = Invoke-TestOmadaWebRequest -Uri $Uri -AuthenticationType WebView2 -ForceAuthentication -InPrivate -Verbose
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaWebRequest using a custom OAuthUri' {
            $Credential = (New-Object System.Management.Automation.PSCredential("user", (ConvertTo-SecureString "password" -AsPlainText -Force)))
            $Result = Invoke-TestOmadaWebRequest -Uri $Uri -AuthenticationType OAuth -ForceAuthentication -Credential $Credential  -OAuthUri $Uri -AllowUnencryptedAuthentication -Verbose
            $Result | Should -Be "OK"
        }

        It 'Should return result from Invoke-(Test)OmadaWebRequest using a custom OAuthUri and OAuthScope' {
            $Credential = (New-Object System.Management.Automation.PSCredential("user", (ConvertTo-SecureString "password" -AsPlainText -Force)))
            $Result = Invoke-TestOmadaWebRequest -Uri $Uri -AuthenticationType OAuth -ForceAuthentication -Credential $Credential -OAuthUri $Uri -OAuthScope $Uri  -AllowUnencryptedAuthentication -WarningVariable Test -Verbose
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
            $Result = Invoke-TestOmadaWebRequest -Uri $Uri -AuthenticationType None -CookiePath $Env:Temp -Verbose
            Get-Item $CookiePath | Remove-Item -Force
            $Result | Should -Be "OK"
        }

        It 'Should create cookie file when using CookiePath parameter using WebDriver/Selenium' {
            $CookiePath = Join-Path $Env:Temp 'localhost.cookie'
            try { Get-Item $CookiePath | Remove-Item -Force } catch { }
            Test-Path $CookiePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaWebRequest -Uri $Uri -CookiePath $Env:Temp -Verbose -ForceAuthentication | Out-Null
            Test-Path $CookiePath -PathType Leaf | Should -Be $true
        }

        It 'Should create cookie file when using CookiePath parameter using WebDriver/Selenium -InPrivate' {
            $CookiePath = Join-Path $Env:Temp 'localhost.cookie'
            try { Get-Item $CookiePath | Remove-Item -Force } catch { }
            Test-Path $CookiePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaWebRequest -Uri $Uri -CookiePath $Env:Temp -Verbose -ForceAuthentication -InPrivate | Out-Null
            Test-Path $CookiePath -PathType Leaf | Should -Be $true
        }

        It 'Should create cookie file when using CookiePath parameter using WebView2' {
            $CookiePath = Join-Path $Env:Temp 'localhost.cookie'
            try { Get-Item $CookiePath | Remove-Item -Force } catch { }
            Test-Path $CookiePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaWebRequest -Uri $Uri -CookiePath $Env:Temp -UseWebView2 -Verbose -ForceAuthentication | Out-Null
            Test-Path $CookiePath -PathType Leaf | Should -Be $true
        }

        It 'Should create cookie file when using CookiePath parameter using WebView2 -InPrivate' {
            $CookiePath = Join-Path $Env:Temp 'localhost.cookie'
            try { Get-Item $CookiePath | Remove-Item -Force } catch { }
            Test-Path $CookiePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaWebRequest -Uri $Uri -CookiePath $Env:Temp -UseWebView2 -Verbose -ForceAuthentication -InPrivate | Out-Null
            Test-Path $CookiePath -PathType Leaf | Should -Be $true
        }

        It 'Should create cached cookie file when using CookiePath parameter using WebView2' {
            $CookieCacheFilePath = Join-Path $Env:Temp -ChildPath (([System.Guid]([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($(( [System.Uri]::New($Uri)).Authority))))).Guid -replace "-", "")
            try { Get-Item $CookieCacheFilePath | Remove-Item -Force } catch { }
            Test-Path $CookieCacheFilePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaWebRequest -Uri $Uri -UseWebView2 -Verbose -ForceAuthentication | Out-Null
            Test-Path $CookieCacheFilePath -PathType Leaf | Should -Be $true
            try { Get-Item $CookieCacheFilePath | Remove-Item -Force } catch { }
        }

        It 'Should not create cached cookie file when using CookiePath parameter using WebView2' {
            $CookieCacheFilePath = Join-Path $Env:Temp -ChildPath (([System.Guid]([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($(( [System.Uri]::New($Uri)).Authority))))).Guid -replace "-", "")
            try { Get-Item $CookieCacheFilePath | Remove-Item -Force } catch { }
            Test-Path $CookieCacheFilePath -PathType Leaf | Should -Be $false
            Invoke-TestOmadaWebRequest -Uri $Uri -UseWebView2 -Verbose -ForceAuthentication -SkipCookieCache | Out-Null
            Test-Path $CookieCacheFilePath -PathType Leaf | Should -Be $false
            try { Get-Item $CookieCacheFilePath | Remove-Item -Force } catch { }
        }
    }

    Context 'Process Block - Error Handling' {
        It 'Should throw terminating error when Invoke-OmadaRequest fails' {
            InModuleScope 'OmadaWeb.PS' {
                Mock Invoke-OmadaRequest { throw "Test Error" }
            }
            { Invoke-TestOmadaWebRequest -Uri "http://localhost" -ErrorAction Stop  -Verbose } | Should -Throw
        }

        It 'Should throw terminating error when -WebSession is used' {
            { Invoke-TestOmadaWebRequest -Uri $Uri -ErrorAction Stop  -Verbose -WebSession null } | Should -Throw
        }
        It 'Should throw terminating error when -Authentication is used' {
            $Credential = (New-Object System.Management.Automation.PSCredential("user", (ConvertTo-SecureString "password" -AsPlainText -Force)))
            { Invoke-TestOmadaWebRequest -Uri $Uri -ErrorAction Stop  -Verbose -Authentication Basic -Credential $Credential } | Should -Throw

        }
        It 'Should throw terminating error when -SessionVariable is used' {
            { Invoke-TestOmadaWebRequest -Uri $Uri -ErrorAction Stop  -Verbose -SessionVariable session } | Should -Throw
        }
        It 'Should throw terminating error when -UseDefaultCredentials is used' {
            { Invoke-TestOmadaWebRequest -Uri $Uri -ErrorAction Stop  -Verbose -UseDefaultCredentials } | Should -Throw
        }
        It 'Should throw terminating error when -UseBasicParsing is used' {
            { Invoke-TestOmadaWebRequest -Uri $Uri -ErrorAction Stop  -Verbose -UseBasicParsing } | Should -Throw
        }
    }
}

AfterAll {
    . (Join-Path $PSScriptRoot 'Start-WebServer.ps1') -Port $RandomPort -Action Stop -Force | Out-Null
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}