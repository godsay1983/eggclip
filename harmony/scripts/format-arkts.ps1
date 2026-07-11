param(
  [switch]$Fix
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceRoots = @(
  (Join-Path $projectRoot 'entry\src\main\ets'),
  (Join-Path $projectRoot 'entry\src\test')
)
$files = $sourceRoots |
  Where-Object { Test-Path $_ } |
  ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -File -Filter '*.ets' }
$changed = [System.Collections.Generic.List[string]]::new()
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

foreach ($file in $files) {
  $raw = [System.IO.File]::ReadAllText($file.FullName)
  $normalized = $raw.Replace("`r`n", "`n").Replace("`r", "`n")
  $lines = $normalized.Split("`n") | ForEach-Object { $_.TrimEnd() }
  $normalized = ($lines -join "`n").TrimEnd([char[]]"`n") + "`n"
  if ($raw -ceq $normalized) {
    continue
  }
  $changed.Add($file.FullName.Substring($projectRoot.Length + 1))
  if ($Fix) {
    [System.IO.File]::WriteAllText($file.FullName, $normalized, $utf8NoBom)
  }
}

if ($changed.Count -eq 0) {
  Write-Host 'ArkTS format check passed.'
  exit 0
}

if ($Fix) {
  Write-Host "Normalized $($changed.Count) ArkTS files:"
  $changed | ForEach-Object { Write-Host "  $_" }
  exit 0
}

$changed | ForEach-Object { Write-Host "  $_" }
Write-Error "ArkTS format check failed for $($changed.Count) files. Run scripts\format-arkts.ps1 -Fix."
exit 1
