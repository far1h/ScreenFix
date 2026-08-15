import ApplicationServices
import Foundation
import ScreenFixApp

private final class FakeAXCalls: AXClientCalling {
    var timeoutResult = AXError.success
    var copyResult: (AXError, CFTypeRef?) = (.success, nil)
    var settableResult: (AXError, Bool) = (.success, true)
    var setResult = AXError.success
    var madePointValue: CFTypeRef?
    var madeSizeValue: CFTypeRef?
    var decodedPoint: CGPoint?
    var decodedSize: CGSize?
    private(set) var timeouts: [Float] = []
    private(set) var log: [String] = []
    private(set) var setValues: [CFTypeRef] = []

    func setMessagingTimeout(_ element: AXUIElement, seconds: Float) -> AXError {
        log.append("timeout")
        timeouts.append(seconds)
        return timeoutResult
    }

    func copyAttributeValue(_ element: AXUIElement, attribute: CFString) -> (AXError, CFTypeRef?) {
        log.append("copy")
        return copyResult
    }

    func isAttributeSettable(_ element: AXUIElement, attribute: CFString) -> (AXError, Bool) {
        log.append("settable")
        return settableResult
    }

    func setAttributeValue(
        _ element: AXUIElement,
        attribute: CFString,
        value: CFTypeRef
    ) -> AXError {
        log.append("set")
        setValues.append(value)
        return setResult
    }

    func makePointValue(_ point: CGPoint) -> CFTypeRef? {
        log.append("make-point")
        return madePointValue
    }

    func makeSizeValue(_ size: CGSize) -> CFTypeRef? {
        log.append("make-size")
        return madeSizeValue
    }

    func point(from value: CFTypeRef) -> CGPoint? {
        log.append("decode-point")
        return decodedPoint
    }

    func size(from value: CFTypeRef) -> CGSize? {
        log.append("decode-size")
        return decodedSize
    }
}

private func axElement() -> AXUIElement {
    AXUIElementCreateApplication(getpid())
}

private func expectAXError(_ expected: AXClientError, _ body: () throws -> Void) throws {
    do {
        try body()
    } catch let error as AXClientError {
        try expectEqual(error, expected)
        return
    }
    throw TestFailure(description: "expected AXClientError \(expected)")
}

