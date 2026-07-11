param(
  [string]$DevEcoHome = 'C:\Program Files\Huawei\DevEco Studio'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'format-arkts.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot 'lint-arkts.ps1') -DevEcoHome $DevEcoHome
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot 'test.ps1') -DevEcoHome $DevEcoHome
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$env:JAVA_HOME = Join-Path $DevEcoHome 'jbr'
if ([string]::IsNullOrWhiteSpace($env:DEVECO_SDK_HOME)) {
  $env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk'
}
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
$hvigor = Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.bat'
Push-Location $projectRoot
try {
  & $hvigor assembleHap --no-daemon --type-check
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Pop-Location
}
Write-Host 'Harmony verification passed: format, lint, test, assembleHap.'

