function Invoke-IntegratedAuthentication {
    [CmdletBinding()]
    PARAM(
        [Parameter(Mandatory)]
        [PSTypeName("OmadaWeb.PS.RequestContext")]$RequestContext
    )

    "{0} - Set integrated authentication" -f $MyInvocation.MyCommand | Write-Verbose
    $RequestContext.BoundParams.Add("UseDefaultCredentials", $true)

    return $RequestContext
}
