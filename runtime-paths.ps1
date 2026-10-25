# Isolated official CUDA runtime for GGUFs containing Qwen3.5 MTP heads.
function Get-SuperCoderRuntimeDirectory {
    Join-Path $PSScriptRoot 'bin\runtimes\b11883-cuda12.4'
}

function Get-ModelExecutable {
    param($Profile, [ValidateSet('server','cli')][string]$Engine)
    $dir = Join-Path $PSScriptRoot 'bin'
    if ($Profile.UseMtpRuntime) { $dir = Get-SuperCoderRuntimeDirectory }
    $path = Join-Path $dir "llama-$Engine.exe"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required model runtime is missing: $path" }
    return $path
}

function Test-WorkspaceServerExecutable {
    param([string]$Path)
    foreach ($allowed in @((Join-Path $PSScriptRoot 'bin\llama-server.exe'), (Join-Path (Get-SuperCoderRuntimeDirectory) 'llama-server.exe'))) {
        if ([string]::Equals($Path, $allowed, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}
