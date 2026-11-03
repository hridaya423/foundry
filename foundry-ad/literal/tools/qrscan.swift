import Foundation
import Vision
import AppKit

for path in CommandLine.arguments.dropFirst() {
    guard let image = NSImage(contentsOfFile: path),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("\(path): unreadable")
        continue
    }
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    try? VNImageRequestHandler(cgImage: cg).perform([request])
    let payloads = (request.results ?? []).compactMap { $0.payloadStringValue }
    print("\(path): \(payloads.isEmpty ? "NO QR" : payloads.joined(separator: " | "))")
}
