Add-Type -AssemblyName System.Drawing

# Original geometric ad window/slash mark, rendered at 4x for crisp small icons.
foreach ($size in @(16, 32, 48, 128)) {
    $bitmap = New-Object System.Drawing.Bitmap ($size * 4), ($size * 4)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.ScaleTransform(($size * 4 / 128), ($size * 4 / 128))
    $shape = New-Object System.Drawing.Drawing2D.GraphicsPath
    $shape.AddArc(4, 4, 44, 44, 180, 90)
    $shape.AddArc(80, 4, 44, 44, 270, 90)
    $shape.AddArc(80, 80, 44, 44, 0, 90)
    $shape.AddArc(4, 80, 44, 44, 90, 90)
    $shape.CloseFigure()
    $blue = New-Object System.Drawing.Drawing2D.LinearGradientBrush ([System.Drawing.Point]::new(0, 0)), ([System.Drawing.Point]::new(128, 128)), ([System.Drawing.Color]::FromArgb(145, 102, 239)), ([System.Drawing.Color]::FromArgb(82, 51, 174))
    $graphics.FillPath($blue, $shape)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 7
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawRectangle($pen, 27, 32, 74, 64)
    $graphics.DrawLine($pen, 27, 49, 101, 49)
    $graphics.DrawLine($pen, 41, 65, 63, 65)
    $graphics.DrawLine($pen, 41, 80, 53, 80)
    $outline = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(108, 69, 202)), 17
    $outline.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $outline.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawLine($outline, 31, 102, 103, 29)
    $graphics.DrawLine($pen, 31, 102, 103, 29)
    $outline.Dispose()
    $output = New-Object System.Drawing.Bitmap $size, $size
    $scaled = [System.Drawing.Graphics]::FromImage($output)
    $scaled.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $scaled.DrawImage($bitmap, 0, 0, $size, $size)
    $output.Save((Join-Path $PSScriptRoot "icon$size.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $scaled.Dispose()
    $output.Dispose()
    $pen.Dispose()
    $blue.Dispose()
    $shape.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}
