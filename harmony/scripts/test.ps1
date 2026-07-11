param(
  [string]$DevEcoHome = 'C:\Program Files\Huawei\DevEco Studio'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$env:JAVA_HOME = Join-Path $DevEcoHome 'jbr'
if ([string]::IsNullOrWhiteSpace($env:DEVECO_SDK_HOME)) {
  $env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk'
}
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
$hvigor = Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.bat'
Push-Location $projectRoot
try {
  & $hvigor test --no-daemon --type-check
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
} finally {
  Pop-Location
}

