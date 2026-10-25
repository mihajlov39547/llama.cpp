$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'server-control.ps1')
function Check($Condition, $Message) { if (-not $Condition) { throw $Message }; Write-Output "PASS: $Message" }
Check (Test-WorkspaceServerExecutable (Join-Path (Get-SuperCoderRuntimeDirectory) 'llama-server.exe')) 'Isolated Super Coder runtime is manageable'
Check (-not (Test-WorkspaceServerExecutable 'C:\other\llama-server.exe')) 'Other installations remain outside manager control'
$metrics = ConvertFrom-ServerMetrics @'
# TYPE llamacpp:tokens_predicted_total counter
llamacpp:tokens_predicted_total 1.25e3
llamacpp:requests_processing 0
llamacpp:predicted_tokens_seconds 60.64
llamacpp:spec_decode_num_accepted_tokens_per_pos_total{position="0"} 2
llamacpp:spec_decode_num_accepted_tokens_per_pos_total{position="1"} 3
'@
Check ($metrics['llamacpp:tokens_predicted_total'] -eq 1250) 'Prometheus exponent parsing'
Check ($metrics['llamacpp:requests_processing'] -eq 0) 'Zero is a valid metric'
Check ($metrics['llamacpp:spec_decode_num_accepted_tokens_per_pos_total'] -eq 5) 'Labeled series are aggregated'
Check ((ConvertFrom-ServerMetrics '').Count -eq 0) 'Disabled metrics are unavailable, not invented totals'

$launch=Get-ServerLaunchOptions '"C:\llama.cpp\bin\llama-server.exe" --reasoning=on --reasoning-budget -1 -n 12288 -ctk f16 --cache-type-v q8_0 -fa on --cache-ram 0 --cache-prompt --no-cache-prompt --chat-template-file "C:\templates with spaces\coding.jinja" --api-key "secret --reasoning off"'
Check ($launch['--reasoning'] -eq 'on' -and $launch['--reasoning-budget'] -eq '-1') 'Equals syntax and negative reasoning budget parse correctly'
Check ($launch['--cache-prompt'] -eq 'off' -and $launch['--cache-ram'] -eq '0') 'Disabled cache and zero cache RAM are preserved'
Check ($launch['--chat-template-file'] -eq 'C:\templates with spaces\coding.jinja' -and $launch['--flash-attn'] -eq 'on') 'Quoted paths and flag aliases parse correctly'
$props=[pscustomobject]@{
    default_generation_settings=[pscustomobject]@{params=[pscustomobject]@{n_predict=-1;reasoning_format='deepseek';reasoning_in_content=$false}}
    chat_template_caps=[pscustomobject]@{supports_tools=$true;supports_tool_calls=$true}
}
$lines=(Get-ServerInferenceLines $launch $props) -join "`n"
Check ($lines -match 'no separate thinking cap' -and $lines -match 'Launch output allowance: 12288') 'Launch thinking and total output limits shown separately'
Check ($lines -match 'in content=false, budget=unavailable' -and $lines -match 'n_predict=-1') 'API false, missing budget and unlimited output remain distinct'
Check ($lines -notmatch 'secret') 'Status does not disclose unrelated sensitive command arguments'
$unset=(Get-ServerInferenceLines @{} $null) -join "`n"
Check ($unset -match 'not set \(runtime/model default\)' -and $unset -match 'budget=unavailable') 'Missing API and launch fields do not invent disabled settings'

& {
    function Get-Process { param($Id,$ErrorAction) throw 'Fixture: process counters unavailable' }
    function Read-ServerEndpoint {
        param($Port,$Path,[switch]$Text)
        switch ($Path) {
            'health' { [pscustomobject]@{status='ok'} }
            'props' { $props }
            'slots' { [pscustomobject]@{id=0;is_processing=$false;tokens_cached=0;n_past=20;n_prompt_tokens=25;params=[pscustomobject]@{cache_prompt=$false;reasoning_budget=0;n_predict=100}} }
            'metrics' { "llamacpp:kv_cache_tokens 0`nllamacpp:kv_cache_usage_ratio 0" }
        }
    }
    $server=[pscustomobject]@{Name='llama-server.exe';ProcessId=0;ExecutablePath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'bin\llama-server.exe');CreationDate=[datetime]::MaxValue;CommandLine='llama-server.exe --reasoning off --reasoning-budget 0'}
    $snapshot=(Get-ServerStatusLines $server 65001) -join "`n"
    Check ($snapshot -match 'Live KV cache metrics: tokens=0 \| Usage: 0[.,]0%') 'Live zero KV tokens/usage are not treated as missing'
    Check ($snapshot -match 'thinking budget=0, cache_prompt=false' -and $snapshot -match 'cached=0, past=20, prompt=25') 'Per-task cache and reasoning values displayed'
}

