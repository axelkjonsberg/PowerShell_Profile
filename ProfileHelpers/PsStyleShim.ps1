# Only create a shim on legacy Windows PowerShell
if ($PSVersionTable.PSVersion.Major -lt 7 -and -not (Get-Variable -Name PSStyle -Scope Global -ErrorAction SilentlyContinue)) {
    $AnsiGreen = 32
    $AnsiMagenta = 35
    $AnsiYellow = 33
    $AnsiCyan = 36
    $AnsiReset = 0

    # Basic check for ANSI support on Windows PowerShell terminals
    $supportsAnsi =
    ([Environment]::OSVersion.Version.Build -ge 10586) -or
    $env:WT_SESSION -or
    ($env:ConEmuANSI -eq 'ON')

    $esc = [char]27
    $mk = {
        param($code)
        if ($supportsAnsi) { "$esc[$code" + 'm' } else { '' }
    }

    $global:PSStyle = [pscustomobject]@{
        Foreground = [pscustomobject]@{
            Green = & $mk $AnsiGreen
            Magenta = & $mk $AnsiMagenta
            Yellow = & $mk $AnsiYellow
            Cyan = & $mk $AnsiCyan
        }
        Reset = & $mk $AnsiReset
    }
}
