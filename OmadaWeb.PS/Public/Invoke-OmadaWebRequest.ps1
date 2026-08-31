function Invoke-OmadaWebRequest {
    <#
    .SYNOPSIS
        Sends a request to an Omada web endpoint and returns the raw HTTP response.

    .DESCRIPTION
        Invoke-OmadaWebRequest wraps the built-in Invoke-WebRequest and adds the authentication
        Omada Identity Cloud and on-premises installations need. Every parameter of
        Invoke-WebRequest is accepted unchanged, so an existing call can be switched over by
        changing the command name.

        Use this command when the response itself matters - status code, headers, raw content or a
        file to download. For REST and OData endpoints that return JSON, Invoke-OmadaRestMethod is
        usually the better fit because it deserializes the response for you and can page through
        OData feeds.

        Authentication is selected with -AuthenticationType. The default, WebView2, signs in with
        an embedded Microsoft Edge browser and works for interactive use, at whichever identity
        provider your Omada tenant uses, multi-factor authentication included. OAuth authenticates
        as an application with the client-credentials grant and needs no browser, no desktop session
        and no interaction at all, which is what unattended scripts, scheduled tasks and CI
        pipelines should use - with a certificate (-ClientId together with one of the
        -OAuthCertificate* parameters) in preference to a client secret. Browser, Windows,
        Integrated and Basic cover Selenium-driven sign-in and the classic on-premises
        authentication schemes.

        After a successful interactive sign-in the session cookie is cached, encrypted with DPAPI
        for the current user, so subsequent commands in the same or a later PowerShell session do
        not prompt again. Use Clear-OmadaWebCache to remove it, or -SkipCookieCache to never write
        it. Sessions are kept apart by base URL, authentication type and, when known, user, so
        several Omada environments can be addressed from the same PowerShell session.

    .INPUTS
        None. This command does not accept pipeline input.

    .OUTPUTS
        Microsoft.PowerShell.Commands.WebResponseObject. The response returned by Invoke-WebRequest.

    .EXAMPLE
        Invoke-OmadaWebRequest -Uri "https://example.omada.cloud"

        Signs in to the Omada portal through an embedded Edge browser and returns the response.
        Useful as a first call to confirm that authentication works and to prime the cookie cache.

    .EXAMPLE
        $Response = Invoke-OmadaWebRequest -Uri "https://example.omada.cloud/api/Health"
        $Response.StatusCode

        Keeps the full response so the status code and headers can be inspected, which
        Invoke-OmadaRestMethod does not expose.

    .EXAMPLE
        $ClientCredential = Get-Credential
        Invoke-OmadaWebRequest -Uri "https://example.omada.cloud/Report/Export?id=42" -OutFile "C:\Temp\report.xlsx" -AuthenticationType "OAuth" -EntraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" -Credential $ClientCredential

        Downloads a report to disk without any interaction, authenticating to Entra ID with a
        client id and secret.

    .EXAMPLE
        Invoke-OmadaWebRequest -Uri "https://example.omada.cloud/Report/Export?id=42" -OutFile "C:\Temp\report.xlsx" -AuthenticationType "OAuth" -EntraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" -ClientId "a1b2c3d4-5e6f-7890-abcd-ef1234567890" -OAuthCertificateThumbprint "9A8B7C6D5E4F30211A2B3C4D5E6F708192A3B4C5"

        The same download from a scheduled task, authenticating with a certificate from the Windows
        certificate store rather than a client secret, so no reusable credential travels on the
        wire or sits in the script.

    .EXAMPLE
        Invoke-OmadaWebRequest -Uri "https://omada.contoso.local/OData/DataObjects" -AuthenticationType "Windows" -Credential $UserCredential

        Requests an on-premises endpoint with explicit Windows credentials, negotiating
        Kerberos or NTLM when the server issues a challenge.

    .NOTES
        The parameters this command adds on top of Invoke-WebRequest are described in the README:
        https://github.com/Fortigi/OmadaWeb.PS#parameters

    .LINK
        https://github.com/Fortigi/OmadaWeb.PS

    .LINK
        Invoke-OmadaRestMethod

    .LINK
        Clear-OmadaWebCache

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest

    .LINK
        https://documentation.omadaidentity.com/
    #>
    [CmdletBinding(DefaultParameterSetName = "StandardMethod")]
    PARAM()

    DynamicParam {
        $Script:FunctionName = "Invoke-WebRequest"
        return Set-DynamicParameter -FunctionName $Script:FunctionName
    }
    process {
        try {
            "{0}" -f $MyInvocation.MyCommand | Write-Verbose
            $BoundParams = $PsCmdLet.MyInvocation.BoundParameters
            return (Invoke-OmadaRequest @BoundParams)
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
    }
}
