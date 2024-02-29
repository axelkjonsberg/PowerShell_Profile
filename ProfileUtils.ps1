# Region: Internal helper functions 

function Show-ModuleInfo {
    param([string]$ModuleName)

    $module = $Global:LoadedModules[$ModuleName]
    if (-not $module) {
        Write-Host "Module `$ModuleName` is not loaded or does not exist." -ForegroundColor Yellow
        return
    }

    Write-Host "Module: $ModuleName (v$($module.Version))" -ForegroundColor Green
    if ($null -ne $module.Author) {
        Write-Host "Author: $($module.Author)"
    }
    # Write-Host "Description: $($module.Description)"
    if ($module.ExportedCommandsAndAliases.Keys.Count -gt 0) {
        Write-Host "Exported Commands and Aliases:"
    }


    foreach ($commandName in $module.ExportedCommandsAndAliases.Keys) {
        if ($module.ExportedCommandsAndAliases[$commandName]) {
            continue
        }

        $commandInfo = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -ne $commandInfo) {
            $aliases = $module.ExportedCommandsAndAliases.Keys | Where-Object { $module.ExportedCommandsAndAliases[$_] -eq $commandName }
            $aliasText = if ($aliases) { "`e[36m(" + ($aliases -join ', ') + ")`e[0m" } else { "" }

            $displayName = "- $commandName $aliasText".Trim()
            Write-Host $displayName -ForegroundColor Yellow -NoNewline

            if (-not $commandInfo.Parameters.Keys) {
                Write-Host
            }

            Show-Parameters -Command $commandInfo
            Write-Host
        } else {
            Write-Host "- $commandName could not retrieve command info" -ForegroundColor Red
        }
    }
    Write-Host
}

function Show-Parameters {
    param(
        [System.Management.Automation.CommandInfo]$Command
    )

    $commonFunctionParameters = 'Debug','ErrorAction','ErrorVariable','InformationAction','ProgressAction','InformationVariable','OutBuffer','OutVariable','PipelineVariable','Verbose','WarningAction','WarningVariable','WhatIf','Confirm'
    $allParameters = $Command.Parameters.Values | Where-Object { $commonFunctionParameters -notcontains $_.Name }

    $mandatoryParameters = $allParameters | Where-Object { $_.Attributes.Mandatory -eq $true }
    $optionalParameters = $allParameters | Where-Object { $_.Attributes.Mandatory -ne $true }

    # Display mandatory parameters first
    foreach ($param in $mandatoryParameters) {
        $parameterName = " -" + $param.Name
        Write-Host $parameterName -NoNewline -ForegroundColor Magenta
        Write-Host ("<" + $param.ParameterType.Name + ">") -NoNewline -ForegroundColor Gray
    }

    # Display optional parameters afterwards
    foreach ($param in $optionalParameters) {
        $parameterName = " -" + $param.Name
        Write-Host $parameterName -NoNewline -ForegroundColor DarkMagenta
        Write-Host ("<" + $param.ParameterType.Name + "?>") -NoNewline -ForegroundColor DarkGray
    }
}

function Get-TaskManager {
    [CmdletBinding()]
    param()

    if (-not $Global:LoadedModules) {
        $Global:LoadedModules = @{}
    }

    $isInstalled = Get-Module -ListAvailable -Name ManageTasks

    if (-not $isInstalled -and -not $Global:LoadedModules.ContainsKey('ManageTasks')) {
        return $false
    }

    return $true
}

function Confirm-GitRepository {
    try {
        $null = git rev-parse --is-inside-work-tree
        $true
    } catch {
        $false
    }
}

function Add-SshKey {
    if (-not (Test-Path env:SSH_AGENT_PID)) {
        Start-Process ssh-agent -WindowStyle Hidden
    }

    $keysAdded = ssh-add -l
    if ($keysAdded -contains "The agent has no identities.") {
        ssh-add
    }
}

# End region

# Region: Exported functions

function Show-LoadedModules {
    if ($Global:LoadedModules.Count -gt 0) {
        Write-Host "`nLoaded Modules:" -ForegroundColor Cyan
        foreach ($moduleName in $Global:LoadedModules.Keys) {
            Show-ModuleInfo -ModuleName $moduleName
        }
    } else {
        Write-Host "No custom modules have been loaded." -ForegroundColor Yellow
    }
}

