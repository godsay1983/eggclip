$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot 'harmony/entry/src/main/ets'
$sourceFiles = Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Filter '*.ets'
$logCallPattern = '(?i)\b(?:hilog|console|logger|log)\.(?:debug|info|warn|error|fatal)\s*\(|\bprint\s*\('
$sensitiveIdentifierPattern = '(?i)clipboard(?:Text|Content|Body)|invitation(?:Text|Secret|Token)|pairingSecret|spaceKey(?!Version)|privateKey|sharedSecret|contentDigest|decryptedPayload|rawFrame|frameBody|\bpayload\b|\bnonce\b|ciphertext|plaintext'
$unsafeSerializationPattern = '(?i)JSON\.stringify\s*\(\s*(?!err\b|bundleVersion\b)'
$violations = [System.Collections.Generic.List[string]]::new()
$logCallCount = 0

foreach ($sourceFile in $sourceFiles) {
  $lines = @(Get-Content -LiteralPath $sourceFile.FullName -Encoding UTF8)
  for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex += 1) {
    if ($lines[$lineIndex] -notmatch $logCallPattern) {
      continue
    }
    $logCallCount += 1
    $windowEnd = [Math]::Min($lineIndex + 4, $lines.Count - 1)
    $logCall = ($lines[$lineIndex..$windowEnd] -join "`n")
    $relativePath = $sourceFile.FullName.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
    if ($logCall -match $sensitiveIdentifierPattern) {
      $violations.Add("$relativePath`:$($lineIndex + 1) passes a sensitive identifier to a log call")
    }
    if ($logCall -match $unsafeSerializationPattern) {
      $violations.Add("$relativePath`:$($lineIndex + 1) serializes a non-allowlisted object in a log call")
    }
  }
}

if ($violations.Count -gt 0) {
  Write-Error ("Harmony log privacy check failed:`n - " + ($violations -join "`n - "))
  exit 1
}

Write-Output "Harmony log privacy check passed: $logCallCount log calls inspected across $($sourceFiles.Count) ArkTS files."
