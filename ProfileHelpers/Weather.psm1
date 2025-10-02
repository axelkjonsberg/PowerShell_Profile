Set-Variable -Name DefaultLatitude -Option Constant -Scope Script -Value 59.91278
Set-Variable -Name DefaultLongitude -Option Constant -Scope Script -Value 10.73639
Set-Variable -Name DefaultCacheTtlMinutes -Option Constant -Scope Script -Value 60
Set-Variable -Name DefaultTrendSignificanceCelsius -Option Constant -Scope Script -Value 1.0
Set-Variable -Name WeatherCacheFilePath -Option Constant -Scope Script -Value (Join-Path $HOME '.weatherCache.json')
Set-Variable -Name WeatherLogFilePath -Option Constant -Scope Script -Value (Join-Path $HOME '.weather.log')
Set-Variable -Name WeatherConfigPath -Option Constant -Scope Script -Value (Join-Path $HOME '.weatherConfig.json')

$global:WeatherTemperature = $null
$global:WeatherIcon = $null
$global:WeatherTrendArrow = $null

# Module settings
$script:WriteDebugLogToFile = $false
$script:EchoDebugLogToHost = $false

function Write-WeatherLog {
    param([Parameter(Mandatory)] [string]$Message)
    if (-not $script:WriteDebugLogToFile) { return }
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = "$timestamp [WX] $Message"
    try { Add-Content -LiteralPath $script:WeatherLogFilePath -Value $line -Encoding UTF8 } catch {}
    if ($script:EchoDebugLogToHost) { Write-Host $line -ForegroundColor DarkGray }
}

function Get-WeatherConfiguration {
    $configPath = $script:WeatherConfigPath
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        Write-WeatherLog "Config file not found: $configPath"
        return $null
    }

    Write-WeatherLog "Loading config: $configPath"
    try {
        $rawText = Get-Content -LiteralPath $configPath -Raw
        if (Get-Command Test-Json -ErrorAction Ignore) {
            if (-not (Test-Json -Json $rawText)) { Write-WeatherLog "Invalid JSON in $configPath"; return $null }
        }
        $data = $rawText | ConvertFrom-Json

        $userAgent = ($data.UserAgent -as [string]).Trim()
        if ([string]::IsNullOrWhiteSpace($userAgent)) {
            Write-WeatherLog "Config has empty UserAgent. MET requires identification."
            return $null
        }

        $style = [System.Globalization.NumberStyles]::Float
        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        $lat = $null; $lon = $null
        if (-not [double]::TryParse([string]$data.Latitude, $style, $culture, [ref]$lat)) { $lat = $script:DefaultLatitude }
        if (-not [double]::TryParse([string]$data.Longitude, $style, $culture, [ref]$lon)) { $lon = $script:DefaultLongitude }


        $ttl = 0; [void][int]::TryParse([string]$data.CacheTtlMinutes, [ref]$ttl)
        if ($ttl -lt 1) { $ttl = $script:DefaultCacheTtlMinutes }

        $numberStyle = [System.Globalization.NumberStyles]::Float
        $cultureInfo = [System.Globalization.CultureInfo]::InvariantCulture
        $trendThresholdCelsius = $script:DefaultTrendSignificanceCelsius

        $parsedTrendThresholdCelsius = 0.0
        if ([double]::TryParse([string]$data.TrendSignificanceCelsius, $numberStyle, $cultureInfo, [ref]$parsedTrendThresholdCelsius)) {
            $trendThresholdCelsius = $parsedTrendThresholdCelsius
        }

        if ($trendThresholdCelsius -le 0) {
            $trendThresholdCelsius = $script:DefaultTrendSignificanceCelsius
        }


        Write-WeatherLog "Config OK; UA length=$($userAgent.Length) TTL=$ttl Lat=$lat Lon=$lon TrendSignificanceC=$trendThresholdCelsius"
        [pscustomobject]@{
            UserAgent                = $userAgent
            Latitude                 = $lat
            Longitude                = $lon
            CacheTtlMinutes          = $ttl
            TrendSignificanceCelsius = $trendThresholdCelsius
        }
    }
    catch {
        Write-WeatherLog "Config parse error: $($_.Exception.Message)"
        return $null
    }
}

