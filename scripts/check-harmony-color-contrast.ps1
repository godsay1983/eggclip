$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$harmonyRoot = Join-Path $repoRoot 'harmony'
$manifestPath = Join-Path $harmonyRoot 'accessibility/color-contrast.json'
$navigationSourcePath = Join-Path $harmonyRoot 'entry/src/main/ets/pages/Index.ets'
$statusSourcePaths = @(
  'entry/src/main/ets/pages/HomePage.ets',
  'entry/src/main/ets/pages/DevicesPage.ets',
  'entry/src/main/ets/pages/PairingPage.ets',
  'entry/src/main/ets/pages/SettingsPage.ets',
  'entry/src/main/ets/components/common/StatusDot.ets'
)

function ConvertTo-Rgb {
  param([Parameter(Mandatory = $true)][string]$HexColor)

  $hex = $HexColor.Trim().TrimStart('#')
  if ($hex.Length -eq 8) {
    $hex = $hex.Substring(2)
  }
  if ($hex.Length -ne 6 -or $hex -notmatch '^[0-9A-Fa-f]{6}$') {
    throw "Unsupported color value: $HexColor"
  }

  return @(
    [Convert]::ToInt32($hex.Substring(0, 2), 16),
    [Convert]::ToInt32($hex.Substring(2, 2), 16),
    [Convert]::ToInt32($hex.Substring(4, 2), 16)
  )
}

function Get-LinearChannel {
  param([Parameter(Mandatory = $true)][double]$Channel)

  $normalized = $Channel / 255.0
  if ($normalized -le 0.04045) {
    return $normalized / 12.92
  }
  return [Math]::Pow(($normalized + 0.055) / 1.055, 2.4)
}

function Get-RelativeLuminance {
  param([Parameter(Mandatory = $true)][string]$HexColor)

  $rgb = ConvertTo-Rgb -HexColor $HexColor
  return 0.2126 * (Get-LinearChannel $rgb[0]) +
    0.7152 * (Get-LinearChannel $rgb[1]) +
    0.0722 * (Get-LinearChannel $rgb[2])
}

function Get-ContrastRatio {
  param(
    [Parameter(Mandatory = $true)][string]$Foreground,
    [Parameter(Mandatory = $true)][string]$Background
  )

  $foregroundLuminance = Get-RelativeLuminance -HexColor $Foreground
  $backgroundLuminance = Get-RelativeLuminance -HexColor $Background
  $lighter = [Math]::Max($foregroundLuminance, $backgroundLuminance)
  $darker = [Math]::Min($foregroundLuminance, $backgroundLuminance)
  return ($lighter + 0.05) / ($darker + 0.05)
}

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "Harmony color contrast manifest is missing: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$failures = [System.Collections.Generic.List[string]]::new()
$checkedCount = 0

foreach ($theme in $manifest.themes) {
  $resourcePath = Join-Path $harmonyRoot $theme.resourceFile
  if (-not (Test-Path -LiteralPath $resourcePath -PathType Leaf)) {
    $failures.Add("$($theme.name): missing resource file $($theme.resourceFile)")
    continue
  }

  $resourceDocument = Get-Content -LiteralPath $resourcePath -Raw -Encoding UTF8 | ConvertFrom-Json
  $colors = @{}
  foreach ($entry in $resourceDocument.color) {
    $colors[$entry.name] = $entry.value
  }

  foreach ($pair in $manifest.pairs) {
    if (-not $colors.ContainsKey($pair.foreground)) {
      $failures.Add("$($theme.name)/$($pair.name): missing foreground token $($pair.foreground)")
      continue
    }
    if (-not $colors.ContainsKey($pair.background)) {
      $failures.Add("$($theme.name)/$($pair.name): missing background token $($pair.background)")
      continue
    }

    $ratio = Get-ContrastRatio -Foreground $colors[$pair.foreground] -Background $colors[$pair.background]
    $minimumRatio = [double]$pair.minimumRatio
    $checkedCount += 1
    if ($ratio + 0.0001 -lt $minimumRatio) {
      $failures.Add(('{0}/{1}: {2:N2}:1 is below {3:N1}:1 ({4} on {5})' -f
          $theme.name, $pair.name, $ratio, $minimumRatio,
          $colors[$pair.foreground], $colors[$pair.background]))
    }
  }
}

if (-not (Test-Path -LiteralPath $navigationSourcePath -PathType Leaf)) {
  $failures.Add("Navigation source is missing: $navigationSourcePath")
} else {
  $navigationSource = Get-Content -LiteralPath $navigationSourcePath -Raw -Encoding UTF8
  if ($navigationSource -match 'fontColor\([^\r\n]*EggClipColors\.primary') {
    $failures.Add('Navigation labels must not use the brand primary color as foreground.')
  }
  if ($navigationSource -match 'color:\s*selected\s*\?\s*EggClipColors\.primary') {
    $failures.Add('Selected navigation glyphs must use onPrimary over the primary fill.')
  }
  $selectedFillCount = ([regex]::Matches(
      $navigationSource,
      'backgroundColor\(selected\s*\?\s*EggClipColors\.primary\s*:\s*Color\.Transparent\)'
    )).Count
  if ($selectedFillCount -ne 1) {
    $failures.Add("Navigation must define exactly one selected primary fill; found $selectedFillCount.")
  }
}

$forbiddenStatusForegrounds = @(
  @{ Name = 'primary font foreground'; Pattern = 'fontColor\([^\r\n]*EggClipColors\.primary' },
  @{ Name = 'primary dialog foreground'; Pattern = 'fontColor:\s*EggClipColors\.primary' },
  @{ Name = 'primary state return'; Pattern = 'return\s+EggClipColors\.primary\s*;' },
  @{ Name = 'primary direct glyph color'; Pattern = 'color:\s*EggClipColors\.primary' },
  @{ Name = 'primary direct fill'; Pattern = '\.fill\(EggClipColors\.primary\)' },
  @{ Name = 'raw red foreground'; Pattern = 'Color\.Red' }
)
foreach ($relativeSourcePath in $statusSourcePaths) {
  $sourcePath = Join-Path $harmonyRoot $relativeSourcePath
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    $failures.Add("Status source is missing: $relativeSourcePath")
    continue
  }
  $source = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
  foreach ($forbidden in $forbiddenStatusForegrounds) {
    if ($source -match $forbidden.Pattern) {
      $failures.Add("$relativeSourcePath uses forbidden $($forbidden.Name).")
    }
  }
}

if ($failures.Count -gt 0) {
  Write-Error ("Harmony color contrast check failed:`n - " + ($failures -join "`n - "))
  exit 1
}

Write-Output "Harmony color contrast check passed: $checkedCount theme/pair combinations plus navigation and status source contracts inspected."
