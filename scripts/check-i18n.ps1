param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot

& node (Join-Path $repoRoot 'scripts/validate-i18n-foundation.mjs')
if ($LASTEXITCODE -ne 0) {
  throw 'Internationalization resource validation failed.'
}

Push-Location (Join-Path $repoRoot 'desktop')
try {
  & pnpm exec vitest run src/lib/i18n/i18n.test.ts
  if ($LASTEXITCODE -ne 0) {
    throw 'Desktop internationalization tests failed.'
  }
} finally {
  Pop-Location
}

Write-Output 'Internationalization check passed: resources, placeholders, generated names, hard-coded copy, and safe parameters validated.'
