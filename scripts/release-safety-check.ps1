param(
  [string[]]$PackagePaths = @(),
  [switch]$SkipI18nCheck
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
  $content = Get-Content -LiteralPath $absolutePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
  if ($null -eq $content) { continue }
  foreach ($marker in $secretMarkers) {
    if ($content -match $marker.Pattern) {
      $violations.Add("$normalized [$($marker.Name)]")
    }
  }
}

$frontendSensitiveStatePattern = '(?i)\b(?:invitationString|pairingSecret|privateKey|sharedSecret|rawFrame|frameBody|decryptedPayload)\b'
$frontendFiles = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'desktop/src') -Recurse -File |
  Where-Object { $_.Extension -match '(?i)^\.(ts|svelte)$' }
foreach ($file in $frontendFiles) {
  $relativePath = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
  $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
  if ($content -match $frontendSensitiveStatePattern) {
    $violations.Add("$relativePath [sensitive material identifier in frontend state]")
  }
}

$rustLogPattern = '(?i)\b(?:trace|debug|info|warn|error)!\s*\(|\b(?:println|eprintln|dbg)!\s*\('
$rustSensitivePattern = '(?i)pairing[_ ]?secret|invitation(?:_text|_secret|string)|space[_ ]?key(?!_version| version)|private[_ ]?key|shared[_ ]?secret|clipboard(?:_text|_content| body)|raw[_ ]?frame|frame[_ ]?body|decrypted[_ ]?payload|plaintext|ciphertext'
$rustFiles = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'desktop/src-tauri/src') -Recurse -File -Filter '*.rs'
foreach ($file in $rustFiles) {
  $lines = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8)
  for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex += 1) {
    if ($lines[$lineIndex] -notmatch $rustLogPattern) { continue }
    $windowEnd = [Math]::Min($lines.Count - 1, $lineIndex + 4)
    $logCall = $lines[$lineIndex..$windowEnd] -join "`n"
    if ($logCall -match $rustSensitivePattern) {
      $relativePath = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
      $violations.Add("$relativePath`:$($lineIndex + 1) [sensitive identifier passed to Rust log]")
    }
  }
}

$fixtureValidator = Join-Path $repoRoot 'protocol/scripts/validate-fixtures.mjs'
if (-not (Test-Path -LiteralPath $fixtureValidator -PathType Leaf)) {
  $violations.Add('protocol/scripts/validate-fixtures.mjs [fixture validator missing]')
} else {
  & node $fixtureValidator
  if ($LASTEXITCODE -ne 0) {
    $violations.Add('protocol/test-vectors [shared fixture validation failed]')
  }
}

if (-not $SkipI18nCheck) {
  & (Join-Path $repoRoot 'scripts/check-i18n.ps1')
  if ($LASTEXITCODE -ne 0) {
    $violations.Add('scripts/check-i18n.ps1 [internationalization validation failed]')
  }
}

$buildProfilePath = Join-Path $repoRoot 'harmony/build-profile.json5'
if (Test-Path -LiteralPath $buildProfilePath) {
  $profile = Get-Content -LiteralPath $buildProfilePath -Raw -Encoding UTF8
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
  $relative = $requestedPath -replace '\\', '/'
  if ([IO.Path]::GetExtension($packagePath) -ieq '.exe') {
    $debugSibling = Get-ChildItem -LiteralPath (Split-Path -Parent $packagePath) -Recurse -File |
      Where-Object { $_.Extension -match '(?i)^\.(pdb|ilk|map|log|dmp)$' } |
      Select-Object -First 1
    if ($null -ne $debugSibling) {
      $violations.Add("$relative [debug artifact found beside release installer]")
    }
  } else {
    $entries = @(& tar -tf $packagePath 2>$null)
    if ($LASTEXITCODE -ne 0) {
      $violations.Add("$relative [release archive cannot be inspected]")
    } elseif ($entries | Where-Object { $_ -match '(?i)\.(pdb|ilk|map|log|dmp)$' }) {
      $violations.Add("$relative [debug artifact packaged in release archive]")
    }
  }
}

foreach ($requiredDocument in @('docs/PRIVACY.md', 'docs/LAN_TROUBLESHOOTING.md', 'docs/RELEASE.md')) {
  if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $requiredDocument))) {
    $violations.Add("$requiredDocument [required release document missing]")
  }
}

if ($violations.Count -gt 0) {
  Write-Error ("Release safety check failed:`n - " + ($violations -join "`n - "))
  exit 1
}

Write-Output "Release safety check passed: $($tracked.Count) repository paths and $($PackagePaths.Count) release packages inspected."
