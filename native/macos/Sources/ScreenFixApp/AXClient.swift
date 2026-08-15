import ApplicationServices
import Foundation

public enum AXClientError: Error, Equatable {
    case api(AXError)
    case missingValue
    case typeMismatch
    case nonFiniteGeometry
    case valueCreationFailed
}

public protocol AXClientCalling: AnyObject {
    func setMessagingTimeout(_ element: AXUIElement, seconds: Float) -> AXError
    func copyAttributeValue(_ element: AXUIElement, attribute: CFString) -> (AXError, CFTypeRef?)
    func isAttributeSettable(_ element: AXUIElement, attribute: CFString) -> (AXError, Bool)
    func setAttributeValue(
        _ element: AXUIElement,
        attribute: CFString,
        value: CFTypeRef
    ) -> AXError
    func makePointValue(_ point: CGPoint) -> CFTypeRef?
    func makeSizeValue(_ size: CGSize) -> CFTypeRef?
    func point(from value: CFTypeRef) -> CGPoint?
    func size(from value: CFTypeRef) -> CGSize?
}

public final class SystemAXClientCalls: AXClientCalling {
    public init() {}

    public func setMessagingTimeout(_ element: AXUIElement, seconds: Float) -> AXError {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    public func copyAttributeValue(
        _ element: AXUIElement,
        attribute: CFString
    ) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        return (error, value)
    }

    public func isAttributeSettable(
        _ element: AXUIElement,
        attribute: CFString
    ) -> (AXError, Bool) {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, attribute, &settable)
        return (error, settable.boolValue)
    }

    public func setAttributeValue(
        _ element: AXUIElement,
        attribute: CFString,
        value: CFTypeRef
    ) -> AXError {
        AXUIElementSetAttributeValue(element, attribute, value)
    }

    public func makePointValue(_ point: CGPoint) -> CFTypeRef? {
        var value = point
        return AXValueCreate(.cgPoint, &value)
    }

    public func makeSizeValue(_ size: CGSize) -> CFTypeRef? {
        var value = size
        return AXValueCreate(.cgSize, &value)
    }

    public func point(from value: CFTypeRef) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    public func size(from value: CFTypeRef) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }
}

public final class AXClient {
    public static let messagingTimeout: Float = 0.5

    private let calls: AXClientCalling

    public init(calls: AXClientCalling = SystemAXClientCalls()) {
        self.calls = calls
    }

    public func prepare(_ element: AXUIElement) throws {
        try requireSuccess(calls.setMessagingTimeout(element, seconds: Self.messagingTimeout))
    }

    public func string(_ element: AXUIElement, attribute: CFString) throws -> String {
        let value = try read(element, attribute: attribute)
        guard CFGetTypeID(value) == CFStringGetTypeID(), let result = value as? String else {
            throw AXClientError.typeMismatch
        }
        return result
    }

    public func bool(_ element: AXUIElement, attribute: CFString) throws -> Bool {
        let value = try read(element, attribute: attribute)
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
            throw AXClientError.typeMismatch
        }
        let boolean = unsafeBitCast(value, to: CFBoolean.self)
        return CFBooleanGetValue(boolean)
    }

    public func element(_ element: AXUIElement, attribute: CFString) throws -> AXUIElement {
        let value = try read(element, attribute: attribute)
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw AXClientError.typeMismatch
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    public func elements(_ element: AXUIElement, attribute: CFString) throws -> [AXUIElement] {
        let value = try read(element, attribute: attribute)
        guard CFGetTypeID(value) == CFArrayGetTypeID(), let result = value as? [AXUIElement] else {
            throw AXClientError.typeMismatch
        }
        return result
    }

    public func point(_ element: AXUIElement, attribute: CFString) throws -> CGPoint {
        let value = try read(element, attribute: attribute)
        guard let point = calls.point(from: value) else { throw AXClientError.typeMismatch }
        guard point.x.isFinite, point.y.isFinite else { throw AXClientError.nonFiniteGeometry }
        return point
    }

    public func size(_ element: AXUIElement, attribute: CFString) throws -> CGSize {
        let value = try read(element, attribute: attribute)
        guard let size = calls.size(from: value) else { throw AXClientError.typeMismatch }
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            throw AXClientError.nonFiniteGeometry
        }
        return size
    }

    public func isSettable(_ element: AXUIElement, attribute: CFString) throws -> Bool {
        try prepare(element)
        let result = calls.isAttributeSettable(element, attribute: attribute)
        try requireSuccess(result.0)
        return result.1
    }

    public func setPoint(_ element: AXUIElement, attribute: CFString, value: CGPoint) throws {
        guard value.x.isFinite, value.y.isFinite else { throw AXClientError.nonFiniteGeometry }
        guard let axValue = calls.makePointValue(value) else { throw AXClientError.valueCreationFailed }
        try set(element, attribute: attribute, value: axValue)
    }

    public func setSize(_ element: AXUIElement, attribute: CFString, value: CGSize) throws {
        guard value.width.isFinite, value.height.isFinite, value.width > 0, value.height > 0 else {
            throw AXClientError.nonFiniteGeometry
        }
        guard let axValue = calls.makeSizeValue(value) else { throw AXClientError.valueCreationFailed }
        try set(element, attribute: attribute, value: axValue)
    }

    private func read(_ element: AXUIElement, attribute: CFString) throws -> CFTypeRef {
        try prepare(element)
        let result = calls.copyAttributeValue(element, attribute: attribute)
        try requireSuccess(result.0)
        guard let value = result.1 else { throw AXClientError.missingValue }
        return value
    }

    private func set(_ element: AXUIElement, attribute: CFString, value: CFTypeRef) throws {
        try prepare(element)
        try requireSuccess(calls.setAttributeValue(element, attribute: attribute, value: value))
    }

    private func requireSuccess(_ error: AXError) throws {
        guard error == .success else { throw AXClientError.api(error) }
    }
}

public struct AXWindowIdentity: Hashable {
    public let pid: pid_t
    public let element: AXUIElement

    public init(pid: pid_t, element: AXUIElement) {
        self.pid = pid
        self.element = element
    }

    public static func == (lhs: AXWindowIdentity, rhs: AXWindowIdentity) -> Bool {
        lhs.pid == rhs.pid && CFEqual(lhs.element, rhs.element)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(CFHash(element))
    }
}
