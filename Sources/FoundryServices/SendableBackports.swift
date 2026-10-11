import Foundation

#if !compiler(>=6.2)
// FileManager is thread-safe for the filesystem operations used here, but only
// gained a Sendable conformance in the macOS 26 SDK. Backport it so services
// holding a FileManager can be checked Sendable on Swift 6.1.
extension FileManager: @retroactive @unchecked Sendable {}
#endif
