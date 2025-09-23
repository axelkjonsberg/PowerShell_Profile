Set-Variable -Name DivergenceNumberThreshold -Option Constant -Scope Script -Value 2

Set-Variable -Name UpArrowGlyph -Option Constant -Scope Script -Value ([char]0x2191) # ↑
Set-Variable -Name DownArrowGlyph -Option Constant -Scope Script -Value ([char]0x2193) # ↓

# Keyed by repo root; value includes last seen HEAD OID and FETCH_HEAD time
$script:RepositoryStatusCache = @{}

function Get-GitRepositoryPaths {
    param([Parameter(Mandatory)] [string]$StartPath)

    $directory = Get-Item -LiteralPath $StartPath -ErrorAction SilentlyContinue
    while ($directory) {
        $gitMarkerPath = Join-Path $directory.FullName '.git'
        if (Test-Path -LiteralPath $gitMarkerPath) {
            if (Test-Path -LiteralPath $gitMarkerPath -PathType Container) {
                return [pscustomobject]@{ RepoRoot = $directory.FullName; GitDir = $gitMarkerPath }
            }

            # Worktree / gitfile that points to the real gitdir
            $firstLine = Get-Content -LiteralPath $gitMarkerPath -TotalCount 1 -ErrorAction SilentlyContinue
            if ($firstLine -match '^gitdir:\s*(.+)$') {
                $target = $Matches[1]
                $resolved = if ([IO.Path]::IsPathRooted($target)) {
                    Resolve-Path -LiteralPath $target -ErrorAction SilentlyContinue
                }
                else {
                    Resolve-Path -LiteralPath (Join-Path $directory.FullName $target) -ErrorAction SilentlyContinue
                }
                if ($resolved) {
                    return [pscustomobject]@{ RepoRoot = $directory.FullName; GitDir = $resolved.Path }
                }
            }
        }
        $directory = $directory.Parent
    }
    return $null
}

function Get-GitHeadBranchName {
    param([Parameter(Mandatory)] [string]$GitDir)

    $headFile = Join-Path $GitDir 'HEAD'
    $line = Get-Content -LiteralPath $headFile -TotalCount 1 -ErrorAction SilentlyContinue
    if ($line -match '^ref:\s+refs/heads/(.+)$') { return $Matches[1] }
    elseif ($line) { return 'DETACHED' }
    return $null
}

function Get-GitRefObjectId {
    param(
        [Parameter(Mandatory)] [string]$GitDir,
        [Parameter(Mandatory)] [string]$RefRelativePath
    )

    $looseRefPath = Join-Path $GitDir $RefRelativePath
    if (Test-Path -LiteralPath $looseRefPath -PathType Leaf) {
        return (Get-Content -LiteralPath $looseRefPath -TotalCount 1 -ErrorAction SilentlyContinue)
    }

    $packedRefs = Join-Path $GitDir 'packed-refs'
    if (Test-Path -LiteralPath $packedRefs -PathType Leaf) {
        foreach ($line in (Get-Content -LiteralPath $packedRefs -ErrorAction SilentlyContinue)) {
            if ($line -match '^[0-9a-fA-F]{40}\s+' + [regex]::Escape($RefRelativePath) + '$') {
                return ($line -split '\s+', 2)[0]
            }
        }
    }
    return $null
}

function Get-GitAheadBehindCounts {
    param([Parameter(Mandatory)] [string]$RepoRoot)

    $counts = (& git -C $RepoRoot rev-list --left-right --count '@{u}...@' 2>$null)
    if (-not $counts) {
        return [pscustomobject]@{ Behind = 0; Ahead = 0; HasUpstream = $false }
    }

    $parts = ($counts -replace '\s+$', '') -split '\s+'
    if ($parts.Count -lt 2) {
        return [pscustomobject]@{ Behind = 0; Ahead = 0; HasUpstream = $true }
    }

    return [pscustomobject]@{ Behind = [int]$parts[0]; Ahead = [int]$parts[1]; HasUpstream = $true }
}

