param(
  [switch]$Restore
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$sharedProfilePath = Join-Path $repoRoot 'harmony/build-profile.json5'
$localProfilePath = Join-Path $repoRoot 'harmony/build-profile.local.json5'

function Clear-ArrayProperty {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$PropertyName
  )

  $propertyPattern = '["'']?{0}["'']?\s*:\s*\[' -f [Regex]::Escape($PropertyName)
  $propertyMatch = [Regex]::Match($Source, $propertyPattern)
  if (-not $propertyMatch.Success) {
    throw "Array property is missing: $PropertyName"
  }
  $openingIndex = $propertyMatch.Index + $propertyMatch.Length - 1
  $depth = 0
  $quote = [char]0
  $escaped = $false
  $closingIndex = -1
  for ($index = $openingIndex; $index -lt $Source.Length; $index += 1) {
    $character = $Source[$index]
    if ($quote -ne [char]0) {
      if ($escaped) {
        $escaped = $false
      } elseif ($character -eq '\') {
        $escaped = $true
      } elseif ($character -eq $quote) {
        $quote = [char]0
      }
      continue
    }
    if ($character -eq '"' -or $character -eq "'") {
      $quote = $character
      continue
    }
    if ($character -eq '[') {
      $depth += 1
      continue
    }
    if ($character -eq ']') {
      $depth -= 1
      if ($depth -eq 0) {
        $closingIndex = $index
        break
      }
    }
  }
  if ($closingIndex -lt 0) {
    throw "Array property is not balanced: $PropertyName"
  }
  return $Source.Substring(0, $openingIndex + 1) + $Source.Substring($closingIndex)
}

if (-not (Test-Path -LiteralPath $sharedProfilePath -PathType Leaf)) {
  throw 'Shared Harmony build profile is missing.'
}

if ($Restore) {
  $restoreCandidate = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'harmony') `
    -Filter 'build-profile.local*.json5' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($null -eq $restoreCandidate) {
    throw 'Local Harmony signing profile backup is missing.'
  }
  Copy-Item -LiteralPath $restoreCandidate.FullName -Destination $sharedProfilePath -Force
  Write-Output 'Restored the local Harmony signing profile without displaying its contents.'
  exit 0
}

$sharedHash = (Get-FileHash -LiteralPath $sharedProfilePath -Algorithm SHA256).Hash
$matchingBackup = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'harmony') -Filter 'build-profile.local*.json5' -File |
  Where-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -eq $sharedHash } |
  Select-Object -First 1
if ($null -ne $matchingBackup) {
  $localProfilePath = $matchingBackup.FullName
} elseif (Test-Path -LiteralPath $localProfilePath -PathType Leaf) {
  $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $localProfilePath = Join-Path $repoRoot "harmony/build-profile.local.$timestamp.json5"
}
Copy-Item -LiteralPath $sharedProfilePath -Destination $localProfilePath -Force

$profile = [IO.File]::ReadAllText($sharedProfilePath)
$sanitized = Clear-ArrayProperty -Source $profile -PropertyName 'signingConfigs'
$sanitized = [Regex]::Replace(
  $sanitized,
  '(?m)^\s*["'']?signingConfig["'']?\s*:\s*["''][^"'']+["'']\s*,?\s*\r?\n',
  ''
)

if ($sanitized -match '(?i)["'']?(?:storeFile|storePassword|keyPassword|certpath)["'']?\s*:') {
  throw 'Shared Harmony build profile still contains signing material keys after sanitization.'
}
if ($sanitized -eq $profile) {
  throw 'No signing configuration was removed from the shared Harmony build profile.'
}

[IO.File]::WriteAllText($sharedProfilePath, $sanitized, [Text.UTF8Encoding]::new($false))
Write-Output "Sanitized the shared Harmony build profile. Local signing settings were preserved in $localProfilePath."
