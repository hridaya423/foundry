import AppKit

// NSImage gained a Sendable conformance in the macOS 26 SDK (Swift 6.2+
// toolchains). The repo also builds on Xcode 16.3 / Swift 6.1, where icon
// pipelines legitimately hand immutable NSImages across actors — declare
// the same conformance there. NSImage is documented thread-safe for
// concurrent reading.
#if compiler(<6.2)
extension NSImage: @retroactive @unchecked Sendable {}
#endif
