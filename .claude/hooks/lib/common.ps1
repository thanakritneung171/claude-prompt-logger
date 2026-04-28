function Write-LogEntry {
    param(
        [string]$Path,
        [hashtable]$Object
    )
    try {
        $dir = [System.IO.Path]::GetDirectoryName($Path)
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $line = $Object | ConvertTo-Json -Compress -Depth 10
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($line + "`n")
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
        } finally {
            $stream.Close()
        }
    } catch {
        # silently swallow to prevent hook failure
    }
}


function Get-ApproxTokens {
    param([string]$Text)
    return [int][math]::Ceiling($Text.Length / 3.5)
}

function Send-LogToWorker {
    param(
        [string]$Endpoint,
        [hashtable]$Body
    )
    try {
        # config.ps1 is 3 levels up from lib/ → project root → worker/config.ps1
        $configPath = Join-Path $PSScriptRoot "..\..\..\worker\config.ps1"
        if (-not (Test-Path $configPath)) { return }
        . $configPath
        if (-not $WORKER_URL) { return }

        $uri   = $WORKER_URL.TrimEnd('/') + $Endpoint
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Compress -Depth 10))

        $req = [System.Net.HttpWebRequest]::Create($uri)
        $req.Method        = "POST"
        $req.ContentType   = "application/json"
        $req.Timeout       = 5000
        $req.ContentLength = $bytes.Length
        $req.Headers.Add("X-Api-Key", $WORKER_API_KEY)

        $stream = $req.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
        $req.GetResponse().Close()
    } catch { }
}

function Invoke-LogRotation {
    param(
        [string]$Path,
        [int]$MaxBytes = 10485760
    )
    try {
        if (-not (Test-Path $Path)) { return }
        $size = (Get-Item $Path).Length
        if ($size -gt $MaxBytes) {
            $ts   = (Get-Date).ToString("yyyyMMdd_HHmmss")
            $dir  = [System.IO.Path]::GetDirectoryName($Path)
            $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
            $ext  = [System.IO.Path]::GetExtension($Path)
            $dest = Join-Path $dir "$name.$ts$ext"
            Move-Item -Path $Path -Destination $dest -Force
        }
    } catch {
        # silently swallow
    }
}
