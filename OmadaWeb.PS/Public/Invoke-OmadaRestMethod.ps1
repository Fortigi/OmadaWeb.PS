function Invoke-OmadaRestMethod {
    <#
    .SYNOPSIS
        Sends a request to an Omada REST or OData endpoint and returns the response as objects.

    .DESCRIPTION
        Invoke-OmadaRestMethod wraps the built-in Invoke-RestMethod and adds the authentication
        Omada Identity Cloud and on-premises installations need. Every parameter of
        Invoke-RestMethod is accepted unchanged, so an existing call can be switched over by
        changing the command name.

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

        For OData feeds that return results one page at a time, -Paged follows every
        @odata.nextLink and returns the complete result set as a single object.

        The command name Invoke-OmadaODataMethod is an alias for this command.

    .INPUTS
        None. This command does not accept pipeline input.

    .OUTPUTS
        System.Object. The response, deserialized the same way Invoke-RestMethod deserializes it.

    .EXAMPLE
        Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)"

        Retrieves one identity from the OData endpoint. Because no -AuthenticationType is given, an
        embedded Edge browser opens for sign-in the first time; later commands reuse the cached
        session cookie.

    .EXAMPLE
        Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity" -Paged

        Retrieves every identity from a paged OData feed. Without -Paged only the first page is
        returned, together with an @odata.nextLink property.

    .EXAMPLE
        $ClientCredential = Get-Credential
        $Identities = Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity" -Paged -AuthenticationType "OAuth" -EntraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" -Credential $ClientCredential

        Extracts all identities without any interaction, authenticating to Entra ID with a client
        id and secret.

    .EXAMPLE
        $Identities = Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity" -Paged -AuthenticationType "OAuth" -EntraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" -ClientId "a1b2c3d4-5e6f-7890-abcd-ef1234567890" -OAuthCertificateThumbprint "9A8B7C6D5E4F30211A2B3C4D5E6F708192A3B4C5"

        The same unattended extraction, authenticating with a certificate from the Windows
        certificate store instead of a client secret. The private key never leaves the machine, so
        nothing reusable travels on the wire. This is the form to use in scheduled tasks, CI
        pipelines and on servers without a desktop session. The certificate is looked for in
        CurrentUser\My and then in LocalMachine\My.

    .EXAMPLE
        $CertificatePassword = ConvertTo-SecureString $env:OMADA_PFX_PASSWORD -AsPlainText -Force
        Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -AuthenticationType "OAuth" -EntraIdTenantId "c1ec94c3-4a7a-4568-9321-79b0a74b8e70" -ClientId "a1b2c3d4-5e6f-7890-abcd-ef1234567890" -OAuthCertificatePath "C:\ProgramData\OmadaJobs\automation.pfx" -OAuthCertificatePassword $CertificatePassword

        Authenticates with a certificate held in a password-protected PKCS#12 file, which is what a
        container or a job running under an account without a certificate store needs.

    .EXAMPLE
        $Body = @{ FIRSTNAME = "Jane"; LASTNAME = "Doe" }
        Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/api/DataObject/Identity" -Method "POST" -Body $Body

        Creates an object through the Omada API. -Body is accepted as a hashtable and sent as JSON;
        the Content-Type and Accept headers default to application/json.

    .EXAMPLE
        Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -AuthenticationType "Browser"

        Signs in through a full Microsoft Edge browser driven by Selenium instead of the embedded
        WebView2 browser. The matching WebDriver version is installed automatically.

    .EXAMPLE
        Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -Credential $UserCredential

        Signs in interactively, but hands the sign-in page the account to use and fills in the
        password, which saves picking the right account when several are signed in. With number
        matching multi-factor authentication the number is copied to the clipboard, so with Phone
        Link and clipboard sharing active it can be pasted straight into the Authenticator app.

    .EXAMPLE
        Invoke-OmadaRestMethod -Uri "https://example.omada.cloud/odata/dataobjects/identity(123456)" -AuthenticationType "OAuth" -OAuthUri "https://dev-505878.okta.com/oauth2/ausc0u4lq9sPySN5W4x7/v1/token" -OAuthScope "omadaIdentityCloud" -Credential $ClientCredential

        Authenticates against an identity provider other than Entra ID - here Okta - by supplying
        the token endpoint and scope explicitly.

    .EXAMPLE
        Invoke-OmadaRestMethod -Uri "https://omada.contoso.local/odata/dataobjects/identity(123456)" -AuthenticationType "Integrated"

        Retrieves an identity from an on-premises installation using Windows Integrated
        Authentication, without opening a browser.

    .NOTES
        The parameters this command adds on top of Invoke-RestMethod are described in the README:
        https://github.com/Fortigi/OmadaWeb.PS#parameters

    .LINK
        https://github.com/Fortigi/OmadaWeb.PS

    .LINK
        Invoke-OmadaWebRequest

    .LINK
        Clear-OmadaWebCache

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod

    .LINK
        https://documentation.omadaidentity.com/
    #>
    [Alias("Invoke-OmadaODataMethod")]
    [CmdletBinding(DefaultParameterSetName = "StandardMethod")]
    PARAM()

    DynamicParam {
        $Script:FunctionName = "Invoke-RestMethod"
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