function Read-WeatherCache {
    if (-not (Test-Path -LiteralPath $script:WeatherCacheFilePath -PathType Leaf)) {
        Write-WeatherLog "Cache not found: $($script:WeatherCacheFilePath)"
        return $null
    }
    try {
        $configuration = Get-WeatherConfiguration
        $cacheTtlMinutes = if ($configuration) { [int]$configuration.CacheTtlMinutes } else { $script:DefaultCacheTtlMinutes }

        $data = Get-Content -LiteralPath $script:WeatherCacheFilePath -Raw | ConvertFrom-Json

        if (-not $data.LastUpdated) { Write-WeatherLog "Cache missing LastUpdated."; return $null }

        # Force refresh if this is a pre-change cache without the new window tag
        if (-not $data.WindowMinutes -or ([int]$data.WindowMinutes -ne 90)) {
            Write-WeatherLog "Cache schema/window mismatch. Forcing refresh. WindowMinutes=$($data.WindowMinutes)"
            return $null
        }

        $freshUntil = ([datetime]$data.LastUpdated).AddMinutes($cacheTtlMinutes)
        $isFresh = (Get-Date) -lt $freshUntil

        Write-WeatherLog ("Cache found. Fresh={0} Temp={1} Icon={2} Trend='{3}' Window={4}m" -f $isFresh, $data.Temperature, $data.Icon, ($data.TrendArrow -as [string]), $data.WindowMinutes)
        if ($isFresh) { return $data }
    }
    catch {
        Write-WeatherLog "Cache read/parse error: $($_.Exception.Message)"
    }
    return $null
}

function Write-WeatherCache {
    param(
        [Parameter(Mandatory)] $Temperature,
        [Parameter(Mandatory)] $Icon,
        [int]$WindowMinutes = 0,
        [string]$IconKey,
        [string]$IconSourceTime,
        [string]$TrendArrow
    )

    $target = $script:WeatherCacheFilePath
    $dir = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $payload = @{
        LastUpdated    = (Get-Date).ToString('o')
        Temperature    = $Temperature
        Icon           = $Icon
        WindowMinutes  = $WindowMinutes
        IconKey        = $IconKey
        IconSourceTime = $IconSourceTime
        TrendArrow     = $TrendArrow
    }

    $json = $payload | ConvertTo-Json -Compress
    $tmp = Join-Path $dir ('.weatherCache.json.tmp.' + [guid]::NewGuid().ToString('N'))

    try {
        [System.IO.File]::WriteAllText($tmp, $json)

        if ([System.IO.File].GetMethod('Move', [Type[]]@([string], [string], [bool]))) {
            [System.IO.File]::Move($tmp, $target, $true)
        }
        else {
            if (Test-Path -LiteralPath $target) {
                $bk = "$target.bak"
                [System.IO.File]::Replace($tmp, $target, $bk)
                Remove-Item -LiteralPath $bk -Force -ErrorAction SilentlyContinue
            }
            else {
                [System.IO.File]::Move($tmp, $target)
            }
        }
        Write-WeatherLog "Cache updated atomically at $target"
        Write-WeatherLog ("Cache payload: Temp={0} IconKey={1} Trend='{2}' Window={3}m" -f $Temperature, $IconKey, ($TrendArrow -as [string]), $WindowMinutes)
    }
    catch {
        try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } } catch {}
        Write-WeatherLog "Cache write error: $($_.Exception.Message)"
    }
}

