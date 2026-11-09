Add-Type -AssemblyName System.Drawing

# Original geometric copy/paste mark, rendered at 4x for crisp small icons.
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
    $blue = New-Object System.Drawing.Drawing2D.LinearGradientBrush ([System.Drawing.Point]::new(0, 0)), ([System.Drawing.Point]::new(128, 128)), ([System.Drawing.Color]::FromArgb(24, 174, 151)), ([System.Drawing.Color]::FromArgb(6, 101, 105))
    $graphics.FillPath($blue, $shape)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 7
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawLines($pen, [System.Drawing.Point[]]@([System.Drawing.Point]::new(39, 85), [System.Drawing.Point]::new(27, 85), [System.Drawing.Point]::new(27, 29), [System.Drawing.Point]::new(77, 29), [System.Drawing.Point]::new(77, 41)))
    $graphics.DrawRectangle($pen, 49, 48, 50, 54)
    $graphics.DrawLine($pen, 62, 67, 86, 67)
    $graphics.DrawLine($pen, 62, 82, 80, 82)
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
