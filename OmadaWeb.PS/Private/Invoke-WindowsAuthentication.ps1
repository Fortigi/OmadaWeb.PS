function Invoke-WindowsAuthentication {
    "{0} - Set Windows authentication" -f $MyInvocation.MyCommand, $_ | Write-Verbose
    if ($BoundParams.keys -notcontains "Credential") {
        $BoundParams.Add("Credential", (Get-Credential -Message "Please enter your authentication credentials"))
    }
    $CredentialPair = "{0}:{1}" -f $BoundParams.Credential.UserName, $BoundParams.Credential.GetNetworkCredential().Password
    $EncodedCredential = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($CredentialPair))
    $BoundParams.Headers.Add("Authorization" , ("Basic {0}" -f $EncodedCredential))
}