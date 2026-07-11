param(
  [string]$DevEcoHome = 'C:\Program Files\Huawei\DevEco Studio',
  [string]$SdkHome = $env:DEVECO_SDK_HOME
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SdkHome)) {
  $SdkHome = Join-Path $DevEcoHome 'sdk'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$node = Join-Path $DevEcoHome 'tools\node\node.exe'
$linterRoot = Join-Path $DevEcoHome 'plugins\codelinter'
$linter = Join-Path $linterRoot 'index.js'
$installedSdk = Join-Path $SdkHome 'default'
$sdkManifestPath = Join-Path $installedSdk 'sdk-pkg.json'
foreach ($required in @($node, $linter, $sdkManifestPath)) {
  if (!(Test-Path -LiteralPath $required)) {
    Write-Error "Required DevEco tool is missing: $required"
    exit 1
  }
}

$sdkManifest = Get-Content -LiteralPath $sdkManifestPath -Raw | ConvertFrom-Json
$sdkLayout = Join-Path $env:TEMP 'eggclip-codelinter-sdk-layout'
$sdkLink = Join-Path $sdkLayout $sdkManifest.data.path
if (!(Test-Path -LiteralPath $sdkLayout)) {
  New-Item -ItemType Directory -Path $sdkLayout | Out-Null
}
if (!(Test-Path -LiteralPath $sdkLink)) {
  New-Item -ItemType Junction -Path $sdkLink -Target $installedSdk | Out-Null
}

$sourceRoot = Join-Path $projectRoot 'entry\src\main\ets'
$directories = ConvertTo-Json -InputObject @($sourceRoot) -Compress
$arguments = @(
  $linter,
  '--project', $projectRoot,
  '--dir', $directories,
  '--config', (Join-Path $projectRoot 'code-linter.json5'),
  '--sdkPath', $sdkLayout,
  '--sdkNumberVersion', "$($sdkManifest.data.apiVersion)",
  '--sdkStringVersion', "$($sdkManifest.data.platformVersion)",
  '--product', 'default',
  '--workdir', $linterRoot,
  '--logPath', (Join-Path $env:TEMP 'eggclip-codelinter.log'),
  '--inIde', 'false',
  '--language', 'cn'
)
$output = & $node @arguments 2>&1
$processExit = $LASTEXITCODE
$errors = [System.Collections.Generic.List[string]]::new()
$warningCount = 0

foreach ($line in $output) {
  try {
    $result = "$line" | ConvertFrom-Json
  } catch {
    continue
  }
  if ($null -ne $result.messageType -and ($result.messageType -eq -1 -or $result.messageType -eq 0)) {
    $errors.Add("$($result.content)")
  }
  if ($null -eq $result.defects) {
    continue
  }
  foreach ($defect in $result.defects) {
    $message = "$($result.filePath):$($defect.reportLine):$($defect.reportColumn) $($defect.ruleId) $($defect.description)"
    if ($defect.severity -eq 2) {
      $errors.Add($message)
    } elseif ($defect.severity -eq 1) {
      $warningCount += 1
    }
  }
}

if ($processExit -ne 0) {
  $errors.Add("Code Linter exited with code $processExit")
}
if ($errors.Count -gt 0) {
  $errors | ForEach-Object { Write-Host "  $_" }
  Write-Error "ArkTS lint failed with $($errors.Count) errors."
  exit 1
}
Write-Host "ArkTS lint passed ($warningCount advisory warnings)."
