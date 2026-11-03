import XCTest
@testable import SmallBizWorkspace

/// "Require Face ID" (AppLockManager). The ways it could hurt an owner:
/// locking everyone on update, asking every time they glance at Messages,
/// and locking them out of their own records when Face ID can't be asked.
@MainActor
final class AppLockTests: XCTestCase {

    private var defaults: UserDefaults!
    private var answer: AppLockManager.AuthResult = .success
    private var asked = 0

    override func setUp() {
        defaults = UserDefaults(suiteName: "AppLockTests.\(UUID().uuidString)")
        answer = .success
        asked = 0
    }

    private func makeLock() -> AppLockManager {
        AppLockManager(defaults: defaults) { [unowned self] _ in
            asked += 1
            return answer
        }
    }

    // async like the rest: as a plain synchronous test on this @MainActor
    // class it crashed freeing the manager (malloc "pointer being freed was
    // not allocated"), an XCTest/main-actor teardown issue, not the lock's.
    func testOffByDefaultAndOpen() async {
        let lock = makeLock()
        XCTAssertFalse(lock.isEnabled)
        XCTAssertTrue(lock.isUnlocked)
        lock.didEnterBackground(at: .distantPast)
        lock.didBecomeActive()
        XCTAssertTrue(lock.isUnlocked, "never locks while off")
        XCTAssertFalse(lock.isObscured)
    }

    func testTurningOnAsksFirstAndStaysOffWhenNotConfirmed() async {
        let lock = makeLock()
        answer = .failed
        let turnedOn = await lock.setEnabled(true)
        XCTAssertFalse(turnedOn)
        XCTAssertFalse(lock.isEnabled)
        XCTAssertFalse(defaults.bool(forKey: AppLockManager.enabledKey))

        answer = .success
        let turnedOnNow = await lock.setEnabled(true)
        XCTAssertTrue(turnedOnNow)
        XCTAssertTrue(lock.isEnabled)
        XCTAssertTrue(lock.isUnlocked, "the owner who just turned it on isn't locked out")
        XCTAssertEqual(asked, 2)
    }

    func testLocksOnlyAfterTheGracePeriod() async {
        let lock = makeLock()
        _ = await lock.setEnabled(true)
        let left = Date()

        lock.didEnterBackground(at: left)
        XCTAssertTrue(lock.isObscured, "covered in the app switcher")
        lock.didBecomeActive(at: left.addingTimeInterval(AppLockManager.gracePeriod - 1))
        XCTAssertTrue(lock.isUnlocked, "a quick trip to Messages doesn't ask again")
        XCTAssertFalse(lock.isObscured)

        lock.didEnterBackground(at: left)
        lock.didBecomeActive(at: left.addingTimeInterval(AppLockManager.gracePeriod + 1))
        XCTAssertFalse(lock.isUnlocked)
    }

    func testRemembersAcrossLaunches() async {
        _ = await makeLock().setEnabled(true)
        let relaunched = makeLock()
        XCTAssertTrue(relaunched.isEnabled)
        XCTAssertFalse(relaunched.isUnlocked, "locked on open")
    }

    func testUnlockStaysLockedOnCancelAndOpensWhenNothingCanBeAsked() async {
        _ = await makeLock().setEnabled(true)
        let lock = makeLock()

        answer = .failed
        await lock.unlock()
        XCTAssertFalse(lock.isUnlocked)

        answer = .unavailable   // passcode removed from the iPhone since
        await lock.unlock()
        XCTAssertTrue(lock.isUnlocked, "never locked out of their own records")
    }

    func testTurningOffUnlocks() async {
        _ = await makeLock().setEnabled(true)
        let lock = makeLock()
        let turnedOff = await lock.setEnabled(false)
        XCTAssertTrue(turnedOff)
        XCTAssertFalse(lock.isEnabled)
        XCTAssertTrue(lock.isUnlocked)
    }
}
