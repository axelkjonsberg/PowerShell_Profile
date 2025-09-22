Set-StrictMode -Version Latest

Set-Variable -Name SshAgentServiceName -Scope Script -Option Constant -Value 'ssh-agent'

$script:InitializedRepos = @{}

function Start-SshAgentIfNeeded {
    try {
        $svc = Get-Service -Name $script:SshAgentServiceName -ErrorAction Stop
        if ($svc.Status -ne 'Running') { Start-Service -Name $script:SshAgentServiceName }
    } catch {} # OpenSSH not installed or no permission -> ignore quietly
}

function Ensure-DefaultSshKeysLoaded {
    $list = (& ssh-add -l) 2>&1
    if ($LASTEXITCODE -ne 0 -or ($list -match 'no identities' -or $list -match 'has no identities')) {
        & ssh-add | Out-Null # load default keys if any
    }
}

function Initialize-RepoSshAuthentication {
    # detect repo root only once per session per repo
    $repoRoot = (& $__real_git rev-parse --show-toplevel 2>$null).Trim()
    if (-not $repoRoot -or $script:InitializedRepos.ContainsKey($repoRoot)) { return }
    $script:InitializedRepos[$repoRoot] = $true

    # only for SSH remotes
    $remote = (& $__real_git config --get remote.origin.url 2>$null).Trim()
    if (-not $remote) { return }
    if ($remote -match '^(git@|ssh://)') {
        Start-SshAgentIfNeeded
        Ensure-DefaultSshKeysLoaded
    }
}

function Enable-GitSshOnDemand {
    $gitExe = (Get-Command git.exe -ErrorAction Ignore).Source
    if (-not $gitExe) { return }

    Set-Alias __real_git $gitExe -Scope Global
    function git {
        param([Parameter(ValueFromRemainingArguments = $true)] [string[]]$Args)
        try { Initialize-RepoSshAuthentication } catch {}
        & $__real_git @Args
    }
}

Export-ModuleMember -Function Enable-GitSshOnDemand,Initialize-RepoSshAuthentication
