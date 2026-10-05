import XCTest
@testable import KeepAwakeCore

final class KeepAwakeCoreTests: XCTestCase {
    func testSystemWideState() throws {
        XCTAssertTrue(try SystemSleepService.parseDisabled("System-wide power settings:\n SleepDisabled\t1\nCurrently in use:\n sleep 0"))
        XCTAssertFalse(try SystemSleepService.parseDisabled(" SleepDisabled 0\n sleep 1"))
        XCTAssertTrue(try SystemSleepService.parseDisabled("disablesleep 1"))
    }
    func testUnknownOrInvalidStateIsNotOff() {
        for output in ["", "System-wide power settings:", "sleep 0", "SleepDisabled 2", "SleepDisabled 1 extra", "SleepDisabled 1\nSleepDisabled 0"] {
            XCTAssertThrowsError(try SystemSleepService.parseDisabled(output))
        }
    }
    func testAuthorizationCommandHasOnlyFixedBooleanInput() {
        XCTAssertEqual(AppleScriptSleepAuthorizer.script(disabled: true), "do shell script \"/usr/bin/pmset -a disablesleep 1\" with administrator privileges")
        XCTAssertEqual(AppleScriptSleepAuthorizer.script(disabled: false), "do shell script \"/usr/bin/pmset -a disablesleep 0\" with administrator privileges")
    }
    func testOptionsAndOwnerLifetime() {
        var options = CaffeinateOptions()
        XCTAssertEqual(options.arguments(ownerPID: 123), ["-d", "-i", "-m", "-s", "-u", "-w", "123"])
        options.display = false
        options.idleSystem = false
        options.disk = false
        options.acSystem = false
        options.userActivity = false
        XCTAssertFalse(options.isValid)
        XCTAssertEqual(options.flags, [])
        options.idleSystem = true
        XCTAssertEqual(options.flags, ["-i"])
    }
    func testRunnerCapturesOutputAndFailureStatus() async throws {
        let success = try await CommandRunner.run("/usr/bin/printf", arguments: ["hello"])
        XCTAssertEqual(success.status, 0)
        XCTAssertEqual(success.output, "hello")
        let failure = try await CommandRunner.run("/usr/bin/false", arguments: [])
        XCTAssertNotEqual(failure.status, 0)
    }
}

final class RuntimeTests: XCTestCase {
    func testReadActualSystemState() async throws {
        _ = try await SystemSleepService().readDisabled()
    }

    @MainActor
    func testCaffeinateOwnershipAndStop() async throws {
        let controller = CaffeinateController()
        XCTAssertFalse(controller.isRunning)
        let options = CaffeinateOptions(display: false, idleSystem: true, disk: false, acSystem: false, userActivity: false)
        let independent = Process()
        independent.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        independent.arguments = ["-i", "-t", "10"]
        try independent.run()
        defer { if independent.isRunning { independent.terminate() } }
        controller.start(options: options)
        defer { controller.stopForQuit() }
        XCTAssertTrue(controller.isRunning)
        XCTAssertNotNil(controller.pid)
        let firstPID = controller.pid
        controller.start(options: options)
        XCTAssertEqual(controller.pid, firstPID)
        controller.stop()
        for _ in 0..<100 {
            if !controller.isRunning { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(controller.isRunning)
        XCTAssertNil(controller.pid)
        XCTAssertNil(controller.errorMessage)
        XCTAssertTrue(independent.isRunning)
    }
}

final class OwlStateTests: XCTestCase {
    func testModeCombinationsAndUnknownState() {
        XCTAssertEqual(OwlState.resolve(systemDisabled: false, caffeinate: false), .sleeping)
        XCTAssertEqual(OwlState.resolve(systemDisabled: false, caffeinate: true), .caffeinated)
        XCTAssertEqual(OwlState.resolve(systemDisabled: true, caffeinate: false), .wideAwake)
        XCTAssertEqual(OwlState.resolve(systemDisabled: true, caffeinate: true), .wideAwake)
        XCTAssertEqual(OwlState.resolve(systemDisabled: nil, caffeinate: false), .unknown)
        XCTAssertEqual(OwlState.resolve(systemDisabled: nil, caffeinate: true), .caffeinated)
    }
}
