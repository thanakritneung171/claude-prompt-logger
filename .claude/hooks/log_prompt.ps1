$ErrorActionPreference = "SilentlyContinue"
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$libPath     = Join-Path $PSScriptRoot "lib\common.ps1"
$logFile     = Join-Path $projectRoot "logs\prompts.jsonl"
$summaryFile = Join-Path $projectRoot "logs\summary.log"

. $libPath

try {
    $raw = [System.Console]::In.ReadToEnd()
    if (-not $raw.Trim()) { exit 0 }

    $payload = $raw | ConvertFrom-Json

    $prompt     = if ($null -ne $payload.prompt)        { [string]$payload.prompt }        else { "" }
    $sessionId  = if ($null -ne $payload.session_id)    { [string]$payload.session_id }    else { "" }
    $cwd        = if ($null -ne $payload.cwd)           { [string]$payload.cwd }           else { "" }

    Invoke-LogRotation -Path $logFile

    $approxTokens = Get-ApproxTokens -Text $prompt

    $entry = [ordered]@{
        timestamp     = (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz")
        session_id    = $sessionId
        cwd           = $cwd
        char_count    = $prompt.Length
        approx_tokens = $approxTokens
        prompt        = $prompt
    }

    Write-LogEntry -Path $logFile -Object $entry
    Send-LogToWorker -Endpoint "/api/prompt" -Body $entry

} catch {
    try {
        $errMsg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] log_prompt error: $_`n"
        [System.IO.File]::AppendAllText($summaryFile, $errMsg, [System.Text.Encoding]::UTF8)
    } catch { }
}

exit 0
