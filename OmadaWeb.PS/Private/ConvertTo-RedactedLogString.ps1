function ConvertTo-RedactedLogString {
    <#
    .SYNOPSIS
        Serializes an object to JSON for the verbose stream with all secret material removed.

    .DESCRIPTION
        The single path by which request parameters, sessions, cookies and configuration objects are
        allowed to reach the verbose stream. Sensitive properties are masked by name, credentials and
        secure strings by type, and bulk data is reduced to a shape summary.

        This matters beyond -Verbose on a console: consumers of this module capture the verbose
        stream into their own logs. OmadaSqlTroubleshooter, for instance, has an "Export Log File"
        button, so anything written here can end up in a file a user attaches to a support ticket.

        NOTE: none of the functions in this file may log anything themselves - every logging call
        site in the module routes through this one, so writing to the verbose stream from here would
        recurse.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        $InputObject,
        [int]$MaxDepth = 6,
        [int]$MaxStringLength = 512,
        # Keep keys and value shapes but no values at all. Used where the object being logged IS a
        # request body, rather than a parameter set containing one.
        [switch]$ShapeOnly
    )

    try {
        $Redacted = ConvertTo-RedactedLogValue -Value $InputObject -Depth 0 -MaxDepth $MaxDepth -MaxStringLength $MaxStringLength -Visited ([System.Collections.Generic.List[object]]::new()) -MaskValues ([bool]$ShapeOnly)
        if ($null -eq $Redacted) {
            return "null"
        }

        return ($Redacted | ConvertTo-Json -Depth 20 -WarningAction SilentlyContinue)
    }
    catch {
        # Failing open would leak the very thing this function exists to hide - and that includes the
        # exception message, which for a failure mid-walk can quote the value being walked. The
        # exception type is enough to debug this from and carries nothing.
        return "<redaction failed: {0}>" -f $_.Exception.GetType().Name
    }
}

