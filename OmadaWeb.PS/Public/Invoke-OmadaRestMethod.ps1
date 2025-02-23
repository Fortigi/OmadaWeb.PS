function Invoke-OmadaRestMethod {
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
            Throw
        }
    }
}