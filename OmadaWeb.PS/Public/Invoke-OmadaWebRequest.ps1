function Invoke-OmadaWebRequest {
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
            Throw
        }
    }
}