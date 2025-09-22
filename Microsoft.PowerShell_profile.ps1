$customModules = Join-Path $HOME 'Documents\WindowsPowerShell\CustomModules'
if ($env:PSModulePath -notlike "*$customModules*") {
    $env:PSModulePath = $customModules + [IO.Path]::PathSeparator + $env:PSModulePath
}

if ($PSStyle) {
    if ($env:NO_COLOR) { Remove-Item Env:NO_COLOR -ErrorAction Ignore }
    $PSStyle.OutputRendering = 'Ansi'
}

Import-Module "$HOME\Documents\WindowsPowerShell\ProfileHelpers\PsStyleShim.psm1" -ErrorAction SilentlyContinue
Import-Module "$HOME\Documents\WindowsPowerShell\ProfileHelpers\Weather.psm1" -ErrorAction Stop
Import-Module "$HOME\Documents\WindowsPowerShell\ProfileHelpers\GitInfo.psm1" -ErrorAction Stop
Import-Module "$HOME\Documents\WindowsPowerShell\ProfileHelpers\PromptWiring.psm1" -ErrorAction Stop

Set-CustomPrompt

Import-Module "$HOME\Documents\WindowsPowerShell\ProfileHelpers\RepoContext.psm1" -ErrorAction Stop
Import-Module "$HOME\Documents\WindowsPowerShell\ProfileHelpers\GitSshAgent.psm1" -ErrorAction Stop
Enable-GitSshOnDemand


Set-CustomModulesRoot -Path $customModules
Set-DirectoryRules @(
    @{ Name = 'Git'; Predicate = { Test-GitRepository }; Modules = @(
            'GitAliases',
            'remove-git-branches\PowerShell\RemoveGitBranches'
        )
    },
    @{ Name = 'FK'; Predicate = { Test-UnderPathSegment '\\FK' }; Modules = @(
            'SyncAzKeyVaultWithUserSecrets'
        )
    },
    @{ Name = 'HasPs'; Predicate = { Test-HasPowerShellFiles }; Modules = @(
            'PsBeautify.psm1'
        )
    }
)
