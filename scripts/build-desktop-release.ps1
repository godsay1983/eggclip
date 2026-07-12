$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$desktopRoot = Join-Path $repoRoot 'desktop'

& (Join-Path $PSScriptRoot 'verify-release-metadata.ps1')
if (-not $?) { exit 1 }

Push-Location $desktopRoot
try {
  & pnpm release:check
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  & pnpm tauri build --bundles nsis
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Pop-Location
}

$bundleDirectory = Join-Path $desktopRoot 'src-tauri/target/release/bundle/nsis'
$installer = Get-ChildItem -LiteralPath $bundleDirectory -Filter '*-setup.exe' -File |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
if ($null -eq $installer) {
  throw 'NSIS installer was not generated.'
}

& (Join-Path $PSScriptRoot 'release-safety-check.ps1') -PackagePaths $installer.FullName
if (-not $?) { exit 1 }

$signature = Get-AuthenticodeSignature -LiteralPath $installer.FullName
Write-Output "Desktop installer: $($installer.FullName)"
Write-Output "Authenticode status: $($signature.Status)"
if ($signature.Status -ne 'Valid') {
  Write-Warning 'Installer is suitable for internal acceptance only until a trusted code-signing certificate is configured.'
}
