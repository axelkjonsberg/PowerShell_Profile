# Region: Helper functions
function DisplayCommandInfo {
    param(
        [System.Management.Automation.CommandInfo]$Command,
        [string[]]$CommonFunctionParameters
    )
    Write-Host "- $($Command.Name)" -NoNewline -ForegroundColor Yellow
    DisplayParameters -Command $Command -CommonFunctionParameters $CommonFunctionParameters
}

function DisplayParameters {
    param(
        [System.Management.Automation.CommandInfo]$Command,
        [string[]]$CommonFunctionParameters
    )
    $mandatoryParameters = $Command.Parameters.Values | Where-Object { $CommonFunctionParameters -notcontains $_.Name -and $_.Attributes.Mandatory -eq $true }
    $optionalParameters = $Command.Parameters.Values | Where-Object { $CommonFunctionParameters -notcontains $_.Name -and $_.Attributes.Mandatory -ne $true }

    # Display mandatory parameters first
    foreach ($param in $mandatoryParameters) {
        $parameterName = " -" + $param.Name + " "
        Write-Host $parameterName -NoNewline -ForegroundColor Magenta
        Write-Host ("<" + $param.ParameterType.Name + ">") -NoNewline -ForegroundColor Gray
    }

    # Display optional parameters afterwards
    foreach ($param in $optionalParameters) {
        $parameterName = " -" + $param.Name + " "
        Write-Host $parameterName -NoNewline -ForegroundColor DarkMagenta
        Write-Host ("<" + $param.ParameterType.Name + "?>") -NoNewline -ForegroundColor DarkGray
    }

    Write-Host
}

function DisplayAliases {
    param(
        [string]$CommandName,
        [string]$ModuleName
    )
    $aliasList = Get-Alias | Where-Object { $_.ReferencedCommand.Name -eq $CommandName -and $_.ReferencedCommand.ModuleName -eq $ModuleName }
    if ($aliasList) {
        foreach ($alias in $aliasList) {
            Write-Host "  Has alias: " -ForegroundColor Gray -NoNewline
            Write-Host "$($alias.Name)" -ForegroundColor Cyan
        }
    }
}

function DisplayLoadedScriptAndModuleInfo {
    param(
        [string]$FullPath,
        [string]$Type # "Module" or "Script"
    )

    $name = [System.IO.Path]::GetFileNameWithoutExtension($FullPath)
    Write-Host "`nLoaded $($Type): $name" -ForegroundColor Green

    try {
        if ($Type -eq "Module") {
            $moduleCommands = Get-Command -Module $moduleName -ErrorAction SilentlyContinue
        } elseif ($Type -eq "Script") {
            $moduleCommands = Get-Command -ErrorAction SilentlyContinue | Where-Object { $_.ScriptBlock.File -eq $FullPath }
        }

        if ($moduleCommands -and $moduleCommands.Count -gt 0) {
            foreach ($command in $moduleCommands) {
                DisplayCommandInfo -Command $command -CommonFunctionParameters $commonFunctionParameters
                DisplayAliases -CommandName $command.Name -ModuleName $name
            }
        }
        else {
            Write-Host "No commands found for $($Type): $name" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Error displaying commands for $($Type): $name. Error: $_" -ForegroundColor Red
    }
}

# End of region

# Region: Load custom scripts

if (-not (Test-Path variable:Global:LoadedModulesAndScripts)) {
    $Global:LoadedModulesAndScripts = @{}
}

$customModulesPath = Join-Path -Path $PSScriptRoot -ChildPath "Custom\Modules"
$customScriptsPath = Join-Path -Path $PSScriptRoot -ChildPath "Custom\Scripts"

$commonFunctionParameters = 'Debug', 'ErrorAction', 'ErrorVariable', 'InformationAction', 'InformationVariable', 'OutBuffer', 'OutVariable', 'PipelineVariable', 'Verbose', 'WarningAction', 'WarningVariable', 'WhatIf', 'Confirm'

$numberOfCustomFunctions = 0

$moduleFiles = Get-ChildItem -Path $customModulesPath -Filter *.psm1 -Recurse
foreach ($moduleFile in $moduleFiles) {
    try {
        $content = Get-Content $moduleFile.FullName -Head 1 -ErrorAction SilentlyContinue
        if ($content -match "doNotLoadByDefault: true") {
            continue
        }

        $moduleFullPath = $moduleFile.FullName
        $moduleName = $moduleFile.BaseName

        Import-Module -Name $moduleFullPath -ErrorAction Stop
        $Global:LoadedModulesAndScripts[$moduleFullPath] = $true

        DisplayLoadedScriptAndModuleInfo -FullPath $moduleFullPath -Type "Module"
        $moduleCommands = (Get-Command | Where-Object { $_.ScriptBlock.File -eq $moduleFullPath })
        $numberOfCustomFunctions += $moduleCommands.Count
    }
    catch {
        Write-Host "Failed to load module: $moduleName" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

$scriptFiles = Get-ChildItem -Path $customScriptsPath -Filter *.ps1 -Recurse
foreach ($scriptFile in $scriptFiles) {
    try {
        $content = Get-Content $scriptFile.FullName -Head 1 -ErrorAction SilentlyContinue
        if ($content -match "doNotLoadByDefault: true") {
            continue
        }

        $scriptFullPath = $scriptFile.FullName
        . $scriptFullPath
        $Global:LoadedModulesAndScripts[$scriptFullPath] = $true

        DisplayLoadedScriptAndModuleInfo -FullPath $scriptFullPath -Type "Script"
        $scriptCommands = (Get-Command | Where-Object { $_.ScriptBlock.File -eq $scriptFullPath })
        $numberOfCustomFunctions += $scriptCommands.Count
    }
    catch {
        $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($scriptFile.FullName)
        Write-Host "Failed to load script: $($scriptName)" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

Write-Host "`nSuccessfuly loaded PowerShell profile: " -NoNewline
Write-Host $PROFILE -ForegroundColor Cyan
Write-Host "Loaded $numberOfCustomFunctions custom functions."

# End of region
