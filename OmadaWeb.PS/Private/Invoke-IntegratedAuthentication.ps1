function Invoke-IntegratedAuthentication {
    [CmdletBinding()]
    PARAM()
    
    "{0} - Set integrated authentication" -f $MyInvocation.MyCommand, $_ | Write-Verbose
    $BoundParams.Add("UseDefaultCredentials", $true)
}