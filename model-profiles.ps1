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
        }
        switch -Regex ($file.Name) {
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
