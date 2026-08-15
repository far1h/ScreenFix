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

    public static func make(
        width: Double,
        height: Double,
        safeFrame: RectD? = nil
    ) -> CalibrationControlLayout? {
        guard width.isFinite, height.isFinite, width >= 260, height >= 180 else {
            return nil
        }
        let safe = safeFrame ?? RectD(x: 0, y: 0, width: width, height: height)
        guard isValid(safeFrame: safe, width: width, height: height) else { return nil }

        let buttonWidth = min(104, floor((safe.width - 48 - 12) / 2))
        let save = RectD(x: safe.x + 24, y: safe.bottom - 66, width: buttonWidth, height: 42)
        let cancel = RectD(x: safe.x + 36 + buttonWidth, y: safe.bottom - 66, width: buttonWidth, height: 42)
        if safe.width < 378 {
            let instruction = RectD(x: safe.x + 24, y: safe.y + 24, width: safe.width - 48, height: 58)
            return CalibrationControlLayout(
                save: save,
                cancel: cancel,
                instruction: instruction,
                instructionDot: RectD(x: instruction.x + 16, y: instruction.y + 25, width: 8, height: 8),
                instructionText: RectD(
                    x: instruction.x + 34,
                    y: instruction.y,
                    width: instruction.width - 50,
                    height: 58
                ),
                instructionTextSize: 13
            )
        }
        let instruction = RectD(x: safe.x + 24, y: safe.y + 24, width: 330, height: 42)
        return CalibrationControlLayout(
            save: save,
            cancel: cancel,
            instruction: instruction,
            instructionDot: RectD(x: instruction.x + 16, y: instruction.y + 17, width: 8, height: 8),
            instructionText: RectD(x: instruction.x + 34, y: instruction.y, width: 280, height: 42),
            instructionTextSize: 15
        )
    }

    private static func isValid(safeFrame: RectD, width: Double, height: Double) -> Bool {
        safeFrame.x.isFinite && safeFrame.y.isFinite
            && safeFrame.width.isFinite && safeFrame.height.isFinite
            && safeFrame.x >= 0 && safeFrame.y >= 0
            && safeFrame.width >= 260 && safeFrame.height >= 180
            && safeFrame.right <= width && safeFrame.bottom <= height
    }
}