function ConvertTo-RedactedLogValue {
    <#
    .SYNOPSIS
        Recursive walker behind ConvertTo-RedactedLogString. Returns a redacted clone, not a string.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value,
        [int]$Depth,
        [int]$MaxDepth,
        [int]$MaxStringLength,
        [System.Collections.Generic.List[object]]$Visited,
        [bool]$MaskValues
    )

    # Read from module scope rather than rebuilt here: this function recurses once per property of
    # every object logged, and the string it feeds is built on every request whether or not -Verbose
    # is on, so a per-call array allocation is not free. The pattern list and its name/value variant
    # are defined in OmadaWeb.PS.psm1 alongside the module's other script state.
    $RedactedToken = $Script:RedactedLogToken
    $SensitiveNamePatterns = $Script:SensitiveLogNamePatterns

    if ($null -eq $Value) {
        return $null
    }

    # Type rules first - these hold regardless of the property name the value arrived under.
    if ($Value -is [System.Security.SecureString]) {
        return $RedactedToken
    }

    if ($Value -is [System.Management.Automation.PSCredential]) {
        # The user name is diagnostic and not secret; the password never leaves the SecureString.
        return "PSCredential(UserName={0})" -f $Value.UserName
    }

    if ($Value -is [System.Net.NetworkCredential]) {
        return "NetworkCredential(UserName={0})" -f $Value.UserName
    }

    if ($Value -is [byte[]]) {
        return "Byte[{0}]" -f $Value.Length
    }

    if ($Value -is [System.Net.CookieContainer]) {
        return "CookieContainer(Count={0})" -f $Value.Count
    }

    if ($Value -is [System.Net.CookieCollection]) {
        return "CookieCollection(Count={0})" -f $Value.Count
    }

    if ($Value -is [System.Net.Cookie]) {
        # A cookie's value IS the session secret. Its name and domain are what you need to see.
        return "Cookie(Name={0}, Domain={1})" -f $Value.Name, $Value.Domain
    }

    if ($Value -is [Microsoft.PowerShell.Commands.WebRequestSession]) {
        # The WebSession bound parameter carries the authentication cookie, and the member name "WebSession"
        # matches none of the patterns above - so this needs a type rule rather than a name rule.
        # The cookie count and user agent are the diagnostic parts; nothing else here is.
        return "WebRequestSession(Cookies={0}, UserAgent={1})" -f $Value.Cookies.Count, $Value.UserAgent
    }

    if ($Value -is [string]) {
        if ($MaskValues) {
            return "String({0})" -f $Value.Length
        }

        # The name rules above only fire on members whose name gives the secret away. A token that
        # arrives under a name nobody anticipated is still a token, so every string value that is
        # about to be logged also passes the regex net.
        $Value = Protect-LogMessage -Message $Value

        if ($Value.Length -gt $MaxStringLength) {
            return "{0}...(truncated, {1} chars)" -f $Value.Substring(0, $MaxStringLength), $Value.Length
        }

        return $Value
    }

    if ($Value -is [uri]) {
        if ($MaskValues) {
            return $Value.GetType().Name
        }

        # Serialized as its string form rather than walked: a Uri's property graph is large and
        # uninteresting in a log, and an OAuth2/login redirect can carry a token in its query
        # string - which the regex net masks, but only on text.
        return (Protect-LogMessage -Message $Value.AbsoluteUri)
    }

    if ($Value -is [ValueType] -or $Value -is [System.Management.Automation.SwitchParameter]) {
        if ($MaskValues) {
            return $Value.GetType().Name
        }

        return $Value
    }

    if ($Depth -ge $MaxDepth) {
        return "<max depth {0} reached: {1}>" -f $MaxDepth, $Value.GetType().Name
    }

    # Live session and response objects are cyclic - without this the walker never returns.
    foreach ($Seen in $Visited) {
        if ([object]::ReferenceEquals($Seen, $Value)) {
            return "<circular reference: {0}>" -f $Value.GetType().Name
        }
    }
    $Visited.Add($Value)

    if ($Value -is [System.Collections.IDictionary]) {
        # See the note further down on name/value pairs - a cookie or header can arrive as a
        # hashtable just as easily as an object, and the same reasoning applies.
        $Keys = @($Value.Keys)
        $KeyNames = @($Keys | ForEach-Object { [string]$_ })
        $DictionaryPatterns = $SensitiveNamePatterns
        # -contains is case-insensitive for strings, so this catches name/value as well as Name/Value.
        if ($KeyNames -contains "name" -and $KeyNames -contains "value") {
            $DictionaryPatterns = $Script:SensitiveLogNamePatternsWithValue
        }

        $Result = [ordered]@{}
        foreach ($Key in $Keys) {
            $Result[[string]$Key] = Get-RedactedMemberValue -Name ([string]$Key) -MemberValue $Value[$Key] -Depth $Depth -MaxDepth $MaxDepth -MaxStringLength $MaxStringLength -Visited $Visited -MaskValues $MaskValues -SensitiveNamePatterns $DictionaryPatterns -RedactedToken $RedactedToken
        }

        return $Result
    }

    if ($Value -isnot [string] -and $Value -is [System.Collections.IEnumerable]) {
        $Items = @($Value)
        $ItemCount = ($Items | Measure-Object).Count
        if ($ItemCount -gt 3) {
            # Bulk data - response collections, cookie lists. Log the shape, never the contents.
            $ElementType = "Object"
            if ($null -ne $Items[0]) {
                $ElementType = $Items[0].GetType().Name
            }

            return "Array[{0}] of {1}" -f $ItemCount, $ElementType
        }

        $Result = @()
        foreach ($Item in $Items) {
            $Result += , (ConvertTo-RedactedLogValue -Value $Item -Depth ($Depth + 1) -MaxDepth $MaxDepth -MaxStringLength $MaxStringLength -Visited $Visited -MaskValues $MaskValues)
        }

        return $Result
    }

    # An object exposing both a Name and a Value member is a name/value pair, and in this module that
    # is almost always a cookie or a header: $SessionContext.AuthCookie is a PSCustomObject with
    # lowercase name/value/domain members (see Get-WebView2Cookie), so no type rule reaches it and
    # "value" names nothing secret on its own. Within such an object, though, the value is the secret -
    # so mask it there and nowhere else. The rest of the members (domain, path, expiry, httpOnly) are
    # the diagnostics worth keeping.
    $MemberSensitiveNamePatterns = $SensitiveNamePatterns
    if ($null -ne $Value.PSObject.Properties['Name'] -and $null -ne $Value.PSObject.Properties['Value']) {
        $MemberSensitiveNamePatterns = $Script:SensitiveLogNamePatternsWithValue
    }

    # Anything else: walk its properties, tolerating members that throw when read.
    $Result = [ordered]@{}
    try {
        foreach ($Property in $Value.PSObject.Properties) {
            try {
                $Result[$Property.Name] = Get-RedactedMemberValue -Name $Property.Name -MemberValue $Property.Value -Depth $Depth -MaxDepth $MaxDepth -MaxStringLength $MaxStringLength -Visited $Visited -MaskValues $MaskValues -SensitiveNamePatterns $MemberSensitiveNamePatterns -RedactedToken $RedactedToken
            }
            catch {
                $Result[$Property.Name] = "<unreadable>"
            }
        }
    }
    catch {
        return "<{0}>" -f $Value.GetType().Name
    }

    if ($Result.Count -le 0) {
        return $Value.ToString()
    }

    return $Result
}

function Get-RedactedMemberValue {
    <#
    .SYNOPSIS
        Applies the name-based rules for a single member, then hands off to the recursive walker.
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [AllowNull()]
        $MemberValue,
        [int]$Depth,
        [int]$MaxDepth,
        [int]$MaxStringLength,
        [System.Collections.Generic.List[object]]$Visited,
        [bool]$MaskValues,
        [string[]]$SensitiveNamePatterns,
        [string]$RedactedToken
    )

    # Credential objects are handled by the type rules in the walker, which keep the user name -
    # knowing which account authenticated is the first thing you need for a 401 - while the password
    # stays in its SecureString. Applying the name rule here instead would throw that away for no gain.
    $HandledByTypeRule = $MemberValue -is [System.Management.Automation.PSCredential] -or $MemberValue -is [System.Net.NetworkCredential] -or $MemberValue -is [System.Security.SecureString]

    if (-not $HandledByTypeRule) {
        foreach ($Pattern in $SensitiveNamePatterns) {
            if ($Name -like "*$Pattern*") {
                return $RedactedToken
            }
        }
    }

    # Request bodies keep their keys and value shapes - enough to tell what was sent - but no values.
    $ChildMaskValues = $MaskValues
    if ($Name -eq "Body") {
        $ChildMaskValues = $true
    }

    return ConvertTo-RedactedLogValue -Value $MemberValue -Depth ($Depth + 1) -MaxDepth $MaxDepth -MaxStringLength $MaxStringLength -Visited $Visited -MaskValues $ChildMaskValues
}
