function Invoke-BasicAuthentication {
    [CmdletBinding()]
    PARAM(
        [Parameter(Mandatory)]
        [PSTypeName("OmadaWeb.PS.RequestContext")]$RequestContext
    )

    $BoundParams = $RequestContext.BoundParams

    "{0} - Set Basic authentication" -f $MyInvocation.MyCommand | Write-Verbose

    if ($BoundParams.keys -notcontains "Credential") {
        $BoundParams.Add("Credential", (Get-Credential -Message "Please enter your authentication credentials"))
    }
    $CredentialPair = "{0}:{1}" -f $BoundParams['Credential'].UserName.Trim(), $BoundParams['Credential'].GetNetworkCredential().Password
    $EncodedCredential = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($CredentialPair))
    # Indexer assignment, not .Add: a caller-supplied Authorization header may already be present,
    # and the Basic authentication the caller asked for overrides it rather than throwing on a
    # duplicate key.
    $BoundParams['Headers']['Authorization'] = "Basic {0}" -f $EncodedCredential

    return $RequestContext
}
