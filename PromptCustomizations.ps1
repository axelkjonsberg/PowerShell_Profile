$WeatherCacheFile = "$env:USERPROFILE\.weatherCache.json"
$AirQualityCacheFile = "$env:USERPROFILE\.airQualityCache.json"
$ConfigFile = "$env:USERPROFILE\.weatherConfig.json"
$IsPS7 = $PSVersionTable.PSVersion.Major -ge 7

function Get-WeatherConfig {
    if (Test-Path $ConfigFile) {
        return Get-Content $ConfigFile | ConvertFrom-Json
    }
}

$config = Get-WeatherConfig
$UserAgent = $config.UserAgent

function Get-CachedWeatherData {
    if (Test-Path $WeatherCacheFile) {
        $data = Get-Content $WeatherCacheFile | ConvertFrom-Json
        $lastUpdated = [datetime]$data.LastUpdated
        if ((Get-Date) -lt $lastUpdated.AddHours(1)) {
            return $data
        }
    }
    return $null
}

function Save-WeatherDataToCache ($temperature,$icon) {
    $weatherData = @{
        LastUpdated = (Get-Date).ToString("o")
        Temperature = $temperature
        Icon = $icon
    }
    $weatherData | ConvertTo-Json | Out-File $WeatherCacheFile
}

function Update-WeatherData {
    $data = Get-CachedWeatherData
    if ($data) {
        $global:WeatherTemperature = $data.Temperature
        $global:WeatherIcon = $data.Icon
        return
    }

    Write-Host $UserAgent

    $headers = @{
        "User-Agent" = $UserAgent
    }
    $lat = 59.91278
    $lon = 10.73639
    $apiUrl = "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=$lat&lon=$lon"

    $weatherIcons = @{
        "clearsky" = "☀️"
        "cloudy" = "☁️"
        "fair" = "🌤️"
        "fog" = "🌫️"
        "heavyrain" = "🌧️"
        "heavyrainandthunder" = "⛈️"
        "heavyrainshowers" = "🌧️"
        "heavyrainshowersandthunder" = "⛈️"
        "heavysleet" = "🌨️"
        "heavysleetandthunder" = "⛈️"
        "heavysleetshowers" = "🌨️"
        "heavysleetshowersandthunder" = "⛈️"
        "heavysnow" = "❄️"
        "heavysnowandthunder" = "⛈️"
        "heavysnowshowers" = "❄️"
        "heavysnowshowersandthunder" = "⛈️"
        "lightrain" = "🌦️"
        "lightrainandthunder" = "⛈️"
        "lightrainshowers" = "🌦️"
        "lightrainshowersandthunder" = "⛈️"
        "lightsleet" = "🌨️"
        "lightsleetandthunder" = "⛈️"
        "lightsleetshowers" = "🌨️"
        "lightsnow" = "🌨️"
        "lightsnowandthunder" = "⛈️"
        "lightsnowshowers" = "🌨️"
        "partlycloudy" = "⛅"
        "rain" = "🌧️"
        "rainandthunder" = "⛈️"
        "rainshowers" = "🌧️"
        "rainshowersandthunder" = "⛈️"
        "sleet" = "🌨️"
        "sleetandthunder" = "⛈️"
        "sleetshowers" = "🌨️"
        "sleetshowersandthunder" = "⛈️"
        "snow" = "🌨️"
        "snowandthunder" = "⛈️"
        "snowshowers" = "🌨️"
        "snowshowersandthunder" = "⛈️"
        "thunderstorm" = "🌩️"
    }

    $noConnectionIcon = "🚫🛜"
    $noDataIcon = "❓"

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 5
        $timeseries = $response.properties.timeseries

        $forecast = $timeseries | Where-Object {
            [datetime]$_.time -ge (Get-Date).AddHours(1)
        } | Select-Object -First 1

        if ($forecast) {
            $global:WeatherTemperature = $forecast.data.instant.details.air_temperature
            $symbolCode = $forecast.data.next_1_hours.summary.symbol_code
            $symbolKey = $symbolCode -replace '_day$|_night$',''
            $global:WeatherIcon = if ($IsPS7) { $weatherIcons[$symbolKey] } else { "" }

            Save-WeatherDataToCache $global:WeatherTemperature $global:WeatherIcon
        }
        else {
            # Internet is available but no forecast data was returned
            $global:WeatherTemperature = "N/A"
            $global:WeatherIcon = if ($IsPS7) { $noDataIcon } else { "(No weather data)" }
            Save-WeatherDataToCache $global:WeatherTemperature $global:WeatherIcon
        }
    }
    catch {
        # On error (e.g. no internet), set the no-connection icon
        $global:WeatherTemperature = "N/A"
        $global:WeatherIcon = if ($IsPS7) { $noConnectionIcon } else { "(No connection)" }
        # Do not cache in this case so that the "no connection" state is not persisted.
    }
}

