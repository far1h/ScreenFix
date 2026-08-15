using System.Drawing.Drawing2D;
using ScreenFix.Core.Calibration;
using ScreenFix.Core.Geometry;

namespace ScreenFix.App.Calibration;

internal static class CalibrationPainter
{
    private const string Instruction = "Drag red bands or white edges";

    public static void Paint(
        Graphics graphics,
        uint dpi,
        RectD logicalFrame,
        IReadOnlyList<RectD> bands,
        CalibrationLayoutSpec layout)
    {
        var scale = dpi / 96f;
        var state = graphics.Save();
        graphics.ScaleTransform(scale, scale);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;

        PaintBands(graphics, logicalFrame, bands);
        PaintInstruction(graphics, layout);
        PaintButton(graphics, layout.SaveButton, layout.ButtonCornerRadius, layout.SaveColor, "Save", layout.ButtonFontSize);
        PaintButton(graphics, layout.CancelButton, layout.ButtonCornerRadius, layout.CancelColor, "Cancel", layout.ButtonFontSize);

        graphics.Restore(state);
    }

    private static void PaintBands(
        Graphics graphics,
        RectD logicalFrame,
        IReadOnlyList<RectD> bands)
    {
        using var fill = new SolidBrush(Color.FromArgb(88, 220, 38, 38));
        using var outline = new Pen(Color.FromArgb(255, 249, 115, 22), 2);
        using var handle = new SolidBrush(Color.White);

        foreach (var band in bands)
        {
            var frame = ToRectangleF(band.ToAbsolute(logicalFrame));
            graphics.FillRectangle(fill, frame);
            graphics.DrawRectangle(outline, frame.X, frame.Y, frame.Width, frame.Height);
            graphics.FillRectangle(handle, frame.X, frame.Y, 8, frame.Height);
            graphics.FillRectangle(handle, frame.Right - 8, frame.Y, 8, frame.Height);
            graphics.FillRectangle(handle, frame.X, frame.Y, frame.Width, 8);
            graphics.FillRectangle(handle, frame.X, frame.Bottom - 8, frame.Width, 8);
        }
    }

    private static void PaintInstruction(Graphics graphics, CalibrationLayoutSpec layout)
    {
        using var background = new SolidBrush(ToColor(layout.InstructionColor));
        using var stroke = new Pen(ToColor(layout.InstructionStrokeColor), 1);
        using var dot = new SolidBrush(ToColor(layout.InstructionDotColor));
        using var text = new SolidBrush(Color.White);
        using var font = CreateFont(layout.InstructionFontSize);
        using var path = RoundedRectangle(layout.Instruction, layout.InstructionCornerRadius);
        using var format = new StringFormat
        {
            Alignment = StringAlignment.Near,
            LineAlignment = StringAlignment.Center,
            Trimming = StringTrimming.None,
        };

        graphics.FillPath(background, path);
        graphics.DrawPath(stroke, path);
        graphics.FillEllipse(dot, ToRectangleF(layout.InstructionDot));
        graphics.DrawString(Instruction, font, text, ToRectangleF(layout.InstructionText), format);
    }

    private static void PaintButton(
        Graphics graphics,
        RectD frame,
        double radius,
        CalibrationColor color,
        string label,
        double fontSize)
    {
        using var background = new SolidBrush(ToColor(color));
        using var text = new SolidBrush(Color.White);
        using var font = CreateFont(fontSize);
        using var path = RoundedRectangle(frame, radius);
        using var format = new StringFormat
        {
            Alignment = StringAlignment.Center,
            LineAlignment = StringAlignment.Center,
        };

        graphics.FillPath(background, path);
        graphics.DrawString(label, font, text, ToRectangleF(frame), format);
    }

    private static Font CreateFont(double size) => new(
        SystemFonts.MessageBoxFont?.FontFamily ?? FontFamily.GenericSansSerif,
        (float)size,
        FontStyle.Bold,
        GraphicsUnit.Pixel);

    private static Color ToColor(CalibrationColor color)
    {
        var opaque = ColorTranslator.FromHtml(color.Hex);
        return Color.FromArgb(
            checked((int)Math.Round(color.Opacity * byte.MaxValue)),
            opaque.R,
            opaque.G,
            opaque.B);
    }

    private static GraphicsPath RoundedRectangle(RectD frame, double radius)
    {
        var rectangle = ToRectangleF(frame);
        var diameter = (float)(radius * 2);
        var path = new GraphicsPath();
        path.AddArc(rectangle.Left, rectangle.Top, diameter, diameter, 180, 90);
        path.AddArc(rectangle.Right - diameter, rectangle.Top, diameter, diameter, 270, 90);
        path.AddArc(rectangle.Right - diameter, rectangle.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(rectangle.Left, rectangle.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    private static RectangleF ToRectangleF(RectD value) => new(
        (float)value.X,
        (float)value.Y,
        (float)value.Width,
        (float)value.Height);
}
