$WeatherCacheFile = "$env:USERPROFILE\.weatherCache.json"
$IsPS7 = $PSVersionTable.PSVersion.Major -ge 7

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

    $headers = @{
        # "User-Agent" = Follow instructions under "Legal stuff" at https://api.met.no/doc/TermsOfService
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

            # Save to cache
            Save-WeatherDataToCache $global:WeatherTemperature $global:WeatherIcon
        }
        else {
            # We have internet but no forecast data
            $global:WeatherTemperature = "N/A"
            $global:WeatherIcon = if ($IsPS7) { $noDataIcon } else { "(No weather data)" }
            Save-WeatherDataToCache $global:WeatherTemperature $global:WeatherIcon
        }
    }
    catch {
        # In case of an error (e.g., no internet), set the no-connection icon
        $global:WeatherTemperature = "N/A"
        $global:WeatherIcon = if ($IsPS7) { $noConnectionIcon } else { "(No connection)" }

        # Do NOT save to cache here, so that "no connection" state isn't persisted
    }
}

Update-WeatherData

function Get-GitBranch {
    param(
        [string]$currentDirectory
    )

    $gitBranch = & git rev-parse --abbrev-ref HEAD 2>$null
    if ($gitBranch) {
        $repositoryPath = (& git rev-parse --show-toplevel 2>$null).Trim()
        $repositoryName = (Split-Path -Leaf -Path $repositoryPath).Trim()

        if ($repositoryName -ne $currentDirectory) {
            return "[$gitBranch ($repositoryName)]"
        } else {
            return "[$gitBranch]"
        }
    }
    return ""
}

function prompt {
    $promptSegments = @()

    # Existing shell version
    $shellVersion = "PS v$($PSVersionTable.PSVersion.ToString())"
    $promptSegments += @{
        Text = $shellVersion
        Color = "Green"
    }

    # Weather information
    $weatherInfo = ""
    if ($IsPS7 -and $global:WeatherIcon) {
        $weatherInfo = "($($global:WeatherTemperature)°C$([char]0x00A0)$($global:WeatherIcon)$([char]0x00A0))"
    } elseif ($global:WeatherTemperature) {
        $weatherInfo = "($($global:WeatherTemperature)°C)"
    }

    if ($weatherInfo -ne "") {
        $promptSegments += @{
            Text = $weatherInfo
            Color = "Magenta"
        }
    }

    # Current path
    $currentPath = (Get-Location).Path
    $relativePath = $currentPath.Replace($env:USERPROFILE,"")
    $pathInfo = "~$relativePath"
    $promptSegments += @{
        Text = $pathInfo
        Color = "Yellow"
    }

    # Git information
    $currentDirectory = Split-Path -Leaf -Path (Get-Location)
    $gitInfo = Get-GitBranch -currentDirectory $currentDirectory
    if ($gitInfo -ne "") {
        $promptSegments += @{
            Text = $gitInfo
            Color = "Cyan"
        }
    }

    # Build and display the prompt with proper spacing
    $firstSegment = $true
    foreach ($segment in $promptSegments) {
        if ($firstSegment) {
            $firstSegment = $false
        } else {
            Write-Host -NoNewline " "
        }
        Write-Host -NoNewline -ForegroundColor $segment.Color $segment.Text
    }

    # Return a newline character to move the prompt to the next line
    return "`n"
}
