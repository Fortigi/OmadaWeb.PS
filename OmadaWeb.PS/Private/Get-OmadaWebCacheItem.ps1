function Get-OmadaWebCacheItem {
    [CmdletBinding()]
    param(
        [ValidateSet("All", "Cookies", "BrowserProfiles", "Binaries", "Sessions")]
        [string[]]$Scope = "All"
    )

    # Single inventory of everything the module stores, shared by Clear-OmadaWebCache (which removes
    # the items) and by anything else that needs to report the data footprint. Keep this in step with
    # the "Local data footprint" table in README.md.
    $SelectedScopes = if ($Scope -contains "All") {
        @("Cookies", "BrowserProfiles", "Binaries", "Sessions")
    }
    else {
        @($Scope | Select-Object -Unique)
    }

    $Items = [System.Collections.Generic.List[object]]::new()

    if ($SelectedScopes -contains "Cookies") {
        $Items.Add((New-OmadaWebCacheItem -Scope "Cookies" -Artefact "Encrypted cookie cache" -Path $Script:CookieCachePath -ItemType "Directory" -Protection "Encrypted with DPAPI for the current user and machine"))

        foreach ($LegacyFile in (Get-OmadaLegacyCookieCacheFile)) {
            $Items.Add((New-OmadaWebCacheItem -Scope "Cookies" -Artefact "Encrypted cookie cache (legacy %TEMP% location)" -Path $LegacyFile.FullName -ItemType "File" -Protection "Encrypted with DPAPI for the current user and machine"))
        }
    }

    if ($SelectedScopes -contains "BrowserProfiles") {
        $Items.Add((New-OmadaWebCacheItem -Scope "BrowserProfiles" -Artefact "WebView2 Edge user profiles" -Path $Script:WebView2UserProfileBasePath -ItemType "Directory" -Protection "NTFS permissions on the user profile only"))
        $Items.Add((New-OmadaWebCacheItem -Scope "BrowserProfiles" -Artefact "Selenium Edge user profiles" -Path $Script:SeleniumProfileBasePath -ItemType "Directory" -Protection "NTFS permissions on the user profile only"))
    }

    if ($SelectedScopes -contains "Binaries") {
        $Items.Add((New-OmadaWebCacheItem -Scope "Binaries" -Artefact "Downloaded runtime binaries" -Path (Join-Path $Script:ModuleAppDataPath -ChildPath "Bin") -ItemType "Directory" -Protection "NTFS permissions on the user profile only"))
    }

    if ($SelectedScopes -contains "Sessions") {
        $SessionCount = 0
        if ($null -ne $Script:OmadaSessions) {
            $SessionCount = $Script:OmadaSessions.Count
        }
        $Item = New-OmadaWebCacheItem -Scope "Sessions" -Artefact "In-memory authentication sessions" -Path "(current PowerShell session)" -ItemType "Memory" -Protection "Process memory only, never written to disk"
        $Item.Exists = $SessionCount -gt 0
        $Item.ItemCount = $SessionCount
        $Items.Add($Item)
    }

    return $Items.ToArray()
}
