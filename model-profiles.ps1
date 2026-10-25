# Shared launcher defaults. Discover files each run so removed models disappear.
function Get-LocalModelProfiles {
    param([string]$ModelDirectory = (Join-Path $PSScriptRoot 'models'))
    $files = @(Get-ChildItem -LiteralPath $ModelDirectory -Filter '*.gguf' -File -Recurse |
        Sort-Object @{Expression={ if ($_.Name -eq 'google_gemma-4-E2B-it-Q4_K_M.gguf') { 0 } else { 1 } }}, FullName)
    foreach ($file in $files) {
        $key = $file.BaseName.ToLowerInvariant() -replace '[^a-z0-9-]', '-'
        $p = [pscustomobject]@{
            Key=$key; File=$file.FullName; Label=$file.BaseName; Alias=$key + '-local'
            Gpu='auto'; Threads=4; Batch=512; UBatch=128; KV='f16'
            Context=49152; Output=12288; Reserved=12288
            SingleTemplate=($file.Name -match 'gemma-4-')
            Reasoning='off'; ReasoningBudget=0; FlashAttention=$null
            Temperature=$null; TopP=$null; TopK=$null; MinP=$null
            SystemPromptFile=$null
        }
        switch -Regex ($file.Name) {
            '^qwen3\.5-4B-super-coder\.Q4_0\.gguf$' {
                $p.Label='Qwen3.5 4B Super Coder Q4_0'
                $p.Context=32768
                # Output includes both thinking and the final answer; retain the 12K allowance.
                $p.Reasoning='on'; $p.ReasoningBudget=-1; $p.FlashAttention='on'
                $p.Temperature=0.6; $p.TopP=0.95; $p.TopK=20; $p.MinP=0.0
                $p.SystemPromptFile=Join-Path $PSScriptRoot 'templates\super-coder-system.txt'
                break
            }
            '^google_gemma-4-E2B-it-Q4_K_M\.gguf$' {
                $p.Key='gemma'; $p.Alias='gemma-4-local'; $p.Label='Gemma 4 E2B Q4_K_M'; break
            }
            '^gemma-4-E4B-' { $p.Label='Gemma 4 E4B UD-IQ2_M'; break }
            '^Qwen3\.5-4B-Q4_K_M\.gguf$' {
                $p.Key='qwen35'; $p.Alias='qwen35-4b-local'; $p.Gpu='all'; $p.Threads=6
                $p.UBatch=256; $p.Context=32768; $p.Output=4096; $p.Reserved=8192; break
            }
            '^Qwen3-4B-Q4_K_M\.gguf$' {
                $p.Key='qwen3'; $p.Alias='qwen3-4b-local'; $p.Gpu='all'; $p.Threads=6
                $p.UBatch=256; $p.KV='q8_0'; $p.Context=16384; $p.Output=4096; $p.Reserved=4096; break
            }
        }
        $p
    }
}

# One argument builder keeps server, CLI and OpenCode inference settings aligned.
function Get-ModelInferenceArguments {
    param([Parameter(Mandatory=$true)]$Profile)
    '--reasoning'; [string]$Profile.Reasoning
    '--reasoning-budget'; [string]$Profile.ReasoningBudget
    if ($Profile.FlashAttention) { '--flash-attn'; $Profile.FlashAttention }
    foreach ($entry in @(
        @('--temp', $Profile.Temperature), @('--top-p', $Profile.TopP),
        @('--top-k', $Profile.TopK), @('--min-p', $Profile.MinP)
    )) {
        if ($null -ne $entry[1]) {
            $entry[0]
            ([double]$entry[1]).ToString([Globalization.CultureInfo]::InvariantCulture)
        }
    }
}
