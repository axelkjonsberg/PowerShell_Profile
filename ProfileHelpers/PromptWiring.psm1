Set-Variable -Name NarrowNoBreakSpace -Option Constant -Scope Script -Value ([char]0x202F)


function Get-CustomPromptString {
    if ($PSStyle -and $PSStyle.OutputRendering -eq 'PlainText') { $PSStyle.OutputRendering = 'Ansi' }
    $fg = $PSStyle.Foreground
    $reset = $PSStyle.Reset


    # Version
    $segmentVersion = "${($fg.Green)}PS v$($PSVersionTable.PSVersion)$reset"


    # Weather (show cached/last value)
    $rawTemp = $global:WeatherTemperature
    $tempText = if ($null -ne $rawTemp -and $rawTemp -ne 'N/A') {
        if ($rawTemp -is [double] -or $rawTemp -is [decimal]) {
            [string]::Format([System.Globalization.CultureInfo]::CurrentCulture,'{0:0.#}',$rawTemp)
        }
        else {
            [string]$rawTemp
        }
    }
    else { $null }

    $displayWeather = if ($tempText) {
        "$tempText°C$script:NarrowNoBreakSpace$($global:WeatherIcon)"
    }
    else {
        'N/A'
    }
    $segmentWeather = "${($fg.Magenta)}$displayWeather$reset"


    # Path (tilde-home)
    $currentPath = (Get-Location).Path
    $prettyPath = if ($currentPath.StartsWith($HOME,[StringComparison]::OrdinalIgnoreCase)) {
        '~' + $currentPath.Substring($HOME.Length)
    }
    else { $currentPath }
    $segmentPath = "${($fg.Yellow)}$prettyPath$reset"


    # Git (repo:branch [+ divergence])
    $leafName = Split-Path -Leaf -Path (Get-Location)
    $gitSegmentText = ''
    try { $gitSegmentText = Get-GitPromptSegment -CurrentDirectoryLeaf $leafName } catch { $gitSegmentText = '' }
    $segmentGit = if ($gitSegmentText) { "${($fg.Cyan)}$gitSegmentText$reset" } else { $null }


    $segments = @($segmentVersion,$segmentWeather,$segmentPath,$segmentGit) | Where-Object { $_ }
    return ($segments -join ' ') + ' > ' + [Environment]::NewLine
}


function Set-CustomPrompt {
    function Global:prompt {
        Request-WeatherForPrompt
        if (Get-Command Invoke-ContextModuleLoader -ErrorAction Ignore) { try { Invoke-ContextModuleLoader } catch {} }
        Get-CustomPromptString
    }
}


Export-ModuleMember -Function Get-CustomPromptString,Set-CustomPrompt
