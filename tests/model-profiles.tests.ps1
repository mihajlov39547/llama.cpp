$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'model-profiles.ps1')
function Check($Condition,$Message) { if (-not $Condition) { throw $Message }; Write-Host "PASS: $Message" }
function Check-Argument($Arguments,$Flag,$Value) {
    $index=[array]::IndexOf($Arguments,$Flag)
    Check ($index -ge 0 -and $Arguments[$index+1] -ceq $Value) "$Flag = $Value"
}
$profiles=@(Get-LocalModelProfiles)
$p=$profiles | Where-Object { (Split-Path -Leaf $_.File) -eq 'qwen3.5-4B-super-coder.Q4_0.gguf' }
Check ($null -ne $p -and $p.Context -eq 32768 -and $p.Output -eq 12288 -and $p.Reserved -eq 12288) 'Super Coder 32K/12K profile'
Check (-not $p.SingleTemplate -and (Test-Path -LiteralPath $p.SystemPromptFile)) 'Embedded Qwen template and coding prompt'
$culture=[Threading.Thread]::CurrentThread.CurrentCulture
try {
    [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('hu-HU')
    $inference=@(Get-ModelInferenceArguments $p)
    Check-Argument $inference '--temp' '0.6'
    Check-Argument $inference '--top-p' '0.95'
    Check-Argument $inference '--top-k' '20'
    Check-Argument $inference '--min-p' '0'
} finally { [Threading.Thread]::CurrentThread.CurrentCulture=$culture }

# Evaluate only argument construction, never launch or stop a model.
$selectedModel=Get-Item -LiteralPath $p.File
$modelPath=$p.File; $gpuLayers=$p.Gpu; $cpuThreads=$p.Threads
$contextSize=$p.Context; $context=$p.Context; $outputLimit=$p.Output; $reserved=$p.Reserved
$batchSize=$p.Batch; $microBatchSize=$p.UBatch; $cacheTypeK=$p.KV; $cacheTypeV=$p.KV
$chatTemplateArguments=@('--jinja'); $apiOnly=$true; $hostAddress='127.0.0.1'; $port=8080
$cliLog=Join-Path $root 'logs\test-cli.log'; $serverUrl='http://127.0.0.1:8080'
foreach ($name in @('start-llama-cli.ps1','start-llama-server.ps1','start-opencode.ps1')) {
    $source=Get-Content -LiteralPath (Join-Path $root $name) -Raw
    $variable=if ($name -eq 'start-opencode.ps1') { 'serverArgs' } else { 'arguments' }
    $start=$source.IndexOf('$'+$variable+' = @(')
    $end=$source.IndexOf('Write-Host', $start)
    . ([scriptblock]::Create($source.Substring($start,$end-$start)))
    $built=(Get-Variable -Name $variable).Value
    Check-Argument $built '--reasoning' 'on'
    Check-Argument $built '--reasoning-budget' '-1'
    Check-Argument $built '--flash-attn' 'on'
    Check-Argument $built '-c' '32768'
    Check-Argument $built '--temp' '0.6'
    Check (@($built | Where-Object { $_ -eq '--reasoning' }).Count -eq 1) "$name has one reasoning setting"
    Check (-not ($built -contains '--chat-template-file')) "$name uses embedded template"
    if ($name -eq 'start-llama-cli.ps1') { Check-Argument $built '--system-prompt-file' $p.SystemPromptFile }
}
$source=Get-Content -LiteralPath (Join-Path $root 'start-opencode.ps1') -Raw
$start=$source.IndexOf('$config = [ordered]@{'); $end=$source.IndexOf('$json =', $start)
. ([scriptblock]::Create($source.Substring($start,$end-$start)))
Check ($config.agent.build.temperature -eq 0.6 -and $config.agent.plan.top_p -eq 0.95) 'OpenCode build/plan sampling'
Check ($config.instructions[0] -eq $p.SystemPromptFile -and $config.provider['local-llama'].models[$p.Alias].reasoning) 'OpenCode instructions and reasoning capability'
$gemma=$profiles | Where-Object Key -eq 'gemma'
Check ($gemma.Context -eq 49152 -and $gemma.SingleTemplate -and $null -eq $gemma.Temperature) 'Gemma settings preserved'
Check-Argument @(Get-ModelInferenceArguments $gemma) '--reasoning' 'off'
