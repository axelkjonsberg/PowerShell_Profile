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
        [System.Management.Automation.CommandInfo]$Command
    )

    $commonFunctionParameters = 'Debug','ErrorAction','ErrorVariable','InformationAction','ProgressAction','InformationVariable','OutBuffer','OutVariable','PipelineVariable','Verbose','WarningAction','WarningVariable','WhatIf','Confirm'
    $allParameters = $Command.Parameters.Values | Where-Object { $CommonFunctionParameters -notcontains $_.Name }

    $mandatoryParameters = $allParameters | Where-Object { $_.Attributes.Mandatory -eq $true }
    $optionalParameters = $allParameters | Where-Object { $_.Attributes.Mandatory -ne $true }

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

    $moduleCommands = $null
    if ($Type -eq "Module") {
        $moduleCommands = Get-Command -Module $name -ErrorAction SilentlyContinue
    } elseif ($Type -eq "Script") {
        $moduleCommands = Get-Command -ErrorAction SilentlyContinue | Where-Object { $_.ScriptBlock.File -eq $FullPath }
    }

    if (-not $moduleCommands -or $moduleCommands.Count -eq 0) {
        Write-Host "No commands found for $($Type): $name" -ForegroundColor Yellow
        return
    }

    foreach ($command in $moduleCommands) {
        DisplayCommandInfo -Command $command
        if ($Type -eq "Module") {
            DisplayAliases -CommandName $command.Name -ModuleName $name
        } else {
            # For scripts, display aliases based on command name only
            DisplayAliases -CommandName $command.Name -ModuleName $null
        }
    }
}
