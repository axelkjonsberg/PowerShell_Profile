$utilsPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents\WindowsPowerShell\ProfileUtils.ps1"
.$utilsPath

$isGitRepo = Confirm-GitRepository
if ($isGitRepo) {
    Add-SshKey
    Write-Host
    # Wake up the GPG agent
    # Or not, as we are using ssh for signing commits
    # gpg-connect-agent /bye | Out-Null
}

$promptCustomizationsPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents\WindowsPowerShell\PromptCustomizations.ps1"
.$promptCustomizationsPath | Out-Null

if (-not $Global:LoadedModules) {
    $Global:LoadedModules = @{}
}

$customModulesBasePath = $env:CUSTOM_MODULES_PATH
if (-not $customModulesBasePath) {
    Write-Host "CUSTOM_MODULES_PATH environment variable is not set. Custom modules loading will be skipped." -ForegroundColor Yellow
    return
}

Write-Host "Attempting to load custom modules from: $customModulesBasePath"

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
    Write-Host "- Import-ExtraModules `e[36m(iem)`e[0m: Dynamically load additional modules." -ForegroundColor Yellow
    Write-Host "- Show-LoadedModules `e[36m(slm)`e[0m: Display currently loaded modules." -ForegroundColor Yellow

    if ($taskManagerAvailable) {
        # Show-PrioritizedTasks
    }

    Write-Host
}

Show-WelcomeMessage
