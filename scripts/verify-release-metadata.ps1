$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$desktopPackage = Get-Content -LiteralPath (Join-Path $repoRoot 'desktop/package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$tauriConfig = Get-Content -LiteralPath (Join-Path $repoRoot 'desktop/src-tauri/tauri.conf.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$cargoManifest = Get-Content -LiteralPath (Join-Path $repoRoot 'desktop/src-tauri/Cargo.toml') -Raw -Encoding UTF8
$harmonyApp = Get-Content -LiteralPath (Join-Path $repoRoot 'harmony/AppScope/app.json5') -Raw -Encoding UTF8 | ConvertFrom-Json
$backupConfig = Get-Content -LiteralPath (Join-Path $repoRoot 'harmony/entry/src/main/resources/base/profile/backup_config.json') -Raw -Encoding UTF8 | ConvertFrom-Json

$cargoVersionMatch = [regex]::Match($cargoManifest, '(?m)^version\s*=\s*"([^"]+)"\s*$')
if (-not $cargoVersionMatch.Success) {
  throw 'Unable to read desktop Cargo package version.'
}

$versions = @(
  [string]$desktopPackage.version,
  [string]$tauriConfig.version,
  [string]$cargoVersionMatch.Groups[1].Value,
  [string]$harmonyApp.app.versionName
)
if (@($versions | Select-Object -Unique).Count -ne 1) {
  throw 'Desktop and HarmonyOS release versions are not aligned.'
}
if ($tauriConfig.identifier -ne 'com.eggclip.desktop' -or $harmonyApp.app.bundleName -ne 'com.eggclip.app') {
  throw 'Release application identifiers changed unexpectedly.'
}
if (@($tauriConfig.bundle.targets).Count -ne 1 -or $tauriConfig.bundle.targets[0] -ne 'nsis') {
  throw 'Desktop v1 must produce only the NSIS bundle.'
}
if ([int64]$harmonyApp.app.versionCode -le 0 -or [int64]$harmonyApp.app.buildVersion -le 0) {
  throw 'HarmonyOS versionCode and buildVersion must be positive.'
}
if ($backupConfig.allowToBackupRestore -ne $false) {
  throw 'HarmonyOS backup must stay disabled because HUKS key references cannot be restored independently.'
}

Write-Output "Release metadata check passed for EggClip $($versions[0])."
