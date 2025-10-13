function Reset-Timer {

    if ($null -ne $Script:Timer -and $Script:Timer.Enabled) {
        $Script:Timer.Stop()
    }
    $Script:Timer = New-Object System.Windows.Forms.Timer
    $Script:Timer.Interval = 150
    [console]::WriteLine("`n")
    "{0} - Reset Timer" -f $MyInvocation.MyCommand | Write-Verbose
}