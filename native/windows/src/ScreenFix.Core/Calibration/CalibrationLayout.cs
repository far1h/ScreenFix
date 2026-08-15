using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Calibration;

public readonly record struct CalibrationColor(string Hex, double Opacity = 1);

public sealed record CalibrationLayoutSpec(
    RectD SaveButton,
    RectD CancelButton,
    RectD Instruction,
    RectD InstructionDot,
    RectD InstructionText,
    double ButtonCornerRadius,
    double ButtonFontSize,
    double InstructionCornerRadius,
    double InstructionFontSize,
    CalibrationColor SaveColor,
    CalibrationColor CancelColor,
    CalibrationColor InstructionColor,
    CalibrationColor InstructionStrokeColor,
    CalibrationColor InstructionDotColor);

public readonly record struct CalibrationLayoutResult(
    CalibrationLayoutSpec? Value,
    string? Error)
{
    public bool IsSuccess => Value is not null;
}

public static class CalibrationLayout
{
    private const double MinimumWidth = 260;
    private const double MinimumHeight = 180;
    private const double Inset = 24;
    private const double ButtonGap = 12;
    private const double ButtonHeight = 42;

    public static CalibrationLayoutResult TryCreate(double width, double height)
    {
        if (!IsFinite(width) || !IsFinite(height) ||
            width < MinimumWidth || height < MinimumHeight)
        {
            return new CalibrationLayoutResult(
                null,
                "display is too small for calibration controls");
        }

        var buttonWidth = Math.Min(104, Math.Floor((width - (2 * Inset) - ButtonGap) / 2));
        var buttonY = height - Inset - ButtonHeight;
        var save = new RectD(Inset, buttonY, buttonWidth, ButtonHeight);
        var cancel = new RectD(Inset + buttonWidth + ButtonGap, buttonY, buttonWidth, ButtonHeight);
        var isNarrow = width < 378;
        var instructionHeight = isNarrow ? 58 : 42;
        var instructionWidth = isNarrow ? width - (2 * Inset) : 330;
        var instruction = new RectD(Inset, Inset, instructionWidth, instructionHeight);
        var dot = new RectD(40, Inset + ((instructionHeight - 8) / 2), 8, 8);
        var text = new RectD(
            58,
            Inset,
            isNarrow ? width - 98 : 280,
            instructionHeight);

        return new CalibrationLayoutResult(
            new CalibrationLayoutSpec(
                save,
                cancel,
                instruction,
                dot,
                text,
                9,
                16,
                10,
                isNarrow ? 13 : 15,
                new CalibrationColor("#16A34A"),
                new CalibrationColor("#353A42"),
                new CalibrationColor("#000000", 0.88),
                new CalibrationColor("#FFFFFF", 0.28),
                new CalibrationColor("#FF643B")),
            null);
    }

    private static bool IsFinite(double value) => !double.IsNaN(value) && !double.IsInfinity(value);
}
