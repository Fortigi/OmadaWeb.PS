function Invoke-WindowsAuthentication {
    [CmdletBinding()]
    PARAM()

    "{0} - Set Windows authentication" -f $MyInvocation.MyCommand | Write-Verbose
    if ($BoundParams.keys -notcontains "Credential") {
        $BoundParams.Add("Credential", (Get-Credential -Message "Please enter your authentication credentials"))
    }
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $BoundParams.Add("Authentication", "Negotiate")
    }
}