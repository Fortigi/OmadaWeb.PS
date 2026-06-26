param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    function New-FakeRelease {
        param($Tag, $PreRelease = $false, $Draft = $false, $Assets = @(@{ name = "$Tag-asset.zip"; browser_download_url = "https://example.com/$Tag-asset.zip" }))
        [PSCustomObject]@{
            tag_name     = $Tag
            prerelease   = $PreRelease
            draft        = $Draft
            published_at = (Get-Date)
            assets       = $Assets
        }
    }
}

Describe 'Get-GitHubRelease' -Tag 'Unit' {
    BeforeEach {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-DownloadFile { 'C:\Temp\downloaded.zip' }
            Mock Expand-DownloadFile { 'C:\Temp\expanded' }
        }
    }

    It 'Should filter out prerelease and draft versions by default' {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ NewFakeRelease = ${function:New-FakeRelease} } {
            Mock Invoke-RestMethod {
                @(
                    (& $NewFakeRelease -Tag 'v1.0.0')
                    (& $NewFakeRelease -Tag 'v2.0.0-beta' -PreRelease $true)
                    (& $NewFakeRelease -Tag 'v3.0.0-draft' -Draft $true)
                )
            }

            Get-GitHubRelease -Org 'fortigi' -Repo 'sample' | Out-Null

            Should -Invoke Invoke-DownloadFile -ParameterFilter { $DownloadUrl -eq 'https://example.com/v1.0.0-asset.zip' }
        }
    }

    It 'Should select a release matching an exact TagFilter' {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ NewFakeRelease = ${function:New-FakeRelease} } {
            Mock Invoke-RestMethod {
                @(
                    (& $NewFakeRelease -Tag 'v1.0.0')
                    (& $NewFakeRelease -Tag 'v1.1.0')
                )
            }

            Get-GitHubRelease -Org 'fortigi' -Repo 'sample' -TagFilter 'v1.0.0' | Out-Null

            Should -Invoke Invoke-DownloadFile -ParameterFilter { $DownloadUrl -eq 'https://example.com/v1.0.0-asset.zip' }
        }
    }

    It 'Should select a release matching a wildcard TagFilter' {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ NewFakeRelease = ${function:New-FakeRelease} } {
            Mock Invoke-RestMethod {
                @(
                    (& $NewFakeRelease -Tag 'v1.0.0')
                    (& $NewFakeRelease -Tag 'v2.0.0')
                )
            }

            Get-GitHubRelease -Org 'fortigi' -Repo 'sample' -TagFilter 'v2.*' | Out-Null

            Should -Invoke Invoke-DownloadFile -ParameterFilter { $DownloadUrl -eq 'https://example.com/v2.0.0-asset.zip' }
        }
    }

    It 'Should throw when no asset matches the AssetFilter' {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ NewFakeRelease = ${function:New-FakeRelease} } {
            Mock Invoke-RestMethod { @( (& $NewFakeRelease -Tag 'v1.0.0') ) }

            { Get-GitHubRelease -Org 'fortigi' -Repo 'sample' -AssetFilter 'no-match\.zip' -ErrorAction Stop } | Should -Throw
        }
    }

    It 'Should throw when multiple assets match the AssetFilter' {
        InModuleScope 'OmadaWeb.PS' -Parameters @{ NewFakeRelease = ${function:New-FakeRelease} } {
            $Assets = @(
                @{ name = 'win-x64.zip'; browser_download_url = 'https://example.com/win-x64.zip' }
                @{ name = 'win-x86.zip'; browser_download_url = 'https://example.com/win-x86.zip' }
            )
            Mock Invoke-RestMethod { @( (& $NewFakeRelease -Tag 'v1.0.0' -Assets $Assets) ) }

            { Get-GitHubRelease -Org 'fortigi' -Repo 'sample' -AssetFilter 'win.*\.zip' -ErrorAction Stop } | Should -Throw
        }
    }

    It 'Should throw a helpful error when the GitHub API call fails' {
        InModuleScope 'OmadaWeb.PS' {
            Mock Invoke-RestMethod { throw 'network error' }

            { Get-GitHubRelease -Org 'fortigi' -Repo 'sample' -ErrorAction Stop } | Should -Throw
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
