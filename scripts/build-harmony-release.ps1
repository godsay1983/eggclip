$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$harmonyRoot = Join-Path $repoRoot 'harmony'
$env:JAVA_HOME = 'C:\Program Files\Huawei\DevEco Studio\jbr'
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"

& (Join-Path $PSScriptRoot 'verify-release-metadata.ps1')
if (-not $?) { exit 1 }
& (Join-Path $PSScriptRoot 'check-harmony-color-contrast.ps1')
if (-not $?) { exit 1 }
& (Join-Path $PSScriptRoot 'check-harmony-market-icon.ps1')
if (-not $?) { exit 1 }
& (Join-Path $PSScriptRoot 'check-harmony-navigation-layout.ps1')
if (-not $?) { exit 1 }
& (Join-Path $PSScriptRoot 'check-harmony-log-privacy.ps1')
if (-not $?) { exit 1 }

Push-Location $harmonyRoot
try {
  & 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' test --no-daemon
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  & 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --mode module -p product=default -p buildMode=release --no-daemon
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Pop-Location
}

$hap = Join-Path $harmonyRoot 'entry/build/default/outputs/default/entry-default-unsigned.hap'
& (Join-Path $PSScriptRoot 'release-safety-check.ps1') -PackagePaths $hap
if (-not $?) { exit 1 }
Write-Output "HarmonyOS unsigned HAP: $hap"
Write-Warning 'Use DevEco Studio or CI secrets to produce and verify the formally signed HAP; never copy signing material into the shared build profile.'
