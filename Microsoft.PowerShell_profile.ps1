$utilsPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents\WindowsPowerShell\ProfileUtils.ps1"
.$utilsPath

$promptCustomizationsPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents\WindowsPowerShell\PromptCustomizations.ps1"
.$promptCustomizationsPath

if (-not $Global:LoadedModules) {
    $Global:LoadedModules = @{}
}

$customModulesBasePath = $env:CUSTOM_MODULES_PATH
if (-not $customModulesBasePath) {
    Write-Host "CUSTOM_MODULES_PATH environment variable is not set. Custom modules loading will be skipped." -ForegroundColor Yellow
    return
}

Write-Host "Attempting to load custom modules from: $customModulesBasePath" -ForegroundColor Cyan

$configPath = Join-Path -Path $customModulesBasePath -ChildPath "DefaultCustomModules.json"
if (-not (Test-Path -Path $configPath)) {
    Write-Host "No inclusion file found at $configPath. If you want to load modules by default, add a DefaultCustomModules.json file at $configPath." -ForegroundColor Yellow
    return
}

Get-Content -Path $configPath -Raw | ConvertFrom-Json | ForEach-Object {
    $fullModulePath = Join-Path -Path $customModulesBasePath -ChildPath $_
    Load-ModuleWithDetails -ModulePath $fullModulePath | Out-Null
}

$taskManagerAvailable = Get-TaskManager

function Show-WelcomeMessage {
    if ($Global:LoadedModules.Count -gt 0) {
        Write-Host "`nSuccessfully loaded modules:" -ForegroundColor Cyan
        foreach ($moduleName in $Global:LoadedModules.Keys) {
            $module = $Global:LoadedModules[$moduleName]
            Write-Host "- $moduleName (v$($module.Version))" -ForegroundColor Green
        }
    } else {
        Write-Host "No custom modules have been loaded." -ForegroundColor Yellow
    }
    Write-Host "`nManage loaded modules with:" -ForegroundColor Cyan
    Write-Host "- Import-ExtraModules (iem): Dynamically load additional modules." -ForegroundColor White
    Write-Host "- Show-LoadedModules (slm): Display currently loaded modules." -ForegroundColor White

    if (-not $taskManagerAvailable) {
        return
    }

    $prioritizedTasks = Get-PrioritizedTasks

    if ($prioritizedTasks.Count -gt 0) {
        Write-Host "`nYour most important tasks:" -ForegroundColor Cyan
        $prioritizedTasks | Format-Table -Property Description,Topic,@{
            Name = 'Deadline'
            Expression = {
                $formattedDeadline = if ($_.Deadline) { $_.Deadline.ToString("yyyy-MM-dd HH:mm:ss") } else { "No Deadline" }

                if ($_.PSObject.Properties.Name -contains 'StrictDeadline' -and $_.StrictDeadline -eq $false) {
                    "$formattedDeadline (Non-strict deadline)"
                } else {
                    $formattedDeadline
                }
            }
        } -AutoSize
    }
}

Show-WelcomeMessage
