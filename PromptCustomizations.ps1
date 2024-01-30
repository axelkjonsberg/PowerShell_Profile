function Get-GitBranch {
    param (
        [string]$currentDirectory
    )

    $gitBranch = & git rev-parse --abbrev-ref HEAD 2>$null
    if ($gitBranch) {
        $repositoryPath = (& git rev-parse --show-toplevel 2>$null).Trim()
        $repositoryName = (Split-Path -Leaf -Path $repositoryPath).Trim()

        if ($repositoryName -ne $currentDirectory) {
            return "[$gitBranch ($repositoryName)]"
        } else {
            return "[$gitBranch]"
        }
    }
    return ""
}

function Prompt {
    $shellVersion = "PS v$($PSVersionTable.PSVersion.ToString())"
    $currentDirectory = Split-Path -leaf -path (Get-Location)
    $currentPath = (Get-Location).Path
    $relativePath = $currentPath.Replace($env:USERPROFILE, "")

    $gitInfo = Get-GitBranch -currentDirectory $currentDirectory

    Write-Host -NoNewline -ForegroundColor Green "$shellVersion"
    Write-Host -NoNewline " ~$relativePath" -ForegroundColor Yellow

    if ($gitInfo -ne "") {
        Write-Host -NoNewline -ForegroundColor Cyan " $gitInfo"
    }

    # Return a newline character to move the prompt to the next line
    return "`n"
}
