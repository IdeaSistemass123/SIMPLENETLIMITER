# Gera app.ico (formato classico BMP/DIB, compativel com brcc32 antigo).
# Desenho: tile azul arredondado + simbolo de wifi branco + barra vermelha (corte).
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

$sizes = 16,24,32,48
$entries = @()  # cada item: @{ W; H; Bytes }

function New-IconImage([int]$s) {
  $s = [int]$s
  $bmp = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.Clear([System.Drawing.Color]::Transparent)

  # fundo arredondado azul
  $pad = [int]([math]::Max(0, [math]::Round($s*0.03)))
  $rad = [int]([math]::Max(2, [math]::Round($s*0.20)))
  $d = $rad*2
  $x0 = $pad; $y0 = $pad; $x1 = $s-1-$pad; $y1 = $s-1-$pad
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddArc($x0, $y0, $d, $d, 180, 90)
  $path.AddArc($x1-$d, $y0, $d, $d, 270, 90)
  $path.AddArc($x1-$d, $y1-$d, $d, $d, 0, 90)
  $path.AddArc($x0, $y1-$d, $d, $d, 90, 90)
  $path.CloseFigure()
  $bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,40,55,95))
  $g.FillPath($bg, $path)

  # arcos de wifi (branco)
  $cx = $s/2.0
  $baseY = $s*0.66
  $penW = [float]([math]::Max(1.0, $s*0.075))
  $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White, $penW)
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  foreach ($f in @(0.14, 0.24, 0.34)) {
    $r = [double]$s * [double]$f
    $g.DrawArc($pen, [float]($cx-$r), [float]($baseY-$r), [float]($r*2), [float]($r*2), 215, 110)
  }
  $dotR = [float]($s*0.05)
  $wb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
  $g.FillEllipse($wb, [float]($cx-$dotR), [float]($baseY-$dotR), [float]($dotR*2), [float]($dotR*2))

  # barra vermelha diagonal (corte/limite)
  $sp = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255,225,45,45), [float]([math]::Max(1.5, $s*0.10)))
  $sp.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $sp.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $g.DrawLine($sp, [float]($s*0.24), [float]($s*0.24), [float]($s*0.76), [float]($s*0.76))

  $g.Dispose()

  # extrai pixels (BGRA, top-down)
  $rect = New-Object System.Drawing.Rectangle(0,0,$s,$s)
  $bd = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $stride = $bd.Stride
  $px = New-Object byte[] ($stride*$s)
  [System.Runtime.InteropServices.Marshal]::Copy($bd.Scan0, $px, 0, $px.Length)
  $bmp.UnlockBits($bd)
  $bmp.Dispose()

  # monta DIB: BITMAPINFOHEADER + XOR(bottom-up BGRA) + AND mask(zeros)
  $maskRow = [int]([math]::Floor(($s + 31)/32) * 4)
  $xorSize = $s*$s*4
  $andSize = $maskRow*$s
  $ms = New-Object System.IO.MemoryStream
  $bw = New-Object System.IO.BinaryWriter($ms)
  $bw.Write([uint32]40)      # biSize
  $bw.Write([int32]$s)       # biWidth
  $bw.Write([int32]($s*2))   # biHeight (XOR+AND)
  $bw.Write([uint16]1)       # biPlanes
  $bw.Write([uint16]32)      # biBitCount
  $bw.Write([uint32]0)       # biCompression BI_RGB
  $bw.Write([uint32]0)       # biSizeImage
  $bw.Write([int32]0); $bw.Write([int32]0)   # ppm
  $bw.Write([uint32]0); $bw.Write([uint32]0) # clrs
  for ($y = $s-1; $y -ge 0; $y--) {
    $bw.Write($px, $y*$stride, $s*4)
  }
  $bw.Write((New-Object byte[] $andSize))
  $bw.Flush()
  return @{ W = $s; H = $s; Bytes = $ms.ToArray() }
}

foreach ($s in $sizes) { $entries += (New-IconImage $s) }

# escreve o .ico
$out = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($out)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$entries.Count)
$offset = 6 + 16*$entries.Count
foreach ($e in $entries) {
  $w = $(if ($e.W -ge 256) { 0 } else { $e.W })
  $h = $(if ($e.H -ge 256) { 0 } else { $e.H })
  $bw.Write([byte]$w); $bw.Write([byte]$h)
  $bw.Write([byte]0); $bw.Write([byte]0)
  $bw.Write([uint16]1); $bw.Write([uint16]32)
  $bw.Write([uint32]$e.Bytes.Length)
  $bw.Write([uint32]$offset)
  $offset += $e.Bytes.Length
}
foreach ($e in $entries) { $bw.Write($e.Bytes) }
$bw.Flush()
[System.IO.File]::WriteAllBytes('C:\Fonte\sefaz-throttle\src\app.ico', $out.ToArray())
Copy-Item 'C:\Fonte\sefaz-throttle\src\app.ico' 'C:\Fonte\sefaz-throttle\bin\app.ico' -Force
Write-Output ("app.ico gerado: {0} bytes, {1} tamanhos" -f (Get-Item 'C:\Fonte\sefaz-throttle\src\app.ico').Length, $entries.Count)
