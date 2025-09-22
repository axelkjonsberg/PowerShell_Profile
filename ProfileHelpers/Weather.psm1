Set-Variable -Name DefaultLatitude -Option Constant -Scope Script -Value 59.91278
Set-Variable -Name DefaultLongitude -Option Constant -Scope Script -Value 10.73639
Set-Variable -Name DefaultCacheTtlMinutes -Option Constant -Scope Script -Value 60
Set-Variable -Name WeatherCacheFilePath -Option Constant -Scope Script -Value (Join-Path $HOME '.weatherCache.json')
Set-Variable -Name WeatherLogFilePath -Option Constant -Scope Script -Value (Join-Path $HOME '.weather.log')
Set-Variable -Name WeatherConfigPath -Option Constant -Scope Script -Value (Join-Path $HOME '.weatherConfig.json')

$global:WeatherTemperature = $null
$global:WeatherIcon = $null

# Module settings
$script:WriteDebugLogToFile = $true
$script:EchoDebugLogToHost = $true

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

        Write-WeatherLog "Config OK; UA length=$($userAgent.Length) TTL=$ttl Lat=$lat Lon=$lon"
        [pscustomobject]@{ UserAgent = $userAgent; Latitude = $lat; Longitude = $lon; CacheTtlMinutes = $ttl }
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
        $cfg = Get-WeatherConfiguration
        $ttl = if ($cfg) { [int]$cfg.CacheTtlMinutes } else { $script:DefaultCacheTtlMinutes }

        # Read the whole file as a single string, then parse JSON
        # (Get-Content -Raw + ConvertFrom-Json is the recommended pattern).
        $data = Get-Content -LiteralPath $script:WeatherCacheFilePath -Raw | ConvertFrom-Json

        if (-not $data.LastUpdated) { Write-WeatherLog "Cache missing LastUpdated."; return $null }

        $freshUntil = ([datetime]$data.LastUpdated).AddMinutes($ttl)
        $isFresh = (Get-Date) -lt $freshUntil

        Write-WeatherLog ("Cache found. Fresh={0} Temp={1} Icon={2}" -f $isFresh, $data.Temperature, $data.Icon)
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
        [Parameter(Mandatory)] $Icon
    )

    $target = $script:WeatherCacheFilePath
    $dir = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = @{ LastUpdated = (Get-Date).ToString('o'); Temperature = $Temperature; Icon = $Icon } |
    ConvertTo-Json -Compress

    $tmp = Join-Path $dir ('.weatherCache.json.tmp.' + [guid]::NewGuid().ToString('N'))

    try {
        [System.IO.File]::WriteAllText($tmp, $json)

        if ([System.IO.File].GetMethod('Move', [Type[]]@([string], [string], [bool]))) {
            [System.IO.File]::Move($tmp, $target, $true)   # overwrite: true
        }
        else {
            # Fallback: Replace with a real backup path to avoid $null -> "" coercion
            if (Test-Path -LiteralPath $target) {
                $bk = "$target.bak"
                [System.IO.File]::Replace($tmp, $target, $bk)   # preserves ACLs/attrs
                Remove-Item -LiteralPath $bk -Force -ErrorAction SilentlyContinue
            }
            else {
                [System.IO.File]::Move($tmp, $target)
            }
        }

        Write-WeatherLog "Cache updated atomically at $target"
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
        "sleet" = "🌨️"; "sleetandthunder" = "⛈️"; "sleetshowers" = "🌨️"; "sleetshowersandthunder" = "🌨️";
        "snow" = "🌨️"; "snowandthunder" = "⛈️"; "snowshowers" = "🌨️"; "snowshowersandthunder" = "⛈️"; "thunderstorm" = "🌩️"
    }

    try {
        $resp = Invoke-RestMethod -Uri $apiUrl -UserAgent $Config.UserAgent -TimeoutSec 8
        $fc = $resp.properties.timeseries |
        Where-Object { [datetime]$_.time -ge (Get-Date).AddHours(1) } |
        Select-Object -First 1
        if (-not $fc) { Write-WeatherLog "No forecast slice found."; return $null }

        $t = $fc.data.instant.details.air_temperature
        $sc = $fc.data.next_1_hours.summary.symbol_code -replace '_day$|_night$', ''
        [pscustomobject]@{ Temperature = $t; Icon = $icons[$sc]; IconKey = $sc }
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
        return
    }

    $cfg = Get-WeatherConfiguration
    if (-not $cfg) {
        $global:WeatherTemperature = 'N/A'
        $global:WeatherIcon = if ($PSVersionTable.PSVersion.Major -ge 7) { '…' } else { '' }
        return
    }

    $result = Get-WeatherNow -Config $cfg
    if ($result) {
        Write-WeatherCache -Temperature $result.Temperature -Icon $result.Icon
        $global:WeatherTemperature = $result.Temperature
        $global:WeatherIcon = $result.Icon
        Write-WeatherLog "Cache refreshed synchronously: $($result.Temperature)°C ($($result.IconKey))"
    }
    else {
        $global:WeatherTemperature = 'N/A'
        $global:WeatherIcon = if ($PSVersionTable.PSVersion.Major -ge 7) { '🚫🛜' } else { '' }
    }
}

Export-ModuleMember -Function Request-WeatherForPrompt, Get-WeatherConfiguration, Read-WeatherCache
