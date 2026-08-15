import Darwin
import Foundation

struct TestCase {
    let name: String
    let body: () throws -> Void
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "expectation failed") throws {
    guard condition() else { throw TestFailure(description: message) }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "values differ") throws {
    guard actual == expected else {
        throw TestFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

func expectEqual(
    _ actual: Double,
    _ expected: Double,
    accuracy: Double,
    _ message: String = "values differ"
) throws {
    guard abs(actual - expected) <= accuracy else {
        throw TestFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

func expectThrows(_ body: () throws -> Void) throws {
    do {
        try body()
    } catch {
        return
    }
    throw TestFailure(description: "expected an error")
}

func runTests(_ tests: [TestCase]) -> Never {
    let arguments = Array(CommandLine.arguments.dropFirst())
    var filter: String?
    if arguments.count == 2, arguments[0] == "--filter" {
        filter = arguments[1]
    } else if !arguments.isEmpty {
        print("FAIL invalid arguments")
        print("Executed 0 tests, 1 failures")
        exit(1)
    }

    let selected = tests.filter { test in
        filter.map { test.name.localizedCaseInsensitiveContains($0) } ?? true
    }
    guard !selected.isEmpty else {
        print("FAIL no matching tests")
        print("Executed 0 tests, 1 failures")
        exit(1)
    }

    var failures = 0
    for test in selected {
        do {
            try test.body()
            print("PASS \(test.name)")
        } catch {
            failures += 1
            print("FAIL \(test.name): \(error)")
        }
    }
    print("Executed \(selected.count) tests, \(failures) failures")
    exit(failures == 0 ? 0 : 1)
}
