#Requires -Version 7
param(
    [int]$Tail = 0,
    [switch]$Today,
    [string]$Session = "",
    [ValidateSet("table", "json")]
    [string]$Format = "table"
)

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$promptsLog  = Join-Path $projectRoot "logs\prompts.jsonl"

if (-not (Test-Path $promptsLog)) {
    Write-Host "No log file found at: $promptsLog"
    exit 0
}

$raw = Get-Content $promptsLog -Raw -Encoding UTF8
if (-not $raw -or -not $raw.Trim()) {
    Write-Host "Log file is empty."
    exit 0
}

$entries = $raw.Trim() -split "`n" | Where-Object { $_.Trim() } | ForEach-Object {
    try { $_ | ConvertFrom-Json } catch { }
}

if ($Today) {
    $todayStr = (Get-Date).ToString("yyyy-MM-dd")
    $entries  = @($entries) | Where-Object { $_.timestamp -like "$todayStr*" }
}
if ($Session) {
    $entries = @($entries) | Where-Object { $_.session_id -eq $Session }
}
if ($Tail -gt 0) {
    $entries = @($entries) | Select-Object -Last $Tail
}

if (-not $entries -or @($entries).Count -eq 0) {
    Write-Host "No matching entries."
    exit 0
}

if ($Format -eq "json") {
    @($entries) | ConvertTo-Json -Depth 5
} else {
    @($entries) | Format-Table -AutoSize `
        timestamp,
        approx_tokens,
        exact_tokens,
        @{ Name = "prompt (60 chars)"; Expression = { $_.prompt.Substring(0, [Math]::Min(60, $_.prompt.Length)) } }
}
