function Set-OmadaCurrentBaseUrl {
    # This function exists to keep the PSAvoidGlobalVars suppression small. The rule offers no
    # per-variable suppression ID - passing a variable name as the attribute's second argument makes
    # PSScriptAnalyzer report "Cannot find any DiagnosticRecord with the Rule Suppression ID" and
    # suppress nothing - so the attribute always covers the whole scope it sits on. Sitting on
    # Invoke-OmadaRequest it covered a 400-line function, where a new, unrelated global would have
    # been silently suppressed. Here it covers six lines that do nothing else.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidGlobalVars", "", Justification = "OmadaWebPSCurrentBaseUrl is deliberately global: it is part of the module's public surface, readable by callers to see which environment the last request went to. It is initialized in OmadaWeb.PS.psm1, maintained here, and cleared by Clear-OmadaWebCache (through Set-Variable -Scope Global, a form this rule does not flag).")]
    [CmdletBinding()]
    param(
        # Untyped and null-permitting on purpose: a [string] constraint would turn $null into an
        # empty string, and the initialized-but-unset state of this global is $null.
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        $BaseUrl
    )

    $PreviousBaseUrl = $Global:OmadaWebPSCurrentBaseUrl
    $Global:OmadaWebPSCurrentBaseUrl = $BaseUrl
    return $PreviousBaseUrl
}
