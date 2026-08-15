import Foundation

public struct CalibrationControlLayout: Equatable {
    public let save: RectD
    public let cancel: RectD
    public let instruction: RectD
    public let instructionDot: RectD
    public let instructionText: RectD
    public let instructionTextSize: Double

    public init(
        save: RectD,
        cancel: RectD,
        instruction: RectD,
        instructionDot: RectD,
        instructionText: RectD,
        instructionTextSize: Double
    ) {
        self.save = save
        self.cancel = cancel
        self.instruction = instruction
        self.instructionDot = instructionDot
        self.instructionText = instructionText
        self.instructionTextSize = instructionTextSize
    }

    public static func make(width: Double, height: Double) -> CalibrationControlLayout? {
        guard width.isFinite, height.isFinite, width >= 260, height >= 180 else {
            return nil
        }
        let buttonWidth = min(104, floor((width - 48 - 12) / 2))
        let save = RectD(x: 24, y: height - 66, width: buttonWidth, height: 42)
        let cancel = RectD(x: 36 + buttonWidth, y: height - 66, width: buttonWidth, height: 42)
        if width < 378 {
            let instruction = RectD(x: 24, y: 24, width: width - 48, height: 58)
            return CalibrationControlLayout(
                save: save,
                cancel: cancel,
                instruction: instruction,
                instructionDot: RectD(x: 40, y: 49, width: 8, height: 8),
                instructionText: RectD(x: 58, y: 24, width: instruction.width - 50, height: 58),
                instructionTextSize: 13
            )
        }
        return CalibrationControlLayout(
            save: save,
            cancel: cancel,
            instruction: RectD(x: 24, y: 24, width: 330, height: 42),
            instructionDot: RectD(x: 40, y: 41, width: 8, height: 8),
            instructionText: RectD(x: 58, y: 24, width: 280, height: 42),
            instructionTextSize: 15
        )
    }
}
