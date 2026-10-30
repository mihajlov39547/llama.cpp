# Development-only exporter; geometry mirrors icon-master.svg.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$master = [System.Drawing.Bitmap]::new(1024, 1024)
$canvas = [System.Drawing.Graphics]::FromImage($master)
$canvas.Clear([System.Drawing.Color]::Transparent)
$canvas.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$canvas.ScaleTransform(8, 8)
$fill = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#132d46'))
$border = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml('#42d9c8'), 6)
$border.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$lines = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml('#e6fffa'), 9)
$lines.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$lines.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$coords = @(64,8,112,26,106,76,88,102,64,120,40,102,22,76,16,26)
$points = for ($i = 0; $i -lt $coords.Length; $i += 2) {
    [System.Drawing.PointF]::new($coords[$i], $coords[$i+1])
}
$canvas.FillPolygon($fill, [System.Drawing.PointF[]]$points)
$canvas.DrawPolygon($border, [System.Drawing.PointF[]]$points)
$canvas.DrawLine($lines, 40,43,88,43)
$canvas.DrawLine($lines, 48,63,80,63)
$canvas.DrawLine($lines, 56,83,72,83)
$canvas.Dispose()
foreach ($size in @(16,32,48,128)) {
    $output = [System.Drawing.Bitmap]::new($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($output)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($master, [System.Drawing.Rectangle]::new(0,0,$size,$size))
    $g.Dispose()
    $output.Save((Join-Path $PSScriptRoot "icon$size.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $output.Dispose()
}
foreach ($resource in @($master,$fill,$border,$lines)) { $resource.Dispose() }
