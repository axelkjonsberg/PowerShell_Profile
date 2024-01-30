# Region: Helper functions

function Import-ModuleAndDisplayInfo {
    param(
        [string]$ModulePath,
        [string]$ModuleName
    )
    Import-Module -Name $ModulePath -ErrorAction Stop
    Write-Host "`nLoaded module: $($ModuleName).psm1" -ForegroundColor Green
}

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

# Region: The profile load script

$customModulesPath = Join-Path -Path $PSScriptRoot -ChildPath "CustomModules"
$commonFunctionParameters = 'Debug', 'ErrorAction', 'ErrorVariable', 'InformationAction', 'InformationVariable', 'OutBuffer', 'OutVariable', 'PipelineVariable', 'Verbose', 'WarningAction', 'WarningVariable', 'WhatIf', 'Confirm'

$moduleFiles = Get-ChildItem -Path $customModulesPath -Filter *.psm1 -Recurse
$scriptFiles = Get-ChildItem -Path $customModulesPath -Filter *.ps1 -Recurse

$numberOfCustomFunctions = 0

foreach ($moduleFile in $moduleFiles) {
    try {
        $moduleFullPath = $moduleFile.FullName
        $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($moduleFullPath)

        Import-ModuleAndDisplayInfo -ModulePath $moduleFullPath -ModuleName $moduleName

        $moduleCommands = Get-Command -Module $moduleName
        foreach ($command in $moduleCommands) {
            DisplayCommandInfo -Command $command -CommonFunctionParameters $commonFunctionParameters
            DisplayAliases -CommandName $command.Name -ModuleName $moduleName
            $numberOfCustomFunctions++
        }
    }
    catch {
        Write-Host "Failed to load module: $($moduleName)" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

foreach ($scriptFile in $scriptFiles) {
    try {
        $scriptFullPath = $scriptFile.FullName
        . $scriptFullPath
        $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($scriptFullPath)
        Write-Host "`nLoaded script: $($scriptName).ps1" -ForegroundColor Green

        $scriptCommands = Get-Command | Where-Object { $_.ScriptBlock.File -eq $scriptFullPath }
        foreach ($command in $scriptCommands) {
            DisplayCommandInfo -Command $command -CommonFunctionParameters $commonFunctionParameters
            DisplayAliases -CommandName $command.Name -ModuleName $null
            $numberOfCustomFunctions++
        }
    }
    catch {
        Write-Host "Failed to load script: $($scriptName)" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

Write-Host "`nPowerShell profile from " -NoNewline
Write-Host $PROFILE -ForegroundColor Cyan -NoNewline
Write-Host " was loaded."
Write-Host "Loaded $numberOfCustomFunctions custom functions."