function Get-WeatherNow {
    param([Parameter(Mandatory)] $Config)

    $apiUrl = "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=$($Config.Latitude)&lon=$($Config.Longitude)"
    Write-WeatherLog "Sync fetch: $apiUrl"

    $icons = @{
        "clearsky" = "☀️"; "cloudy" = "☁️"; "fair" = "🌤️"; "fog" = "🌫️"; "heavyrain" = "🌧️"; "heavyrainandthunder" = "⛈️";
        "heavyrainshowers" = "🌧️"; "heavyrainshowersandthunder" = "⛈️"; "heavysleet" = "🌨️"; "heavysleetandthunder" = "⛈️";
        "heavysleetshowers" = "🌨️"; "heavysleetshowersandthunder" = "⛈️"; "heavysnow" = "❄️"; "heavysnowandthunder" = "⛈️";
        "heavysnowshowers" = "❄️"; "heavysnowshowersandthunder" = "⛈️"; "lightrain" = "🌦️"; "lightrainandthunder" = "⛈️";
        "lightrainshowers" = "🌦️"; "lightrainshowersandthunder" = "⛈️"; "lightsleet" = "🌨️"; "lightsleetandthunder" = "⛈️";
        "lightsleetshowers" = "🌨️"; "lightsnow" = "🌨️"; "lightsnowandthunder" = "⛈️"; "lightsnowshowers" = "🌨️";
        "partlycloudy" = "⛅"; "rain" = "🌧️"; "rainandthunder" = "⛈️"; "rainshowers" = "🌧️"; "rainshowersandthunder" = "⛈️";
        "sleet" = "🌨️"; "sleetandthunder" = "⛈️"; "sleetshowers" = "🌨️"; "sleetshowersandthunder" = "⛈️";
        "snow" = "🌨️"; "snowandthunder" = "⛈️"; "snowshowers" = "🌨️"; "snowshowersandthunder" = "⛈️"; "thunderstorm" = "🌩️"
    }

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -UserAgent $Config.UserAgent -TimeoutSec 8
        $nowLocal = Get-Date
        $windowEnd = $nowLocal.AddMinutes(90)

        $timeSeries = $response.properties.timeseries
        $slicesInWindow = $timeSeries | Where-Object {
            $sliceTime = [datetime]$_.time
            $sliceTime -gt $nowLocal -and $sliceTime -le $windowEnd
        }

        $trendThreshold = if ($Config.PSObject.Properties.Name -contains 'TrendSignificanceCelsius') {
            [double]$Config.TrendSignificanceCelsius
        }
        else {
            [double]$script:DefaultTrendSignificanceCelsius
        }       

        $firstFutureInstant = $timeSeries | Where-Object { [datetime]$_.time -ge $nowLocal } | Select-Object -First 1
        $lastInstantInWindow = $timeSeries | Where-Object {
            $t = [datetime]$_.time
            $t -ge $nowLocal -and $t -le $windowEnd
        } | Select-Object -Last 1

        $temperatureTrendArrow = ''
        if ($firstFutureInstant -and $lastInstantInWindow) {
            $tStart = [double]$firstFutureInstant.data.instant.details.air_temperature
            $tEnd = [double]$lastInstantInWindow.data.instant.details.air_temperature
            $delta = $tEnd - $tStart
            if ([math]::Abs($delta) -ge $trendThreshold) {
                $temperatureTrendArrow = if ($delta -gt 0) { '↑' } else { '↓' }
            }
            Write-WeatherLog ("Temp trend start={0} end={1} Δ={2:0.##}°C threshold={3}°C arrow='{4}'" -f $tStart, $tEnd, $delta, $trendThreshold, $temperatureTrendArrow)
        }

        if (-not $slicesInWindow) {
            Write-WeatherLog "No slices in 90m window. Falling back to first future slice."
            $fallbackSlice = $timeSeries | Where-Object { [datetime]$_.time -ge $nowLocal } | Select-Object -First 1
            if (-not $fallbackSlice) { Write-WeatherLog "No forecast slice found."; return $null }
            $rawCode = $fallbackSlice.data.next_1_hours.summary.symbol_code
            if (-not $rawCode) { Write-WeatherLog "No symbol_code on fallback slice."; return $null }
            $normalizedCode = $rawCode -replace '_day$|_night$|_polartwilight$', ''
            $temperature = $fallbackSlice.data.instant.details.air_temperature

            return [pscustomobject]@{
                Temperature  = $temperature
                Icon         = $icons[$normalizedCode]
                IconKey      = $normalizedCode
                IconFromTime = ([datetime]$fallbackSlice.time).ToString('o')
                TrendArrow   = ''
            }
        }

        function Get-SymbolSeverity ([string]$code) {
            # ranking: thunder > heavy precip > frozen precip > rain/showers > fog > clouds > fair > clear
            $severity = 0
            if ($code -match 'thunderstorm|andthunder') { $severity += 100 }
            if ($code -match '^heavy' -or $code -match 'heavyrain|heavysnow|heavysleet') { $severity += 40 }
            if ($code -match 'sleet|snow') { $severity += 25 }
            if ($code -match 'rain|showers') { $severity += 20 }
            if ($code -match '^light') { $severity -= 5 }
            if ($code -eq 'fog') { $severity = [math]::Max($severity, 10) }
            if ($code -eq 'cloudy') { $severity = [math]::Max($severity, 5) }
            if ($code -eq 'partlycloudy') { $severity = [math]::Max($severity, 2) }
            if ($code -eq 'fair') { $severity = [math]::Max($severity, 1) }
            if ($code -eq 'clearsky') { $severity = [math]::Max($severity, 0) }
            return $severity
        }

        $worstSlice = $null
        $worstCode = $null
        $worstSeverity = [int]::MinValue

        foreach ($slice in $slicesInWindow) {
            $period = $slice.data.next_1_hours
            if (-not $period) { continue }
            $rawCode = $period.summary.symbol_code
            if (-not $rawCode) { continue }
            $normalizedCode = $rawCode -replace '_day$|_night$|_polartwilight$', ''
            $severity = Get-SymbolSeverity $normalizedCode
            if ($severity -gt $worstSeverity) {
                $worstSeverity = $severity
                $worstSlice = $slice
                $worstCode = $normalizedCode
            }
        }

        if (-not $worstSlice) { Write-WeatherLog "No symbol_code within window."; return $null }

        # Temperature from the nearest future instant
        $tempSlice = $timeSeries | Where-Object { [datetime]$_.time -ge $nowLocal } | Select-Object -First 1
        $temperature = $tempSlice.data.instant.details.air_temperature

        Write-WeatherLog ("Worst-in-90m: code={0} sev={1} at={2} arrow='{3}'" -f $worstCode, $worstSeverity, ([datetime]$worstSlice.time).ToString("yyyy-MM-dd HH:mm"), $temperatureTrendArrow)

        return [pscustomobject]@{
            Temperature  = $temperature
            Icon         = ($icons[$worstCode] | ForEach-Object { if ($_) { $_ } else { '❓' } })
            IconKey      = $worstCode
            IconFromTime = ([datetime]$worstSlice.time).ToString('o')
            TrendArrow   = $temperatureTrendArrow
        }
    }
    catch {
        Write-WeatherLog ("Sync fetch error: " + $_.Exception.Message)
        return $null
    }
}

