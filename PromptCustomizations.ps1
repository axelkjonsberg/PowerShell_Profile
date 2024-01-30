function Get-GitBranch {
    $gitBranch = & git rev-parse --abbrev-ref HEAD 2>$null
    if ($gitBranch) {
        return "[$gitBranch]"
    }
    return ""
}

function Prompt {
    $currentPath = Split-Path -leaf -path (Get-Location)
    $gitInfo = Get-GitBranch

    Write-Host -NoNewline -ForegroundColor Green "PS – "

    Write-Host -NoNewline -ForegroundColor Yellow "$currentPath"

    if ($gitInfo -ne "") {
        Write-Host -NoNewline -ForegroundColor Green " – "
        Write-Host -NoNewline -ForegroundColor Cyan "$gitInfo"
    }

    Write-Host -NoNewline -ForegroundColor Green " >"

    # Return an empty string to prevent double prompt
    return " "
}
