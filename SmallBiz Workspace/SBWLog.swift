import Foundation
import OSLog

/// Application logging.
///
/// The app had 126 `print` calls and three uses of `Logger`. `print` does not
/// reach the unified log in a release build, so when a user reported that an
/// invoice would not sync there was no way to find out why — the diagnostics
/// existed, but only on a developer's console during a debug run.
///
/// These categories show up as filters in Console.app and in a sysdiagnose, so a
/// support report can be narrowed to `Portal` or `Payments` without wading
/// through everything else.
enum SBWLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "SmallBizWorkspace"

    /// Startup, migrations, business switching.
    static let launch = Logger(subsystem: subsystem, category: "Launch")
    /// Anything crossing the network to the portal backend.
    static let portal = Logger(subsystem: subsystem, category: "Portal")
    /// Provider setup, checkout, reconciliation.
    static let payments = Logger(subsystem: subsystem, category: "Payments")
    /// Push registration, the inbox, local reminders.
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    /// The document store and file index.
    static let files = Logger(subsystem: subsystem, category: "Files")
    /// SwiftData reads and writes outside the above.
    static let data = Logger(subsystem: subsystem, category: "Data")
    /// View-level events.
    static let ui = Logger(subsystem: subsystem, category: "UI")
}

extension Logger {
    /// A normal diagnostic, readable in a release build.
    ///
    /// String interpolation into `Logger` defaults to `.private`, which redacts
    /// the value in release — the failure mode being a log full of `<private>`
    /// that is no more useful than the `print` it replaced. These messages carry
    /// control flow, identifiers and error descriptions rather than customer
    /// data, so they are marked public deliberately.
    ///
    /// Do not pass a client's name, email, address, or an invoice amount through
    /// here. Log the id instead and look the record up.
    func note(_ message: @autoclosure () -> String) {
        let text = message()
        info("\(text, privacy: .public)")
    }

    /// Something went wrong and someone may have to explain it later.
    func problem(_ message: @autoclosure () -> String) {
        let text = message()
        error("\(text, privacy: .public)")
    }
}
