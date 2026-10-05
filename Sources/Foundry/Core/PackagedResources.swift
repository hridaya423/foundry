import Foundation

private final class PackagedResourceFinder {}

extension Bundle {
    /// `Bundle.module` only checks the executable's directory and the `.build`
    /// path baked in at compile time, so it traps in the installed app once the
    /// source checkout is cleaned. This looks where the bundle actually ships.
    static let packagedResources: Bundle? = [
        Bundle.main,
        Bundle(for: PackagedResourceFinder.self),
    ]
    .lazy
    .flatMap { [$0.resourceURL, $0.bundleURL, $0.bundleURL.deletingLastPathComponent()].compactMap { $0 } }
    .map { $0.appendingPathComponent("Foundry_Foundry.bundle") }
    .compactMap(Bundle.init(url:))
    .first
}
