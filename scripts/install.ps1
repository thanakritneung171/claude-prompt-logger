#Requires -Version 7
$ErrorActionPreference = "Stop"

# 1. Verify PowerShell 7.x
$ver = $PSVersionTable.PSVersion
if ($ver.Major -lt 7) {
    Write-Error "PowerShell 7.x required. Current version: $($ver.ToString())"
    exit 1
}
Write-Host "PowerShell $($ver.ToString()) detected." -ForegroundColor Green

# 2. Resolve paths
$projectRoot     = Resolve-Path (Join-Path $PSScriptRoot "..")
$pwshPath        = (Get-Command pwsh).Source
$logPromptPath   = Join-Path $projectRoot ".claude\hooks\log_prompt.ps1"
$logUsagePath    = Join-Path $projectRoot ".claude\hooks\log_usage.ps1"
$settingsPath    = Join-Path $projectRoot ".claude\settings.local.json"
$logsDir         = Join-Path $projectRoot "logs"

# 3. Create logs/ if not present
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    Write-Host "Created: $logsDir" -ForegroundColor Cyan
}

# 4. Build hook command strings (paths quoted to handle spaces)
$cmdPrompt = "`"$pwshPath`" -NoProfile -File `"$logPromptPath`""
$cmdUsage  = "`"$pwshPath`" -NoProfile -File `"$logUsagePath`""

$newUserPromptSubmit = @(@{ hooks = @(@{ type = "command"; command = $cmdPrompt }) })
$newStop             = @(@{ hooks = @(@{ type = "command"; command = $cmdUsage  }) })

# 5. Merge with existing settings or create fresh
if (Test-Path $settingsPath) {
    $backupPath = "$settingsPath.bak"
    Copy-Item $settingsPath $backupPath -Force
    Write-Host "Backed up existing settings to: $backupPath" -ForegroundColor Yellow

    try {
        $existing = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    } catch {
        $existing = @{}
    }

    if (-not $existing.ContainsKey("hooks")) {
        $existing["hooks"] = @{}
    }
    if (-not $existing["hooks"].ContainsKey("UserPromptSubmit")) {
        $existing["hooks"]["UserPromptSubmit"] = $newUserPromptSubmit
    }
    if (-not $existing["hooks"].ContainsKey("Stop")) {
        $existing["hooks"]["Stop"] = $newStop
    }
    $outputJson = $existing | ConvertTo-Json -Depth 10
} else {
    $settings = @{
        hooks = @{
            UserPromptSubmit = $newUserPromptSubmit
            Stop             = $newStop
        }
    }
    $outputJson = $settings | ConvertTo-Json -Depth 10
}

# 6. Write settings UTF-8 no BOM
[System.IO.File]::WriteAllText($settingsPath, $outputJson, [System.Text.UTF8Encoding]::new($false))
Write-Host "Settings written: $settingsPath" -ForegroundColor Green

# 7. Print log file paths
Write-Host ""
Write-Host "Log files:" -ForegroundColor Cyan
Write-Host "  Prompts : $(Join-Path $logsDir 'prompts.jsonl')"
Write-Host "  Usage   : $(Join-Path $logsDir 'usage.jsonl')"
Write-Host "  Summary : $(Join-Path $logsDir 'summary.log')"
Write-Host ""
Write-Host "Installation complete. Restart Claude Code to activate hooks." -ForegroundColor Green