Update-WeatherData

function Get-GitBranch {
    param(
        [string]$currentDirectory
    )

    $gitBranch = & git rev-parse --abbrev-ref HEAD 2>$null
    if (-not $gitBranch) {
        return ""
    }

    $repositoryPath = (& git rev-parse --show-toplevel 2>$null).Trim()
    $repositoryName = (Split-Path -Leaf -Path $repositoryPath).Trim()

    $hasUpstream = (& git rev-parse --abbrev-ref '@{u}' 2>$null)
    if (-not $hasUpstream) {
        if ($repositoryName -ne $currentDirectory) {
            return "[${repositoryName}:${gitBranch}]"
        }
        else {
            return "[${gitBranch}]"
        }
    }

    $aheadCount = (& git rev-list --count '@{u}..@' 2>$null)
    $behindCount = (& git rev-list --count '@..@{u}' 2>$null)

    $statusIndicator = ""
    $showNumbers = ($aheadCount -gt 1 -or $behindCount -gt 1)

    if ($behindCount -gt 0) {
        if ($showNumbers) {
            $statusIndicator += "$behindCount↓"
        }
        else {
            $statusIndicator += "↓"
        }
    }

    if ($aheadCount -gt 0) {
        if ($showNumbers) {
            $statusIndicator += "$aheadCount↑"
        }
        else {
            $statusIndicator += "↑"
        }
    }

    if ($statusIndicator) {
        $statusIndicator = "($statusIndicator)"
    }

    if ($repositoryName -ne $currentDirectory) {
        return "[${repositoryName}:${gitBranch}${statusIndicator}]"
    }
    else {
        return "[${gitBranch}${statusIndicator}]"
    }
}


function prompt {
    $promptSegments = @()

    # Shell version segment.
    $shellVersion = "PS v$($PSVersionTable.PSVersion.ToString())"
    $promptSegments += @{
        Text = $shellVersion
        Color = "Green"
    }

    # Define an adjusted space (a narrow non-breaking space).
    $adjustedSpace = "$([char]0x202F)"

    # Build the weather segment.
    if ($global:WeatherTemperature -and $global:WeatherTemperature -ne "N/A") {
        $weatherInfo = "$global:WeatherTemperature°C$adjustedSpace$global:WeatherIcon"
    }
    else {
        $weatherInfo = "N/A"
    }

    $promptSegments += @{
        Text = $weatherInfo
        Color = "Magenta"
    }

    # Current path segment.
    $currentPath = (Get-Location).Path
    $relativePath = $currentPath.Replace($env:USERPROFILE,"")
    $pathInfo = "~$relativePath"
    $promptSegments += @{
        Text = $pathInfo
        Color = "Yellow"
    }

    # Git branch segment.
    $currentDirectory = Split-Path -Leaf -Path (Get-Location)
    $gitInfo = Get-GitBranch -currentDirectory $currentDirectory
    if ($gitInfo -ne "") {
        $promptSegments += @{
            Text = $gitInfo
            Color = "Cyan"
        }
    }

    $firstSegment = $true
    foreach ($segment in $promptSegments) {
        if (-not $firstSegment) {
            Write-Host -NoNewline " "
        }
        else {
            $firstSegment = $false
        }
        Write-Host -NoNewline -ForegroundColor $segment.Color $segment.Text
    }

    # Return a newline character for the prompt.
    return "`n"
}
