using ScreenFix.Core.Calibration;
using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Tests;

public sealed class CalibrationLayoutTests
{
    [Fact]
    public void TryCreate_UsesExactNarrowMinimumLayout()
    {
        var result = CalibrationLayout.TryCreate(260, 180);

        Assert.True(result.IsSuccess);
        var layout = Assert.IsType<CalibrationLayoutSpec>(result.Value);
        Assert.Equal(new RectD(24, 114, 100, 42), layout.SaveButton);
        Assert.Equal(new RectD(136, 114, 100, 42), layout.CancelButton);
        Assert.Equal(new RectD(24, 24, 212, 58), layout.Instruction);
        Assert.Equal(new RectD(40, 49, 8, 8), layout.InstructionDot);
        Assert.Equal(new RectD(58, 24, 162, 58), layout.InstructionText);
        Assert.Equal(13, layout.InstructionFontSize);
    }

    [Fact]
    public void TryCreate_UsesApprovedNormalLayoutAndStyles()
    {
        var result = CalibrationLayout.TryCreate(3440, 1440);

        var layout = Assert.IsType<CalibrationLayoutSpec>(result.Value);
        Assert.Equal(new RectD(24, 1374, 104, 42), layout.SaveButton);
        Assert.Equal(new RectD(140, 1374, 104, 42), layout.CancelButton);
        Assert.Equal(12, layout.CancelButton.X - layout.SaveButton.Right);
        Assert.Equal(new RectD(24, 24, 330, 42), layout.Instruction);
        Assert.Equal(new RectD(40, 41, 8, 8), layout.InstructionDot);
        Assert.Equal(new RectD(58, 24, 280, 42), layout.InstructionText);
        Assert.Equal(9, layout.ButtonCornerRadius);
        Assert.Equal(16, layout.ButtonFontSize);
        Assert.Equal(10, layout.InstructionCornerRadius);
        Assert.Equal(15, layout.InstructionFontSize);
        Assert.Equal(new CalibrationColor("#16A34A"), layout.SaveColor);
        Assert.Equal(new CalibrationColor("#353A42"), layout.CancelColor);
        Assert.Equal(new CalibrationColor("#000000", 0.88), layout.InstructionColor);
        Assert.Equal(new CalibrationColor("#FFFFFF", 0.28), layout.InstructionStrokeColor);
        Assert.Equal(new CalibrationColor("#FF643B"), layout.InstructionDotColor);
    }

    [Theory]
    [InlineData(259, 180)]
    [InlineData(260, 179)]
    public void TryCreate_RejectsUnsupportedCanvas(double width, double height)
    {
        var result = CalibrationLayout.TryCreate(width, height);

        Assert.False(result.IsSuccess);
        Assert.Equal("display is too small for calibration controls", result.Error);
    }
}
