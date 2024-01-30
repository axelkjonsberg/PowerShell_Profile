$utilsPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents\WindowsPowerShell\ProfileUtils.ps1"
. $utilsPath

$promptCustomizationsPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents\WindowsPowerShell\PromptCustomizations.ps1"
. $promptCustomizationsPath

if (-not (Test-Path variable:Global:LoadedModulesAndScripts)) {
    $Global:LoadedModulesAndScripts = @{}
}

$customModulesPath = Join-Path -Path $PSScriptRoot -ChildPath "Custom\Modules"
$customScriptsPath = Join-Path -Path $PSScriptRoot -ChildPath "Custom\Scripts"

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
