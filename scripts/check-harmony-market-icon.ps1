param(
  [string]$IconPath = (Join-Path $PSScriptRoot '..\docs\store-assets\app-icon-opaque.png')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Drawing

$resolvedPath = (Resolve-Path -LiteralPath $IconPath).Path
$file = Get-Item -LiteralPath $resolvedPath
$bitmap = [System.Drawing.Bitmap]::new($resolvedPath)

try {
  $expectedSize = 216
  $expectedBackground = [System.Drawing.ColorTranslator]::FromHtml('#FFF8E7')
  $minimumSafeMargin = 16
  $maximumBytes = 2MB

  if ($bitmap.Width -ne $expectedSize -or $bitmap.Height -ne $expectedSize) {
    throw "Market icon must be ${expectedSize}x${expectedSize}, got $($bitmap.Width)x$($bitmap.Height)."
  }

  if ($bitmap.RawFormat.Guid -ne [System.Drawing.Imaging.ImageFormat]::Png.Guid) {
    throw 'Market icon must be a PNG file.'
  }

  if ($file.Length -gt $maximumBytes) {
    throw "Market icon must not exceed 2 MiB, got $($file.Length) bytes."
  }

  $nonOpaquePixels = 0
  $minX = $bitmap.Width
  $minY = $bitmap.Height
  $maxX = -1
  $maxY = -1

  for ($y = 0; $y -lt $bitmap.Height; $y++) {
    for ($x = 0; $x -lt $bitmap.Width; $x++) {
      $pixel = $bitmap.GetPixel($x, $y)
      if ($pixel.A -ne 255) {
        $nonOpaquePixels++
      }

      $isBackground =
        $pixel.R -eq $expectedBackground.R -and
        $pixel.G -eq $expectedBackground.G -and
        $pixel.B -eq $expectedBackground.B

      if (-not $isBackground) {
        $minX = [Math]::Min($minX, $x)
        $minY = [Math]::Min($minY, $y)
        $maxX = [Math]::Max($maxX, $x)
        $maxY = [Math]::Max($maxY, $y)
      }
    }
  }

  if ($nonOpaquePixels -ne 0) {
    throw "Market icon contains $nonOpaquePixels non-opaque pixels."
  }

  if ($maxX -lt 0 -or $maxY -lt 0) {
    throw 'Market icon does not contain a foreground illustration.'
  }

  $margins = @(
    $minX,
    $minY,
    ($bitmap.Width - 1 - $maxX),
    ($bitmap.Height - 1 - $maxY)
  )
  $smallestMargin = ($margins | Measure-Object -Minimum).Minimum

  if ($smallestMargin -lt $minimumSafeMargin) {
    throw "Market icon safe margin must be at least $minimumSafeMargin px, got $smallestMargin px."
  }

  Write-Output (
    'Harmony market icon check passed: ' +
    "$($bitmap.Width)x$($bitmap.Height) PNG, $($file.Length) bytes, " +
    "0 transparent pixels, minimum safe margin $smallestMargin px."
  )
}
finally {
  $bitmap.Dispose()
}