# Public
function Get-GitPromptSegment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$CurrentDirectoryLeaf,
        [int]$NumberThreshold = $script:DivergenceNumberThreshold
    )

    $where = Get-GitRepositoryPaths -StartPath $pwd.Path
    if (-not $where) { return '' }

    $repoRoot = $where.RepoRoot
    $gitDir = $where.GitDir
    $repoName = Split-Path -Leaf $repoRoot

    $branch = Get-GitHeadBranchName -GitDir $gitDir
    if (-not $branch) { return '' }

    # Create a cache signature that changes when HEAD moves or after a fetch
    $fetchFile = Join-Path $gitDir 'FETCH_HEAD'
    $fetchStamp = (Get-Item -LiteralPath $fetchFile -ErrorAction SilentlyContinue)?.LastWriteTimeUtc?.ToFileTimeUtc()

    $headObjectId = if ($branch -ne 'DETACHED') {
        Get-GitRefObjectId -GitDir $gitDir -RefRelativePath ("refs/heads/" + $branch)
    }
    else {
        Get-GitRefObjectId -GitDir $gitDir -RefRelativePath 'HEAD'
    }

    $upstreamRef = (& git -C $repoRoot rev-parse --symbolic-full-name '@{u}' 2>$null)
    $upstreamOid = $null
    if ($LASTEXITCODE -eq 0 -and $upstreamRef) {
        $upstreamOid = Get-GitRefObjectId -GitDir $gitDir -RefRelativePath $upstreamRef
    }
    $packedStamp = (Get-Item -LiteralPath (Join-Path $gitDir 'packed-refs') -ErrorAction SilentlyContinue)?.LastWriteTimeUtc?.ToFileTimeUtc()

    $cache = $script:RepositoryStatusCache[$repoRoot]
    $signatureChanged = -not $cache -or
    $cache.HeadObjectId -ne $headObjectId -or
    $cache.FetchStamp -ne $fetchStamp -or
    $cache.BranchName -ne $branch -or
    $cache.UpstreamRef -ne $upstreamRef -or
    $cache.UpstreamOid -ne $upstreamOid -or
    $cache.PackedStamp -ne $packedStamp

    if ($signatureChanged) {
        $ab = [pscustomobject]@{ Ahead = 0; Behind = 0 }
        $hasUpstream = $false
        if ($upstreamRef) {
            $ab = Get-GitAheadBehindCounts -RepoRoot $repoRoot
            $hasUpstream = $true
        }
        $cache = @{
            RepoName     = $repoName
            BranchName   = $branch
            HeadObjectId = $headObjectId
            FetchStamp   = $fetchStamp
            UpstreamRef  = $upstreamRef
            UpstreamOid  = $upstreamOid
            PackedStamp  = $packedStamp
            Ahead        = $ab.Ahead
            Behind       = $ab.Behind
            HasUpstream  = $hasUpstream
        }
        $script:RepositoryStatusCache[$repoRoot] = $cache
    }

    # Build small status string
    $status = ''
    if ($cache.Behind -gt 0) { $status += "$(if($cache.Behind -ge $NumberThreshold){$cache.Behind})$($script:DownArrowGlyph)" }
    if ($cache.Ahead -gt 0) { $status += "$(if($cache.Ahead  -ge $NumberThreshold){$cache.Ahead })$($script:UpArrowGlyph)" }
    if ($status) { $status = "($status)" }

    if ($repoName -ne $CurrentDirectoryLeaf) {
        if ($cache.HasUpstream) { "[${repoName}:${branch}${status}]" } else { "[${repoName}:${branch}]" }
    }
    else {
        if ($cache.HasUpstream) { "[${branch}${status}]" } else { "[${branch}]" }
    }
}

Export-ModuleMember -Function Get-GitPromptSegment, Get-GitAheadBehindCounts
