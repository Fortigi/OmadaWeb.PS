function Invoke-IntegratedAuthentication {
    "{0} - Set integrated authentication" -f $MyInvocation.MyCommand, $_ | Write-Verbose
    $BoundParams.Add("UseDefaultCredentials", $true)
}