function Request-WeatherForPrompt {
    $cached = Read-WeatherCache
    if ($cached) {
        $global:WeatherTemperature = $cached.Temperature
        $global:WeatherIcon = $cached.Icon
        $global:WeatherTrendArrow = ($cached.TrendArrow | ForEach-Object { if ($_) { $_ } else { '' } })
        return
    }

    $config = Get-WeatherConfiguration
    if (-not $config) {
        $global:WeatherTemperature = 'N/A'
        $global:WeatherIcon = if ($PSVersionTable.PSVersion.Major -ge 7) { '…' } else { '' }
        return
    }

    $result = Get-WeatherNow -Config $config
    if ($result) {
        Write-WeatherCache -Temperature $result.Temperature -Icon $result.Icon -WindowMinutes 90 -IconKey $result.IconKey -IconSourceTime $result.IconFromTime -TrendArrow $result.TrendArrow
        $global:WeatherTemperature = $result.Temperature
        $global:WeatherIcon = $result.Icon
        $global:WeatherTrendArrow = $result.TrendArrow
        Write-WeatherLog "Cache refreshed synchronously (worst-in-90m): $($result.Temperature)°C [$($result.IconKey)] Trend=$($result.TrendArrow)"
    }
    else {
        $global:WeatherTemperature = 'N/A'
        $global:WeatherIcon = if ($PSVersionTable.PSVersion.Major -ge 7) { '🚫🛜' } else { '' }
        $global:WeatherTrendArrow = ''
    }
}

Export-ModuleMember -Function Request-WeatherForPrompt, Get-WeatherConfiguration, Read-WeatherCache
