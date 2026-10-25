# start-codex.ps1
# Starts Codex with approval prompts disabled and unrestricted sandbox access.
# Resumes the most recent Codex session.

$logDir = Join-Path $PSScriptRoot 'logs\codex'
[void][IO.Directory]::CreateDirectory($logDir)
# TOML literal strings preserve Windows paths, including spaces.
$logConfig = "log_dir='" + $logDir + "'"
Write-Host "Codex logs: $logDir"

codex `
    -c $logConfig `
    --ask-for-approval never `
    --sandbox danger-full-access `
    --disable apps `
    resume