<#
    Classification of the module's exported commands, shared by Build/Update-ReadmeHelp.ps1 and
    Build/Test-CommentBasedHelp.ps1.

    WrappedCommands maps each exported function to the built-in cmdlet it wraps, or to an empty
    string when it is a command in its own right. Both scripts fail when an exported function is
    missing from this map, so adding a public function is a deliberate step rather than something
    that silently drops out of the generated README and the help check.

    Why it matters for the two scripts:
      - A wrapper's parameters are all added at runtime by DynamicParam/Set-DynamicParameter.ps1,
        so its parameter help lives in the -HelpMessage strings there rather than in
        comment-based .PARAMETER entries, and its README syntax ends in a
        "[<Invoke-RestMethod Parameters>]" placeholder instead of listing the inherited parameters.
      - A standalone command declares its parameters normally, so its help comes from its
        comment-based help and its full syntax is generated.
#>
@{
    WrappedCommands = @{
        "Invoke-OmadaRestMethod" = "Invoke-RestMethod"
        "Invoke-OmadaWebRequest" = "Invoke-WebRequest"
        "Clear-OmadaWebCache"    = ""
    }
}
