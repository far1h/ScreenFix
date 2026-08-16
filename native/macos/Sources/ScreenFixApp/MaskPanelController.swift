import AppKit
import ScreenFixCore

public enum MaskPanelError: Error {
    case invalidFrames
    case mouseEventsEnabled
    case notVisible
}

public protocol MaskWindow: AnyObject {
    var frame: NSRect { get }
    var ignoresMouseEvents: Bool { get }
    func orderAndVerify() throws
    func close()
}

public final class MaskPanel: NSPanel, MaskWindow {
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    public func orderAndVerify() throws {
        orderFrontRegardless()
        guard isVisible else { throw MaskPanelError.notVisible }
    }
}

public struct MaskPanelFactory {
    public init() {}

    public func make(frame: NSRect) -> MaskPanel {
        let panel = MaskPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.isReleasedWhenClosed = false
        return panel
    }
}

public final class PreparedMasks {
    public let windows: [MaskWindow]
    private var consumed = false

    init(windows: [MaskWindow]) {
        self.windows = windows
    }

    func take() -> [MaskWindow]? {
        guard !consumed else { return nil }
        consumed = true
        return windows
    }
}

public final class MaskPanelController {
    public typealias Factory = (NSRect) throws -> MaskWindow

    private let factory: Factory
    private var committed: [MaskWindow]

    public init(
        factory: @escaping Factory = { MaskPanelFactory().make(frame: $0) },
        initialCommitted: [MaskWindow] = []
    ) {
        self.factory = factory
        committed = initialCommitted
    }

    public var committedCount: Int { committed.count }
    public var committedWindowsIgnoreMouseEvents: Bool {
        committed.allSatisfy(\.ignoresMouseEvents)
    }

    public func prepare(frames: [RectD], screenFrame: NSRect) throws -> PreparedMasks {
        guard frames.count == 3,
              frames.allSatisfy({ frame in
                  frame.x.isFinite
                      && frame.y.isFinite
                      && frame.width.isFinite
                      && frame.height.isFinite
                      && frame.width > 0
                      && frame.height > 0
              }) else {
            throw MaskPanelError.invalidFrames
        }

        var candidates: [MaskWindow] = []
        do {
            for frame in frames {
                let appKitFrame = NSRect(
                    x: screenFrame.minX + frame.x,
                    y: screenFrame.maxY - frame.y - frame.height,
                    width: frame.width,
                    height: frame.height
                )
                let candidate = try factory(appKitFrame)
                candidates.append(candidate)
                guard candidate.ignoresMouseEvents else {
                    throw MaskPanelError.mouseEventsEnabled
                }
            }
            return PreparedMasks(windows: candidates)
        } catch {
            candidates.forEach { $0.close() }
            throw error
        }
    }

    public func commit(
        _ prepared: PreparedMasks,
        beforeRetire: () throws -> Void = {}
    ) throws {
        guard let candidates = prepared.take() else { return }
        do {
            for candidate in candidates {
                try candidate.orderAndVerify()
            }
            try beforeRetire()
        } catch {
            candidates.forEach { $0.close() }
            throw error
        }

        let old = committed
        committed = candidates
        old.forEach { $0.close() }
    }

    public func discard(_ prepared: PreparedMasks) {
        guard let candidates = prepared.take() else { return }
        candidates.forEach { $0.close() }
    }

    public func removeAll() {
        let old = committed
        committed = []
        old.forEach { $0.close() }
    }
}
