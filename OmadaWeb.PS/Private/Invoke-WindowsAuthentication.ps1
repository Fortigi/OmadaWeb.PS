function Invoke-WindowsAuthentication {
    [CmdletBinding()]
    PARAM()

    "{0} - Set Windows authentication" -f $MyInvocation.MyCommand | Write-Verbose
    if ($BoundParams.keys -notcontains "Credential") {
        $BoundParams.Add("Credential", (Get-Credential -Message "Please enter your authentication credentials"))
    }
    if ($BoundParams.Keys -contains "Headers" -and $BoundParams.Headers.ContainsKey("Authorization")) {
        $BoundParams.Headers.Remove("Authorization")
    }
}