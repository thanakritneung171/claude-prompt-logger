#Requires -Version 7
$ErrorActionPreference = "Continue"

$ScriptDir    = $PSScriptRoot
$projectRoot  = Resolve-Path (Join-Path $ScriptDir "..")
$hooksDir     = Join-Path $projectRoot ".claude\hooks"
$fixturesDir  = Join-Path $ScriptDir "fixtures"
$logsDir      = Join-Path $projectRoot "logs"

$pwsh            = (Get-Command pwsh -ErrorAction Stop).Source
$logPromptScript = Join-Path $hooksDir "log_prompt.ps1"
$logUsageScript  = Join-Path $hooksDir "log_usage.ps1"
$promptsLog      = Join-Path $logsDir "prompts.jsonl"
$usageLog        = Join-Path $logsDir "usage.jsonl"
$mockPayload     = Join-Path $fixturesDir "mock_prompt_payload.json"
$mockTranscript  = Join-Path $fixturesDir "mock_transcript.jsonl"

New-Item -ItemType Directory -Path $logsDir -Force | Out-Null

$passCount  = 0
$failList   = @()

function Assert-True {
    param([string]$Name, [scriptblock]$Condition)
    try {
        if (& $Condition) {
            Write-Host "  PASS: $Name" -ForegroundColor Green
            $script:passCount++
        } else {
            Write-Host "  FAIL: $Name" -ForegroundColor Red
            $script:failList += $Name
        }
    } catch {
        Write-Host "  FAIL: $Name (exception: $_)" -ForegroundColor Red
        $script:failList += $Name
    }
}

# Returns an array of non-empty lines from a JSONL file
function Read-LogLines {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    $raw = Get-Content $Path -Raw -Encoding UTF8
    if (-not $raw -or -not $raw.Trim()) { return @() }
    # @() on the caller side ensures array; filter empty lines
    $lines = $raw.Trim() -split "`n" | Where-Object { $_.Trim() }
    return @($lines)
}

function Get-Payload {
    $obj = Get-Content $mockPayload -Raw | ConvertFrom-Json
    $obj.transcript_path = $mockTranscript
    return $obj | ConvertTo-Json -Compress
}

# ── Test 1: log_prompt writes entry with all required fields ──────────────
Write-Host "`nTest 1: log_prompt.ps1 writes entry with all required fields"
$before1 = @(Read-LogLines $promptsLog).Count
Get-Payload | & $pwsh -NoProfile -File $logPromptScript
$lines1 = @(Read-LogLines $promptsLog) # force array with @()
$after1Count = $lines1.Count

$lastEntry1 = $null
if ($after1Count -gt 0) {
    try { $lastEntry1 = $lines1[$after1Count - 1] | ConvertFrom-Json } catch { }
}

Assert-True "entry has all required fields (timestamp, session_id, char_count, approx_tokens, prompt)" {
    $after1Count -gt $before1 -and
    $null -ne $lastEntry1 -and
    [bool]$lastEntry1.timestamp -and
    $null -ne $lastEntry1.PSObject.Properties["session_id"] -and
    $null -ne $lastEntry1.PSObject.Properties["char_count"] -and
    $null -ne $lastEntry1.PSObject.Properties["approx_tokens"] -and
    $null -ne $lastEntry1.PSObject.Properties["prompt"]
}

# ── Test 2: log_usage reads transcript and writes correct token counts ─────
Write-Host "`nTest 2: log_usage.ps1 writes correct token counts from mock transcript"
$usagePayload = @{ session_id = "test-session-001"; transcript_path = [string]$mockTranscript } | ConvertTo-Json -Compress
$before3 = @(Read-LogLines $usageLog).Count
$usagePayload | & $pwsh -NoProfile -File $logUsageScript
$lines3      = @(Read-LogLines $usageLog)
$after3Count = $lines3.Count

$lastUsage3 = $null
if ($after3Count -gt 0) {
    try { $lastUsage3 = $lines3[$after3Count - 1] | ConvertFrom-Json } catch { }
}

Assert-True "usage entry has input_tokens=1500, output_tokens=250, cache_read=8000" {
    $after3Count -gt $before3 -and
    $null -ne $lastUsage3 -and
    $lastUsage3.input_tokens -eq 1500 -and
    $lastUsage3.output_tokens -eq 250 -and
    $lastUsage3.cache_read_input_tokens -eq 8000
}

# ── Test 3: rotation creates archive when file exceeds 10 MB ──────────────
Write-Host "`nTest 3: rotation creates prompts.<timestamp>.jsonl archive"
Remove-Item $promptsLog -ErrorAction SilentlyContinue
$enc    = [System.Text.Encoding]::UTF8
$chunk  = $enc.GetBytes(("x" * 1000) + "`n")
$stream = [System.IO.File]::Open($promptsLog, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
for ($i = 0; $i -lt 11000; $i++) { $stream.Write($chunk, 0, $chunk.Length) }
$stream.Close()

$beforeArchives = @(Get-ChildItem $logsDir -Filter "prompts.????????_??????.jsonl" -ErrorAction SilentlyContinue).Count
Get-Payload | & $pwsh -NoProfile -File $logPromptScript
$afterArchives = @(Get-ChildItem $logsDir -Filter "prompts.????????_??????.jsonl" -ErrorAction SilentlyContinue).Count

Assert-True "archive file prompts.<timestamp>.jsonl was created" {
    $afterArchives -gt $beforeArchives
}

# ── Test 4: new prompts.jsonl starts fresh after rotation ─────────────────
Write-Host "`nTest 4: new prompts.jsonl is small after rotation"
Assert-True "prompts.jsonl is under 1 MB after rotation" {
    (Test-Path $promptsLog) -and (Get-Item $promptsLog).Length -lt 1MB
}

# ── Summary ────────────────────────────────────────────────────────────────
$total = 4
Write-Host ""
if ($failList.Count -eq 0) {
    Write-Host "PASS $passCount/$total" -ForegroundColor Green
} else {
    Write-Host "PASS $passCount/$total" -ForegroundColor Yellow
    foreach ($f in $failList) {
        Write-Host "  FAIL: $f" -ForegroundColor Red
    }
    exit 1
}
