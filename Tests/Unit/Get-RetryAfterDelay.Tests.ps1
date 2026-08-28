param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Get-RetryAfterDelay' -Tag 'Unit' {
    Context 'delay-seconds form' {
        It 'Should return the number of seconds the header asks for' {
            InModuleScope 'OmadaWeb.PS' {
                $Exception = [PSCustomObject]@{ Response = [PSCustomObject]@{ Headers = @{ 'Retry-After' = '120' } } }

                Get-RetryAfterDelay -Exception $Exception | Should -Be 120
            }
        }

        It 'Should match the header name case-insensitively' {
            InModuleScope 'OmadaWeb.PS' {
                $Exception = [PSCustomObject]@{ Response = [PSCustomObject]@{ Headers = @{ 'retry-after' = '7' } } }

                Get-RetryAfterDelay -Exception $Exception | Should -Be 7
            }
        }

        It 'Should read the first value when the header is multi-valued' {
            InModuleScope 'OmadaWeb.PS' {
                $Exception = [PSCustomObject]@{ Response = [PSCustomObject]@{ Headers = @{ 'Retry-After' = @('30', '60') } } }

                Get-RetryAfterDelay -Exception $Exception | Should -Be 30
            }
        }

        It 'Should cap the delay at MaximumDelaySec' {
            InModuleScope 'OmadaWeb.PS' {
                $Exception = [PSCustomObject]@{ Response = [PSCustomObject]@{ Headers = @{ 'Retry-After' = '99999' } } }

                Get-RetryAfterDelay -Exception $Exception -MaximumDelaySec 300 | Should -Be 300
            }
        }

        It 'Should cap a delay with more digits than a double can represent instead of throwing' {
            InModuleScope 'OmadaWeb.PS' {
                # Windows PowerShell 5.1 throws when casting a 320-digit string to [double]. This
                # runs inside the retry path's catch block, so throwing here would turn the
                # transient failure being handled into a hard one.
                $Exception = [PSCustomObject]@{ Response = [PSCustomObject]@{ Headers = @{ 'Retry-After' = ('9' * 320) } } }

                Get-RetryAfterDelay -Exception $Exception -MaximumDelaySec 300 | Should -Be 300
            }
        }

        It 'Should reject a negative MaximumDelaySec' {
            InModuleScope 'OmadaWeb.PS' {
                # A negative cap would make the returned delay negative, which reads as "retry now".
                $Exception = [PSCustomObject]@{ Response = [PSCustomObject]@{ Headers = @{ 'Retry-After' = '120' } } }

                { Get-RetryAfterDelay -Exception $Exception -MaximumDelaySec -1 } | Should -Throw
            }
        }

        It 'Should not be affected by a culture that uses a decimal comma' {
            InModuleScope 'OmadaWeb.PS' {
                $OriginalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
                try {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('nl-NL')
                    $Exception = [PSCustomObject]@{ Response = [PSCustomObject]@{ Headers = @{ 'Retry-After' = '45' } } }

                    Get-RetryAfterDelay -Exception $Exception | Should -Be 45
                }
                finally {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = $OriginalCulture
                }
            }
        }
    }

    Context 'HTTP-date form' {
        It 'Should return the seconds remaining until an RFC 1123 date in the future' {
            InModuleScope 'OmadaWeb.PS' {
                $Future = [datetime]::UtcNow.AddSeconds(90).ToString('r')
                $Exception = [PSCustomObject]@{ Response = [PSCustomObject]@{ Headers = @{ 'Retry-After' = $Future } } }

                $Delay = Get-RetryAfterDelay -Exception $Exception

                # The header has one-second resolution, so the remaining time lands just under 90s.
                $Delay | Should -BeGreaterThan 85
                $Delay | Should -BeLessOrEqual 90
            }
        }

        It 'Should return zero for a date that has already passed' {
            InModuleScope 'OmadaWeb.PS' {
                $Past = [datetime]::UtcNow.AddMinutes(-5).ToString('r')
                $Exception = [PSCustomObject]@{ Response = [PSCustomObject]@{ Headers = @{ 'Retry-After' = $Past } } }

                Get-RetryAfterDelay -Exception $Exception | Should -Be 0
            }
        }
    }

    Context 'No usable header' {
        It 'Should return null when the header is absent' {
            InModuleScope 'OmadaWeb.PS' {
                $Exception = [PSCustomObject]@{ Response = [PSCustomObject]@{ Headers = @{ 'Content-Type' = 'application/json' } } }

                Get-RetryAfterDelay -Exception $Exception | Should -BeNullOrEmpty
            }
        }

        It 'Should return null when the header value is not parseable' {
            InModuleScope 'OmadaWeb.PS' {
                $Exception = [PSCustomObject]@{ Response = [PSCustomObject]@{ Headers = @{ 'Retry-After' = 'soon' } } }

                Get-RetryAfterDelay -Exception $Exception | Should -BeNullOrEmpty
            }
        }

        It 'Should return null when the header value is whitespace' {
            InModuleScope 'OmadaWeb.PS' {
                $Exception = [PSCustomObject]@{ Response = [PSCustomObject]@{ Headers = @{ 'Retry-After' = '   ' } } }

                Get-RetryAfterDelay -Exception $Exception | Should -BeNullOrEmpty
            }
        }

        It 'Should return null when the exception carries no response' {
            InModuleScope 'OmadaWeb.PS' {
                Get-RetryAfterDelay -Exception ([PSCustomObject]@{ Message = 'socket closed' }) | Should -BeNullOrEmpty
            }
        }

        It 'Should return null when the response carries no headers' {
            InModuleScope 'OmadaWeb.PS' {
                $Exception = [PSCustomObject]@{ Response = [PSCustomObject]@{ StatusCode = 503 } }

                Get-RetryAfterDelay -Exception $Exception | Should -BeNullOrEmpty
            }
        }

        It 'Should return null for a null exception' {
            InModuleScope 'OmadaWeb.PS' {
                Get-RetryAfterDelay -Exception $null | Should -BeNullOrEmpty
            }
        }
    }

    Context 'WebHeaderCollection (Windows PowerShell 5.1 shape)' {
        It 'Should read the header from a WebHeaderCollection' {
            InModuleScope 'OmadaWeb.PS' {
                $Headers = [System.Net.WebHeaderCollection]::new()
                $Headers.Add('Retry-After', '15')
                $Exception = [PSCustomObject]@{ Response = [PSCustomObject]@{ Headers = $Headers } }

                Get-RetryAfterDelay -Exception $Exception | Should -Be 15
            }
        }
    }
}

AfterAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