function Show-MenuSelection {
    param(
        [Parameter(Mandatory = $true)] [array]$Items,
        [Parameter(Mandatory = $false)] [array]$PreselectedIndices
    )

    $currentIndex = 0
    $selections = @{}
    $selectionComplete = $false

    foreach ($index in $PreselectedIndices) {
        $selections[$index] = $true
    }

    function DisplayItems {
        param(
            [bool]$selectionComplete
        )

        Clear-Host
        Write-Host "Select items (use 'Up/Down' arrows to navigate, 'Space' to select, 'Enter' to finalize):"

        for ($i = 0; $i -lt $Items.Count; $i++) {
            $foregroundColor = if ($i -eq $currentIndex -and -not $selectionComplete) { "White" } else { "DarkGray" }
            $selectedSign = if ($i -eq $currentIndex -and -not $selectionComplete) { "<" } else { "" }
            $checkMark = if ($selections[$i]) { "`e[36m[x]`e[0m" } else { "[ ]" }

            $displayString = "- $checkMark $($Items[$i].Name) $selectedSign"
            Write-Host $displayString -ForegroundColor $foregroundColor
        }
    }

    [console]::CursorVisible = $false
    DisplayItems -selectionComplete $false

    do {
        $key = [Console]::ReadKey($true)
        if ($key.Key -in 'UpArrow','DownArrow','Spacebar') {
            switch ($key.Key) {
                "UpArrow" {
                    if ($currentIndex -gt 0) { $currentIndex -- }
                }
                "DownArrow" {
                    if ($currentIndex -lt $Items.Count - 1) { $currentIndex++ }
                }
                "Spacebar" {
                    $selections[$currentIndex] = -not $selections[$currentIndex]
                }
            }
            DisplayItems -selectionComplete $false
        }
    } while ($key.Key -ne "Enter")

    [console]::CursorVisible = $true

    $selectionComplete = $true
    DisplayItems -selectionComplete $true

    # Return indices of selected items
    return $selections.Keys | Where-Object { $selections[$_] }
}

function Load-ModuleWithDetails {
    param([Parameter(Mandatory = $true)] [string]$ModulePath)

    # Verify if the module path exists
    if (-not (Test-Path -Path $ModulePath)) {
        Write-Host "Module path does not exist: $ModulePath" -ForegroundColor Yellow
        return $false
    }

    # Determine if the path is a directory or a file
    $moduleToLoad = if (Test-Path -Path $ModulePath -PathType Container) {
        $manifest = Get-ChildItem -Path $ModulePath -Filter "*.psd1" -File | Select-Object -First 1
        $manifest?.FullName
    } else {
        $ModulePath
    }

    # Verify if a valid module manifest or file is found
    if (-not $moduleToLoad) {
        Write-Host "Valid module manifest (.psd1) or module file not found: $ModulePath" -ForegroundColor Red
        return $false
    }

    try {
        $moduleInfo = Import-Module -Name $moduleToLoad -Passthru -ErrorAction Stop
        $moduleName = $moduleInfo.Name

        $exportedCommandsAndAliases = @{}

        foreach ($cmd in $moduleInfo.ExportedCommands.Values) {
            if ($cmd.CommandType -eq 'Alias') {
                # For aliases, map the alias name to the resolved command name
                $exportedCommandsAndAliases[$cmd.Name] = $cmd.ResolvedCommandName
            } else {
                # For commands, ensure an entry exists even if it does not have aliases
                $exportedCommandsAndAliases[$cmd.Name] = $null
            }
        }

        $Global:LoadedModules[$moduleName] = @{
            Path = $moduleToLoad
            Version = $moduleInfo.Version.ToString()
            Author = $moduleInfo.Author
            Description = $moduleInfo.Description
            ExportedCommandsAndAliases = $exportedCommandsAndAliases
        }
        return $true
    } catch {
        Write-Host "Failed to load module: $ModulePath with error: $_" -ForegroundColor Red
        return $false
    }
}

function Import-ExtraModules {
    $pathToCustom = $env:CUSTOM_MODULES_PATH
    if (-not $pathToCustom) {
        Write-Host "CUSTOM_MODULES_PATH environment variable is not set." -ForegroundColor Yellow
        return
    }

    $moduleManifests = Get-ChildItem -Path $pathToCustom -Recurse -Filter "*.psd1"
    if (-not $moduleManifests) {
        Write-Host "No module manifests found in $pathToCustom." -ForegroundColor Yellow
        return
    }

    $availableModules = $moduleManifests | ForEach-Object {
        $name = $_.BaseName
        @{
            Path = $_.FullName
            Name = $name
            IsLoaded = $Global:LoadedModules.ContainsKey($name)
        }
    }

    $selectedIndices = Show-MenuSelection -Items $availableModules -PreselectedIndices ($availableModules | Where-Object { $_.IsLoaded }).ForEach({ $availableModules.IndexOf($_) })
    $newlySelectedIndices = $selectedIndices | Where-Object { -not $availableModules[$_].IsLoaded }

    foreach ($index in $newlySelectedIndices) {
        $module = $availableModules[$index]
        $loadResult = Load-ModuleWithDetails -ModulePath $module.Path
        if ($loadResult) {
            Write-Host "Successfully loaded: $($module.Name)" -ForegroundColor Green
        }
    }
}

Set-Alias -Name iem -Value Import-ExtraModules
Set-Alias -Name slm -Value Show-LoadedModules

# End region
