# push_models.ps1 — Push transpiled model bundles to the Android device.
# Run AFTER Docker transpile completes (each model folder must have components/).
# Usage: .\push_models.ps1

$ADB = "$env:USERPROFILE\AppData\Local\Android\Sdk\platform-tools\adb.exe"
$BASE = "/storage/emulated/0/Android/data/com.example.my_agent_app/files/models"
$WEIGHTS = "D:\cactus_src\weights"

# model-id (folder on device) → weight folder name in D:\cactus_src\weights\
$MAP = @{
  "lfm2-350m"       = "lfm2-350m-cq4"
  "lfm2.5-350m"     = "lfm2.5-350m-cq4"
  "lfm2-700m"       = "lfm2-vl-700m-cq4"   # VL variant — text mode in paper
  "lfm2-1.2b"       = "lfm2-1.2b-cq4"
  "qwen3-0.6"       = "qwen3-0.6b-cq4"
  "qwen3-1.7"       = "qwen3-1.7b-cq4"
  "qwen3.5-0.8"     = "qwen3.5-0.8b-cq4"
  "qwen3.5-2b"      = "qwen3.5-2b-cq4"
  "lfm2-audio-350m" = "lfm2-audio-350m-cq4"
  "gemma-4-1b"      = "gemma-4-1b-it-cq4"
  "lfm2-vl-450m"    = "lfm2-vl-450m-cq4"   # placeholder, already on device
}

Write-Host "Checking adb device..."
& $ADB devices

foreach ($id in $MAP.Keys | Sort-Object) {
  $src = Join-Path $WEIGHTS $MAP[$id]
  $dst = "$BASE/$id"

  # Verify transpile completed (components/ must exist)
  if (-not (Test-Path "$src\components")) {
    Write-Host "SKIP $id — components/ missing in $src (transpile not done?)"
    continue
  }

  Write-Host ""
  Write-Host "Pushing $id ($($MAP[$id]))..."
  & $ADB push $src $dst
  Write-Host "Done: $id"
}

Write-Host ""
Write-Host "=== All pushes complete ==="
Write-Host "Open the app and test each model."