let axClientTests: [TestCase] = [
    TestCase(name: "AXClient applies the exact timeout before every remote operation") {
        let calls = FakeAXCalls()
        calls.copyResult = (.success, "AXWindow" as CFString)
        let client = AXClient(calls: calls)
        let element = axElement()

        _ = try client.string(element, attribute: kAXRoleAttribute as CFString)
        _ = try client.isSettable(element, attribute: kAXPositionAttribute as CFString)

        try expectEqual(calls.log, ["timeout", "copy", "timeout", "settable"])
        try expectEqual(calls.timeouts, [0.5, 0.5])
    },
    TestCase(name: "AXClient timeout failure prevents the remote operation") {
        let calls = FakeAXCalls()
        calls.timeoutResult = .cannotComplete
        let client = AXClient(calls: calls)

        try expectAXError(.api(.cannotComplete)) {
            _ = try client.string(axElement(), attribute: kAXRoleAttribute as CFString)
        }
        try expectEqual(calls.log, ["timeout"])
    },
    TestCase(name: "AXClient reads typed string boolean and element values") {
        let calls = FakeAXCalls()
        let client = AXClient(calls: calls)
        let element = axElement()

        calls.copyResult = (.success, "AXStandardWindow" as CFString)
        try expectEqual(try client.string(element, attribute: kAXSubroleAttribute as CFString), "AXStandardWindow")

        calls.copyResult = (.success, kCFBooleanTrue)
        let minimized = try client.bool(element, attribute: kAXMinimizedAttribute as CFString)
        try expect(minimized)

        let child = AXUIElementCreateApplication(getpid())
        calls.copyResult = (.success, child)
        let readChild = try client.element(element, attribute: kAXFocusedWindowAttribute as CFString)
        try expect(CFEqual(readChild, child))

        calls.copyResult = (.success, [child] as CFArray)
        let children = try client.elements(element, attribute: kAXWindowsAttribute as CFString)
        try expectEqual(children.count, 1)
        try expect(CFEqual(children[0], child))
    },
    TestCase(name: "AXClient decodes finite point and size values") {
        let calls = FakeAXCalls()
        calls.copyResult = (.success, NSObject())
        calls.decodedPoint = CGPoint(x: -300, y: 25)
        calls.decodedSize = CGSize(width: 500, height: 400)
        let client = AXClient(calls: calls)
        let element = axElement()

        try expectEqual(try client.point(element, attribute: kAXPositionAttribute as CFString), CGPoint(x: -300, y: 25))
        try expectEqual(try client.size(element, attribute: kAXSizeAttribute as CFString), CGSize(width: 500, height: 400))
    },
    TestCase(name: "AXClient writes point and size AX values after timeout") {
        let calls = FakeAXCalls()
        let pointValue = NSObject()
        let sizeValue = NSObject()
        calls.madePointValue = pointValue
        calls.madeSizeValue = sizeValue
        let client = AXClient(calls: calls)
        let element = axElement()

        try client.setPoint(element, attribute: kAXPositionAttribute as CFString, value: CGPoint(x: 10, y: 20))
        try client.setSize(element, attribute: kAXSizeAttribute as CFString, value: CGSize(width: 300, height: 200))

        try expectEqual(calls.log, ["make-point", "timeout", "set", "make-size", "timeout", "set"])
        try expect(calls.setValues[0] === pointValue)
        try expect(calls.setValues[1] === sizeValue)
    },
    TestCase(name: "AXClient maps missing mismatched and API failures exactly") {
        let calls = FakeAXCalls()
        let client = AXClient(calls: calls)
        let element = axElement()

        calls.copyResult = (.success, nil)
        try expectAXError(.missingValue) {
            _ = try client.string(element, attribute: kAXRoleAttribute as CFString)
        }
        calls.copyResult = (.success, kCFBooleanTrue)
        try expectAXError(.typeMismatch) {
            _ = try client.string(element, attribute: kAXRoleAttribute as CFString)
        }
        calls.copyResult = (.invalidUIElement, nil)
        try expectAXError(.api(.invalidUIElement)) {
            _ = try client.string(element, attribute: kAXRoleAttribute as CFString)
        }
        calls.settableResult = (.apiDisabled, false)
        try expectAXError(.api(.apiDisabled)) {
            _ = try client.isSettable(element, attribute: kAXPositionAttribute as CFString)
        }
    },
    TestCase(name: "AXClient rejects nonfinite geometry and value construction failure") {
        let calls = FakeAXCalls()
        calls.copyResult = (.success, NSObject())
        calls.decodedPoint = CGPoint(x: CGFloat.nan, y: 0)
        calls.decodedSize = CGSize(width: CGFloat.infinity, height: 20)
        let client = AXClient(calls: calls)
        let element = axElement()

        try expectAXError(.nonFiniteGeometry) {
            _ = try client.point(element, attribute: kAXPositionAttribute as CFString)
        }
        try expectAXError(.nonFiniteGeometry) {
            _ = try client.size(element, attribute: kAXSizeAttribute as CFString)
        }
        try expectAXError(.nonFiniteGeometry) {
            try client.setPoint(
                element,
                attribute: kAXPositionAttribute as CFString,
                value: CGPoint(x: CGFloat.nan, y: 0)
            )
        }
        try expectAXError(.valueCreationFailed) {
            try client.setSize(element, attribute: kAXSizeAttribute as CFString, value: CGSize(width: 20, height: 30))
        }
    },
    TestCase(name: "AXWindowIdentity uses PID and Core Foundation identity") {
        let first = AXUIElementCreateApplication(getpid())
        let equal = AXUIElementCreateApplication(getpid())
        let one = AXWindowIdentity(pid: getpid(), element: first)
        let two = AXWindowIdentity(pid: getpid(), element: equal)
        let otherPID = AXWindowIdentity(pid: getpid() + 1, element: equal)

        try expectEqual(one, two)
        try expect(one != otherPID)
        try expectEqual(Set([one, two, otherPID]).count, 2)
    },
]
