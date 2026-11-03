import Foundation

#if compiler(<7)
// FileManager is thread-safe for the filesystem operations used here, but has
// no Sendable conformance in the SDKs we build against (16.3 → 27.0). Backport
// it so services holding a FileManager can be checked Sendable.
extension FileManager: @retroactive @unchecked Sendable {}
#endif
