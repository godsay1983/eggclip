param(
  [string[]]$PackagePaths = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$tracked = @(& git -c core.quotepath=false -C $repoRoot ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE -ne 0) {
  throw 'Unable to enumerate tracked files.'
}

$violations = [System.Collections.Generic.List[string]]::new()
$blockedTracked = '(?i)(^|/)(local\.properties|\.env(?:\..*)?|.*\.(?:p12|p7b|cer|pem|key|sqlite|sqlite3|db|log|dmp))$|(^|/)(?:node_modules|oh_modules|target|build|\.hvigor|\.idea)/'
$secretMarkers = @(
  @{ Name = 'private-key-header'; Pattern = '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----' },
  @{ Name = 'credential-assignment'; Pattern = '(?i)(?:storePassword|keyPassword|api[_-]?key)\s*[:=]\s*["''][^"'']+["'']' }
)

foreach ($relativePath in $tracked) {
  $normalized = $relativePath -replace '\\', '/'
  if ($normalized -match $blockedTracked) {
    $violations.Add("$normalized [blocked tracked artifact]")
    continue
  }
  $absolutePath = Join-Path $repoRoot $relativePath
  if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) { continue }
  if ([IO.Path]::GetExtension($absolutePath) -match '(?i)\.(png|ico|icns|woff2?)') { continue }
  if ($normalized -eq 'scripts/release-safety-check.ps1') { continue }
  $content = Get-Content -LiteralPath $absolutePath -Raw -ErrorAction SilentlyContinue
  if ($null -eq $content) { continue }
  foreach ($marker in $secretMarkers) {
    if ($content -match $marker.Pattern) {
      $violations.Add("$normalized [$($marker.Name)]")
    }
  }
}

$buildProfilePath = Join-Path $repoRoot 'harmony/build-profile.json5'
if (Test-Path -LiteralPath $buildProfilePath) {
  $profile = Get-Content -LiteralPath $buildProfilePath -Raw
  if ($profile -match '(?i)["'']?(?:storeFile|storePassword|keyPassword|certpath)["'']?\s*:') {
    $violations.Add('harmony/build-profile.json5 [signing material key present]')
  }
}

foreach ($requestedPath in $PackagePaths) {
  $packagePath = if ([IO.Path]::IsPathRooted($requestedPath)) {
    $requestedPath
  } else {
    Join-Path $repoRoot $requestedPath
  }
  if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    $violations.Add("$requestedPath [release package missing]")
    continue
  }
  $entries = @(& tar -tf $packagePath 2>$null)
  $relative = $requestedPath -replace '\\', '/'
  if ($LASTEXITCODE -ne 0) {
    $violations.Add("$relative [release archive cannot be inspected]")
  } elseif ($entries | Where-Object { $_ -match '(?i)\.(pdb|ilk|map|log|dmp)$' }) {
    $violations.Add("$relative [debug artifact packaged in release archive]")
  }
}

foreach ($requiredDocument in @('docs/PRIVACY.md', 'docs/LAN_TROUBLESHOOTING.md')) {
  if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $requiredDocument))) {
    $violations.Add("$requiredDocument [required release document missing]")
  }
}

if ($violations.Count -gt 0) {
  Write-Error ("Release safety check failed:`n - " + ($violations -join "`n - "))
  exit 1
}

Write-Output "Release safety check passed: $($tracked.Count) repository paths and $($PackagePaths.Count) release packages inspected."
