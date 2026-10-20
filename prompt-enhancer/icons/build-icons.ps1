# Development-only PNG exporter. Uses Windows System.Drawing; no installed
# packages and no extension runtime dependencies. Geometry mirrors icon-master.svg.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
function Color([string] $hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
function Polygon($graphics, $brush, [float[]] $coordinates) {
    $points = for ($i = 0; $i -lt $coordinates.Length; $i += 2) {
        [System.Drawing.PointF]::new($coordinates[$i], $coordinates[$i + 1])
    }
    $graphics.FillPolygon($brush, [System.Drawing.PointF[]] $points)
}

$master = [System.Drawing.Bitmap]::new(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($master)
$g.Clear([System.Drawing.Color]::Transparent)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.ScaleTransform(8, 8)
$navy = [System.Drawing.SolidBrush]::new((Color '#102a43'))
$blue = [System.Drawing.SolidBrush]::new((Color '#4385ff'))
$mint = [System.Drawing.SolidBrush]::new((Color '#8fede2'))
$tip = [System.Drawing.SolidBrush]::new((Color '#e6fffa'))
$border = [System.Drawing.Pen]::new((Color '#4b8eaf'), 3)
$separator = [System.Drawing.Pen]::new((Color '#102a43'), 3)
$gradient = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.PointF]::new(36, 94), [System.Drawing.PointF]::new(98, 32),
    (Color '#4385ff'), (Color '#28dac1'))
$tile = [System.Drawing.Drawing2D.GraphicsPath]::new()
$tile.AddArc(4, 4, 52, 52, 180, 90)
$tile.AddArc(72, 4, 52, 52, 270, 90)
$tile.AddArc(72, 72, 52, 52, 0, 90)
$tile.AddArc(4, 72, 52, 52, 90, 90)
$tile.CloseFigure()
$g.FillPath($navy, $tile)
$g.DrawPath($border, $tile)
Polygon $g $gradient @(40,78, 82,36, 98,52, 56,94)
Polygon $g $tip @(36,98, 40,78, 56,94)
$cap = [System.Drawing.Drawing2D.GraphicsPath]::new()
$cap.AddLine(82,36,89,29)
# Cubic equivalents of the SVG master's quadratic curves.
$cap.AddBezier(89,29,91.666667,26.333333,94.333333,26.333333,97,29)
$cap.AddLine(97,29,105,37)
$cap.AddBezier(105,37,107.666667,39.666667,107.666667,42.333333,105,45)
$cap.AddLine(105,45,98,52)
$cap.CloseFigure()
$g.FillPath($blue, $cap)
$g.DrawLine($separator, 82,36,98,52)
Polygon $g $mint @(34,18, 38,30, 50,34, 38,38, 34,50, 30,38, 18,34, 30,30)
$g.Dispose()
foreach ($size in @(16,32,48,128)) {
    $output = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $canvas = [System.Drawing.Graphics]::FromImage($output)
    $canvas.Clear([System.Drawing.Color]::Transparent)
    $canvas.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $canvas.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $canvas.DrawImage($master, [System.Drawing.Rectangle]::new(0,0,$size,$size))
    $canvas.Dispose()
    $destination = Join-Path $PSScriptRoot "icon$size.png"
    $output.Save($destination, [System.Drawing.Imaging.ImageFormat]::Png)
    $output.Dispose()
    Write-Output $destination
}
foreach ($resource in @($master,$navy,$blue,$mint,$tip,$border,$separator,$gradient,$tile,$cap)) {
    $resource.Dispose()
}
