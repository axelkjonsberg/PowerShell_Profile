Set-StrictMode -Version Latest

Set-Variable -Name DefaultCustomModulesRoot   -Scope Script -Option Constant -Value (Join-Path $HOME 'Documents\WindowsPowerShell\CustomModules')
Set-Variable -Name RepoConfigJsonFileName     -Scope Script -Option Constant -Value '.psmodules.json'
Set-Variable -Name RepoConfigProfileFileName  -Scope Script -Option Constant -Value '.psprofile.ps1'

$script:CustomModulesRoot     = $script:DefaultCustomModulesRoot
$script:DirectoryRules        = @()
$script:LastAppliedContextKey = $null

function Set-CustomModulesRoot([Parameter(Mandatory)][string]$Path) { $script:CustomModulesRoot = $Path }
function Get-CustomModulesRoot { $script:CustomModulesRoot }

function Set-DirectoryRules([Parameter(Mandatory)][array]$Rules) { $script:DirectoryRules = $Rules }
function Get-DirectoryRules { $script:DirectoryRules }

function Test-GitRepository {
    try {
        $git = Get-Command git -ErrorAction Ignore
        if (-not $git) { return $false }
        $out = & $git.Source rev-parse --is-inside-work-tree 2>$null
        ($LASTEXITCODE -eq 0 -and $out.Trim() -eq 'true')
    } catch { $false }
}

function Test-UnderPathSegment([Parameter(Mandatory)][string]$Segment) {
    $PWD.Path -match ([regex]::Escape($Segment) + '(\\|$)')
}

function Test-HasPowerShellFiles {
    [bool](Get-ChildItem -File -Filter *.ps?1 -ErrorAction Ignore | Select-Object -First 1)
}

function Get-GitRepositoryRoot {
    try {
        $git = Get-Command git -ErrorAction Ignore
        if (-not $git) { return $null }
        $root = & $git.Source rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0) { return $root.Trim() }
    } catch { }
    $null
}

function Get-RepositoryModuleListFromFiles {
    $root = Get-GitRepositoryRoot
    if (-not $root) { return $null }   # not in a repo → signal "no repo"

    $jsonPath = Join-Path $root $script:RepoConfigJsonFileName
    if (Test-Path $jsonPath) {
        try {
            $cfg = Get-Content $jsonPath -Raw | ConvertFrom-Json
            if ($cfg.modules) { return @($cfg.modules) }
        } catch { }
    }

    $profilePath = Join-Path $root $script:RepoConfigProfileFileName
    if (Test-Path $profilePath) {
        . $profilePath
        return @()  # ran the repo profile already
    }

    @()  # in a repo, but no explicit module list
}

function Resolve-CustomModulePath([Parameter(Mandatory)][string]$NameOrPath) {
    if (Split-Path $NameOrPath -IsAbsolute) { return $NameOrPath }

    $candidate = Join-Path $script:CustomModulesRoot $NameOrPath
    if (Test-Path $candidate -PathType Container) {
        (Get-ChildItem $candidate -Filter *.psd1 -ea Ignore | Select-Object -First 1)?.FullName `
            ?? (Get-ChildItem $candidate -Filter *.psm1 -ea Ignore | Select-Object -First 1)?.FullName `
            ?? $candidate
    } elseif (Test-Path $candidate) { $candidate } else { $NameOrPath }
}

function Import-ModuleSet([string[]]$Items) {
    foreach ($i in $Items) {
        if ([string]::IsNullOrWhiteSpace($i)) { continue }
        try { Import-Module (Resolve-CustomModulePath $i) -ErrorAction Stop | Out-Null } catch { }
    }
}

function Compute-ContextKey {
    $repoRoot = Get-GitRepositoryRoot
    $marker   = if ($repoRoot) {
        foreach ($f in $script:RepoConfigJsonFileName, $script:RepoConfigProfileFileName) {
            $p = Join-Path $repoRoot $f
            if (Test-Path $p) { (Get-Item $p).LastWriteTimeUtc.Ticks }
        } -join ';'
    }
    '{0}|{1}|{2}' -f $PWD.Path, ($repoRoot ?? ''), $marker
}

function Invoke-ContextModuleLoader {
    $key = Compute-ContextKey
    if ($key -eq $script:LastAppliedContextKey) { return }  # nothing changed

    $repoList = Get-RepositoryModuleListFromFiles
    if ($null -ne $repoList) {
        if ($repoList.Count) { Import-ModuleSet $repoList }
        $script:LastAppliedContextKey = $key
        return
    }

    foreach ($rule in $script:DirectoryRules) {
        if (& $rule.Predicate) { Import-ModuleSet $rule.Modules }
    }
    $script:LastAppliedContextKey = $key
}

Export-ModuleMember -Function `
    Set-CustomModulesRoot, Get-CustomModulesRoot, `
    Set-DirectoryRules,   Get-DirectoryRules,   `
    Test-GitRepository, Test-UnderPathSegment, Test-HasPowerShellFiles, `
    Invoke-ContextModuleLoader