# These tests replace all destructive operations; no real server is stopped.
& {
    $exe = Join-Path (Split-Path -Parent $PSScriptRoot) 'bin\llama-server.exe'
    $created = [datetime]::UtcNow
    $created = $created.AddTicks(-($created.Ticks % 10))
    $expected = [pscustomobject]@{ProcessId=123; CreationDate=$created; ExecutablePath=$exe}
    $script:testCurrent = $expected
    function Get-LocalServerProcess { param($Port) $script:testCurrent }
    Check ((Assert-LocalServerIdentity $expected 8080).ProcessId -eq 123) 'Exact executable, port owner, PID and creation time accepted'
    foreach ($other in @(
        [pscustomobject]@{ProcessId=124; CreationDate=$created; ExecutablePath=$exe},
        [pscustomobject]@{ProcessId=123; CreationDate=$created.AddSeconds(1); ExecutablePath=$exe},
        [pscustomobject]@{ProcessId=123; CreationDate=$created; ExecutablePath='C:\other\llama-server.exe'}
    )) {
        $script:testCurrent = $other
        $blocked = $false
        try { $null = Assert-LocalServerIdentity $expected 8080 } catch { $blocked=$true }
        Check $blocked 'Changed PID, recycled PID or foreign executable rejected'
    }
    $script:testCurrent = $expected
    $script:killed = $false
    $fake = [pscustomobject]@{Handle=1; StartTime=$created.AddTicks(4)}
    $fake | Add-Member ScriptMethod Kill { $script:killed=$true }
    $fake | Add-Member ScriptMethod WaitForExit { param($Milliseconds) return $true }
    function Get-Process { param($Id, $ErrorAction) $fake }
    Stop-LocalServer $expected 8080
    Check $script:killed 'Stop handles CIM microsecond precision and waits for exit'
    $script:killed=$false
    $fake.StartTime=$created.AddSeconds(1)
    try { Stop-LocalServer $expected 8080 } catch { }
    Check (-not $script:killed) 'Process handle with different start time cannot be killed'
}

& {
    $server = [pscustomobject]@{ProcessId=123; ExecutablePath='C:\llama.cpp\bin\llama-server.exe'; CommandLine='"C:\llama.cpp\bin\llama-server.exe" -m "C:\models with spaces\model.gguf" --no-slots --port 8080 --no-webui'}
    $script:didStop=$false; $script:launched=$false
    function Assert-LocalServerIdentity { param($Expected,$Port) $Expected }
    function Stop-LocalServer { param($Server,$Port) $script:didStop=$true }
    function Get-LocalServerProcess { param($Port) if ($script:launched) { [pscustomobject]@{ProcessId=456} } }
    function Start-Process {
        param($FilePath,$ArgumentList,$WorkingDirectory,$WindowStyle,$RedirectStandardOutput,$RedirectStandardError,[switch]$PassThru)
        Check $script:didStop 'Old server is stopped before starting replacement'
        Check ($ArgumentList -like '*-m "C:\models with spaces\model.gguf"*') 'Restart preserves native argument quoting'
        Check ($ArgumentList -match '--metrics' -and $ArgumentList -match '--slots' -and $ArgumentList -notmatch '--no-slots') 'Restart enables metrics and slot monitoring'
        Check ($WindowStyle -eq 'Hidden' -and $RedirectStandardError -like '*\logs\*') 'Restart logs stay in logs and console stays hidden'
        $script:launched=$true
        $fake=[pscustomobject]@{Id=456;HasExited=$false}
        $fake | Add-Member ScriptMethod Refresh { }
        return $fake
    }
    function Save-ServerLogRecord { param($Process,$Port,$Stdout,$Stderr) }
    function Read-ServerEndpoint { param($Port,$Path) [pscustomobject]@{status='ok'} }
    # Suppress test assertions from the fake Start-Process success stream.
    function Check($Condition,$Message) { if (-not $Condition) { throw $Message }; Write-Host "PASS: $Message" }
    Restart-LocalServer $server 8080
}
