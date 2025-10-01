Set-Variable -Name NarrowNoBreakSpace -Option Constant -Scope Script -Value ([char]0x202F)

function Get-PromptColorStyles {
    $psStyleValue = $global:PSStyle
    if (-not $psStyleValue) {
        return [pscustomobject]@{ Version = ''; Weather = ''; Path = ''; Git = ''; Reset = '' }
    }

    $foreground = $psStyleValue.Foreground
    $hasFromRgb = ($foreground.PSObject.Properties.Name -contains 'FromRgb')

    # Prefer RGB on PowerShell 7+, fall back to shim’s named colors on Windows PowerShell
    $styleVersion = if ($hasFromRgb) { $foreground.FromRgb(0x6CBF7C) } else { $foreground.Green }
    $styleWeather = if ($hasFromRgb) { $foreground.FromRgb(0xC678DD) } else { $foreground.Magenta }
    $stylePath = if ($hasFromRgb) { $foreground.FromRgb(0xE5C07B) } else { $foreground.Yellow }
    $styleGit = if ($hasFromRgb) { $foreground.FromRgb(0x56B6C2) } else { $foreground.Cyan }

    [pscustomobject]@{
        Version = $styleVersion
        Weather = $styleWeather
        Path    = $stylePath
        Git     = $styleGit
        Reset   = $psStyleValue.Reset
    }
}

function Get-CustomPromptString {
    $colorStyles = Get-PromptColorStyles

    # Version
    $segmentVersion = "$($colorStyles.Version)PS v$($PSVersionTable.PSVersion)$($colorStyles.Reset)"

    # Weather (cached/last value)
    $rawWeatherTemperature = $global:WeatherTemperature
    $weatherTemperatureText = if ($null -ne $rawWeatherTemperature -and $rawWeatherTemperature -ne 'N/A') {
        if ($rawWeatherTemperature -is [double] -or $rawWeatherTemperature -is [decimal]) {
            [string]::Format([System.Globalization.CultureInfo]::CurrentCulture, '{0:0.#}', $rawWeatherTemperature)
        }
        else { [string]$rawWeatherTemperature }
    }
    else { $null }

    $displayWeather = if ($weatherTemperatureText) {
        "$weatherTemperatureText°C$($global:WeatherTrendArrow)$script:NarrowNoBreakSpace$($global:WeatherIcon)"
    }
    else { 'N/A' }
    $segmentWeather = "$($colorStyles.Weather)$displayWeather$($colorStyles.Reset)"

    # Path (tilde-home)
    $currentPath = (Get-Location).Path
    $prettyPath = if ($currentPath.StartsWith($HOME, [StringComparison]::OrdinalIgnoreCase)) {
        '~' + $currentPath.Substring($HOME.Length)
    }
    else { $currentPath }
    $segmentPath = "$($colorStyles.Path)$prettyPath$($colorStyles.Reset)"

    # Git (repo:branch [+ divergence])
    $currentDirectoryLeaf = Split-Path -Leaf -Path (Get-Location)
    $gitSegmentText = ''
    try { $gitSegmentText = Get-GitPromptSegment -CurrentDirectoryLeaf $currentDirectoryLeaf } catch { $gitSegmentText = '' }
    $segmentGit = if ($gitSegmentText) { "$($colorStyles.Git)$gitSegmentText$($colorStyles.Reset)" } else { $null }

    $segments = @($segmentVersion, $segmentWeather, $segmentPath, $segmentGit) | Where-Object { $_ }
    return ($segments -join ' ') + ' > ' + [Environment]::NewLine
}


function Set-CustomPrompt {
    function Global:prompt {
        Request-WeatherForPrompt
        if (Get-Command Invoke-ContextModuleLoader -ErrorAction Ignore) { try { Invoke-ContextModuleLoader } catch {} }
        Get-CustomPromptString
    }
}


Export-ModuleMember -Function Get-CustomPromptString, Set-CustomPrompt
