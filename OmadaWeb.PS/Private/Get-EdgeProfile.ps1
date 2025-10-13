function Get-EdgeProfile {
    [CmdletBinding()]
    param()

    "{0} - Getting Edge profiles" -f $MyInvocation.MyCommand | Write-Verbose
    $UserDataDir = Join-Path $Env:LOCALAPPDATA -ChildPath "Microsoft\Edge\User Data"

    if (Test-Path $UserDataDir -PathType Container) {

        $Profiles = Get-ChildItem -Directory -Path $UserDataDir | Where-Object {
            $_.Name -match "^Default$|^Profile \d+$"
        }

        $ProfileInfo = foreach ($Profile in $Profiles) {
            $PreferencesFile = Join-Path -Path $Profile.FullName -ChildPath "Preferences"
            if (Test-Path $PreferencesFile) {

                $Preferences = Get-Content -Path $PreferencesFile -Raw | ConvertFrom-Json
                [PSCustomObject]@{
                    Folder = $Profile.Name
                    Name   = $Preferences.profile.name
                }
            }
            else {
                [PSCustomObject]@{
                    Folder = $Profile.Name
                    Name   = "Default"
                }
            }
        }

        return $ProfileInfo
    }
    else {
        "Edge user data directory not found at '{0}'. Trying to use the default profile!" -f $UserDataDir | Write-Warning
    }
}