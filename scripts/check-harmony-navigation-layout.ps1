$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$harmonySourceRoot = Join-Path $repoRoot 'harmony/entry/src/main/ets'
$spacingPath = Join-Path $harmonySourceRoot 'theme/Spacing.ets'
$indexPath = Join-Path $harmonySourceRoot 'pages/Index.ets'
$mainPagePaths = @(
  (Join-Path $harmonySourceRoot 'pages/HomePage.ets'),
  (Join-Path $harmonySourceRoot 'pages/DevicesPage.ets'),
  (Join-Path $harmonySourceRoot 'pages/SettingsPage.ets')
)

function Get-Source {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Required Harmony source is missing: $Path"
  }
  return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

function Assert-Contains {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Expected,
    [Parameter(Mandatory = $true)][string]$Context
  )

  if (-not $Source.Contains($Expected)) {
    throw "$Context is missing required layout contract: $Expected"
  }
}

function Get-SpacingValue {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $pattern = "static readonly $Name`: number = (?<value>\d+);"
  $match = [Regex]::Match($Source, $pattern)
  if (-not $match.Success) {
    throw "Spacing token is missing or invalid: $Name"
  }
  return [int]$match.Groups['value'].Value
}

$spacingSource = Get-Source -Path $spacingPath
$indexSource = Get-Source -Path $indexPath
$itemHeight = Get-SpacingValue -Source $spacingSource -Name 'floatingNavigationItemHeight'
$bottomMargin = Get-SpacingValue -Source $spacingSource -Name 'floatingNavigationBottomMargin'
$maskHeight = Get-SpacingValue -Source $spacingSource -Name 'floatingNavigationMaskHeight'
$contentInset = Get-SpacingValue -Source $spacingSource -Name 'floatingNavigationContentInset'

if ($contentInset -le $maskHeight) {
  throw 'Scrollable content inset must clear the entire floating navigation gradient mask.'
}
if ($contentInset -le ($itemHeight + $bottomMargin)) {
  throw 'Scrollable content inset must clear the floating navigation bar and its bottom margin.'
}

Assert-Contains -Source $indexSource `
  -Expected 'barBottomMargin: EggClipSpacing.floatingNavigationBottomMargin' `
  -Context 'Index.ets'
Assert-Contains -Source $indexSource `
  -Expected 'maskHeight: EggClipSpacing.floatingNavigationMaskHeight' `
  -Context 'Index.ets'
Assert-Contains -Source $indexSource `
  -Expected '.height(EggClipSpacing.floatingNavigationItemHeight)' `
  -Context 'Index.ets'

foreach ($pagePath in $mainPagePaths) {
  $pageSource = Get-Source -Path $pagePath
  $pageName = Split-Path -Leaf $pagePath
  Assert-Contains -Source $pageSource -Expected 'Scroll()' -Context $pageName
  Assert-Contains -Source $pageSource -Expected ".height('100%')" -Context $pageName
  Assert-Contains -Source $pageSource `
    -Expected 'bottom: EggClipSpacing.floatingNavigationContentInset' `
    -Context $pageName
  Assert-Contains -Source $pageSource `
    -Expected '.constraintSize({ maxWidth: 960 })' `
    -Context $pageName
  if ($pageSource -match 'bottom\s*:\s*112') {
    throw "$pageName still contains the old hard-coded navigation inset."
  }
}

Write-Host "Harmony navigation layout check passed: 1 floating bar and $($mainPagePaths.Count) scrollable pages share the same safe inset."
