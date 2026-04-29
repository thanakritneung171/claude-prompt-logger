$ErrorActionPreference = "SilentlyContinue"
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$projectRoot   = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$libPath       = Join-Path $PSScriptRoot "lib\common.ps1"
$promptsFile   = Join-Path $projectRoot "logs\prompts.jsonl"

. $libPath

if ($env:HOOK_PIPE_CTX -eq "1") { exit 0 }

try {
    $raw = [System.Console]::In.ReadToEnd()
    if (-not $raw.Trim()) { exit 0 }

    $payload = $raw | ConvertFrom-Json

    $sessionId      = if ($null -ne $payload.session_id)      { [string]$payload.session_id }      else { "" }
    $transcriptPath = if ($null -ne $payload.transcript_path)  { [string]$payload.transcript_path } else { "" }

    if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) { exit 0 }

    $lastUsage = $null
    $lastModel = ""
    foreach ($rawLine in [System.IO.File]::ReadAllLines($transcriptPath, [System.Text.Encoding]::UTF8)) {
        try {
            $line = $rawLine | ConvertFrom-Json
            if ($line.type -eq "assistant" -and $null -ne $line.message.usage) {
                $lastUsage = $line.message.usage
                $lastModel = if ($line.message.model) { [string]$line.message.model } else { "" }
            }
        } catch { }
    }

    if (-not $lastUsage) { exit 0 }

    $inputTokens  = [int]($lastUsage.input_tokens                  ?? 0)
    $outputTokens = [int]($lastUsage.output_tokens                 ?? 0)
    $cacheCreate  = [int]($lastUsage.cache_creation_input_tokens   ?? 0)
    $cacheRead    = [int]($lastUsage.cache_read_input_tokens       ?? 0)
    $total        = $inputTokens + $outputTokens + $cacheCreate + $cacheRead

    $entry = [ordered]@{
        timestamp                   = (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz")
        session_id                  = $sessionId
        model                       = $lastModel
        input_tokens                = $inputTokens
        output_tokens               = $outputTokens
        cache_creation_input_tokens = $cacheCreate
        cache_read_input_tokens     = $cacheRead
        total_tokens                = $total
    }

    Send-LogToWorker -Endpoint "/api/usage" -Body $entry

    # Build combined record: last prompt for this session + token usage
    $lastPrompt = ""
    if (Test-Path $promptsFile) {
        $promptLines = [System.IO.File]::ReadAllLines($promptsFile, [System.Text.Encoding]::UTF8)
        for ($i = $promptLines.Length - 1; $i -ge 0; $i--) {
            $pl = $promptLines[$i].Trim()
            if (-not $pl) { continue }
            try {
                $pe = $pl | ConvertFrom-Json
                if ($pe.session_id -eq $sessionId) { $lastPrompt = [string]$pe.prompt; break }
            } catch { }
        }
    }

    # Skip model-switch phantom calls: no user prompt + minimal input tokens
    if (-not $lastPrompt -and $inputTokens -le 5) { exit 0 }

} catch {
}

exit 0
