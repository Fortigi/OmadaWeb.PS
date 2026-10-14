<#
.SYNOPSIS
    Drives one of the canary sign-ins that is not meant to finish, and writes everything the module
    traced to standard output.
.DESCRIPTION
    The two watched scenarios - a user name with no password, and neither - end with a browser window
    waiting for a person who does not exist on a runner. Nothing inside the process that shows that
    window can interrupt it: the WinForms dialog blocks the thread it is shown on. So the sign-in is
    run out of process and killed from outside, and this script is what that process runs.

    It exists as a file, rather than as the script block of a background job, because of the apartment.
    WebView2 is COM and needs a single-threaded apartment; Start-Job runs its script in a runspace
    whose thread is MTA, so CoreWebView2Environment::CreateAsync came straight back with
    "Cannot change thread mode after it is set (RPC_E_CHANGED_MODE)" and the browser was never
    created. Every assertion in the two watched scenarios then failed for the same reason, and the
    canary reported it as a changed Microsoft sign-in page - issue #90. A child process started with
    -STA is a host the browser can actually live in, and it is still a separate process, which is what
    made a background job the right shape in the first place.

    Nothing is redacted here beyond what the module already does: Protect-LogMessage covers its own
    streams, and the workflow masks the four canary secrets before this runs.
.PARAMETER ModulePath
    The built OmadaWeb.PS.psm1 to sign in with.
.PARAMETER ResourceUrl
    The loopback stand-in's protected resource, from Tests/E2E/Start-CanaryRelyingParty.ps1.
.PARAMETER UserName
    The account to name on the call, or empty for the scenario that names none. Empty is a scenario
    rather than an oversight: what it proves is that the module adds nothing to the request.
.EXAMPLE
    pwsh -STA -NoLogo -NoProfile -File ./Tests/E2E/Start-WatchedSignIn.ps1 `
        -ModulePath ./buildoutput/OmadaWeb.PS/OmadaWeb.PS.psm1 -ResourceUrl http://localhost:8400/resource
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ModulePath,

    [Parameter(Mandatory)]
    [string]$ResourceUrl,

    [AllowEmptyString()]
    [string]$UserName = ''
)

$VerbosePreference = 'Continue'

# Said out loud, and first. If this ever reads MTA again the trace says so on line one, instead of
# leaving a reader to work backwards from a COM error code.
"Start-WatchedSignIn - Apartment state: {0}" -f [System.Threading.Thread]::CurrentThread.GetApartmentState() | Write-Host

Import-Module $ModulePath -Force -ErrorAction Stop

$Parameter = @{
    Uri                = $ResourceUrl
    AuthenticationType = 'WebView2'
    SkipCookieCache    = $true
}

# PowerShell 7 refuses to send a credential over an unencrypted connection without being told to, and
# the stand-in serves plain HTTP on loopback. Guarded by version because the parameter does not exist
# on Windows PowerShell 5.1.
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $Parameter['AllowUnencryptedAuthentication'] = $true
}

if (-not [string]::IsNullOrWhiteSpace($UserName)) {
    $Parameter['UserName'] = $UserName
}

# Every stream, as strings, as they are produced. The verbose trace is the product here: what is being
# asserted is which decisions the module took on a page it could read perfectly well, and those are
# only ever reported there.
Invoke-OmadaWebRequest @Parameter -Verbose *>&1 | ForEach-Object { $_.ToString() | Write-Host }
