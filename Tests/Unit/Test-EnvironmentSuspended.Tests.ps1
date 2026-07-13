param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    function Start-TestHttpListener {
        param(
            [Parameter(Mandatory)]
            [string]$ResponseBody
        )

        $Port = Get-Random -Minimum 19500 -Maximum 19999
        $Listener = [System.Net.HttpListener]::new()
        $Listener.Prefixes.Add("http://127.0.0.1:$Port/")
        $Listener.Start()

        # A background PowerShell instance (its own runspace) accepts the single request and
        # writes the response - a plain .NET Task/delegate can't safely invoke a PowerShell
        # scriptblock since it has no runspace of its own on that thread.
        $PowerShellInstance = [powershell]::Create()
        $null = $PowerShellInstance.AddScript(
            {
                param($ListenerParam, $ResponseBodyParam)
                try {
                    $Context = $ListenerParam.GetContext()
                    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($ResponseBodyParam)
                    $Context.Response.StatusCode = 200
                    $Context.Response.ContentLength64 = $Bytes.Length
                    $Context.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
                    $Context.Response.OutputStream.Close()
                }
                catch {}
            }
        ).AddArgument($Listener).AddArgument($ResponseBody)
        $AsyncResult = $PowerShellInstance.BeginInvoke()

        return [PSCustomObject]@{
            Listener           = $Listener
            Url                = "http://127.0.0.1:$Port/"
            PowerShellInstance = $PowerShellInstance
            AsyncResult        = $AsyncResult
        }
    }

    function Stop-TestHttpListener {
        param(
            [Parameter(Mandatory)]
            [PSCustomObject]$Server
        )

        try { $Server.Listener.Stop() } catch {}
        try { $Server.Listener.Close() } catch {}
        # End the async pipeline started with BeginInvoke before disposing so the background
        # runspace is properly completed and any exception it raised is observed. Stopping the
        # listener above unblocks a pending GetContext() (it throws, which the scriptblock
        # swallows), so EndInvoke returns promptly instead of leaving the pipeline unobserved.
        try { $Server.PowerShellInstance.EndInvoke($Server.AsyncResult) } catch {}
        try { $Server.PowerShellInstance.Dispose() } catch {}
    }
}

Describe 'Test-EnvironmentSuspended' -Tag 'Unit' {
    Context 'Function Definition' {
        It 'Should have Url as a mandatory parameter' {
            InModuleScope 'OmadaWeb.PS' {
                (Get-Command Test-EnvironmentSuspended).Parameters['Url'].Attributes.Mandatory | Should -Contain $true
            }
        }

        It 'Should have a default TimeoutSec value of 5' {
            InModuleScope 'OmadaWeb.PS' {
                $Ast = (Get-Command Test-EnvironmentSuspended).ScriptBlock.Ast
                $ParameterAst = $Ast.Find(
                    { $args[0] -is [System.Management.Automation.Language.ParameterAst] -and $args[0].Name.VariablePath.UserPath -eq 'TimeoutSec' },
                    $true
                )
                $ParameterAst.DefaultValue.Value | Should -Be 5
            }
        }
    }

    Context 'Environment is active' {
        It 'Should return $false when the response does not contain the suspended marker' {
            $Server = Start-TestHttpListener -ResponseBody 'OK'
            try {
                InModuleScope 'OmadaWeb.PS' -Parameters @{ TestUrl = $Server.Url } {
                    Test-EnvironmentSuspended -Url $TestUrl | Should -Be $false
                }
            }
            finally {
                Stop-TestHttpListener -Server $Server
            }
        }
    }

    Context 'Environment is suspended' {
        It 'Should return $true when the response contains the suspended marker' {
            $Server = Start-TestHttpListener -ResponseBody '<html><body>The environment is suspended</body></html>'
            try {
                InModuleScope 'OmadaWeb.PS' -Parameters @{ TestUrl = $Server.Url } {
                    Test-EnvironmentSuspended -Url $TestUrl | Should -Be $true
                }
            }
            finally {
                Stop-TestHttpListener -Server $Server
            }
        }
    }

    Context 'Environment is unreachable' {
        It 'Should return $false when the request fails' {
            $Server = Start-TestHttpListener -ResponseBody 'OK'
            $Url = $Server.Url
            Stop-TestHttpListener -Server $Server

            InModuleScope 'OmadaWeb.PS' -Parameters @{ TestUrl = $Url } {
                Test-EnvironmentSuspended -Url $TestUrl -TimeoutSec 2 | Should -Be $false
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
