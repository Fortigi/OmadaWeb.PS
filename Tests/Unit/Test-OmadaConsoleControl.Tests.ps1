param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    # A host with no console attached, built deterministically rather than hoped for. The suite is
    # run both from a real console and from an editor or a CI job, so asserting the no-console
    # behaviour in-process would assert whichever one the developer happened to have. A child pwsh
    # whose streams are redirected is the same shape as a GitHub Actions step every time.
    $Script:ChildScriptFolder = Join-Path ([System.IO.Path]::GetTempPath()) ("OmadaWebConsoleTests_{0}" -f [guid]::NewGuid().ToString("N"))
    $null = New-Item -ItemType Directory -Force -Path $Script:ChildScriptFolder

    function Invoke-InConsolelessHost {
        param(
            [Parameter(Mandatory)]
            [string]$Body
        )

        $ScriptPath = Join-Path $Script:ChildScriptFolder ("probe_{0}.ps1" -f [guid]::NewGuid().ToString("N"))
        $Preamble = @(
            'Set-StrictMode -Version Latest',
            ('$Module = Import-Module "{0}" -Force -PassThru -WarningAction SilentlyContinue -ErrorAction Stop' -f $ModulePath)
        ) -join [System.Environment]::NewLine

        ($Preamble, $Body) -join [System.Environment]::NewLine | Set-Content -LiteralPath $ScriptPath -Encoding UTF8

        # Start-Process with redirected streams, so the child genuinely has no console handle. Running
        # it through the current host would inherit this process's console and prove nothing.
        $StdOut = Join-Path $Script:ChildScriptFolder ("out_{0}.txt" -f [guid]::NewGuid().ToString("N"))
        $StdErr = Join-Path $Script:ChildScriptFolder ("err_{0}.txt" -f [guid]::NewGuid().ToString("N"))
        $Process = Start-Process -FilePath (Get-Command pwsh.exe).Source `
            -ArgumentList @("-NoLogo", "-NoProfile", "-File", ('"{0}"' -f $ScriptPath)) `
            -RedirectStandardOutput $StdOut -RedirectStandardError $StdErr `
            -NoNewWindow -PassThru -Wait

        return [pscustomobject]@{
            ExitCode = $Process.ExitCode
            Output   = (Get-Content -LiteralPath $StdOut -Raw -ErrorAction SilentlyContinue)
            Error    = (Get-Content -LiteralPath $StdErr -Raw -ErrorAction SilentlyContinue)
        }
    }
}

AfterAll {
    Remove-Item -LiteralPath $Script:ChildScriptFolder -Recurse -Force -ErrorAction SilentlyContinue
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}

Describe 'Test-OmadaConsoleControl' -Tag 'Unit' {

    It 'Answers with a boolean whatever host it is asked in' {
        $Result = InModuleScope 'OmadaWeb.PS' { Test-OmadaConsoleControl }

        $Result | Should -BeOfType [System.Boolean]
    }

    It 'Never throws, which is the whole point of it' {
        { InModuleScope 'OmadaWeb.PS' { Test-OmadaConsoleControl } } | Should -Not -Throw
    }

    It 'Agrees with what the console actually allows' {
        # Not a tautology: it asserts the predicate reports the same thing the guarded call site will
        # experience a moment later. A probe that answered from something else - a redirection flag,
        # a cached value - could differ from it, and that difference is the bug.
        $Expected = $true
        try {
            $null = [Console]::TreatControlCAsInput
        }
        catch {
            $Expected = $false
        }

        InModuleScope 'OmadaWeb.PS' { Test-OmadaConsoleControl } | Should -Be $Expected
    }

    It 'Reports false in a host that has no console' {
        # The answer is tagged rather than read off the whole stream: importing the module emits a
        # WebView2 warning on the way in, so matching the child's entire output would be asserting
        # against that warning as much as against the result.
        $Result = Invoke-InConsolelessHost -Body '"RESULT:{0}" -f (& $Module { Test-OmadaConsoleControl }) | Write-Output'

        $Result.Output | Should -Match 'RESULT:False'
    }
}

Describe 'Start-WebView2Login without a console' -Tag 'Unit' {

    It 'Does not fail on the console handle before it has even opened a browser' {
        # The regression test for issue #79, and it discriminates rather than passing by luck.
        #
        # The console read used to be the second statement in Start-WebView2Login, ahead of everything
        # else it does, so in a host with no console it threw "The handle is invalid" before any
        # browser window existed - and the canary reported that as Microsoft having changed its
        # sign-in page.
        #
        # Called here with no session context, so it still fails: what is asserted is *which* failure.
        # Without the guard the message is the console one; with it, the function gets past that line
        # and falls over on something later, which is what this looks for.
        $Result = Invoke-InConsolelessHost -Body @'
$Message = ""
try {
    & $Module { Start-WebView2Login -EdgeProfile "Default" }
}
catch {
    $Message = $_.Exception.Message
}
"CAUGHT: $Message" | Write-Output
'@

        $Combined = "{0}`n{1}" -f $Result.Output, $Result.Error
        $Combined | Should -Not -Match 'handle is invalid'
    }
}
