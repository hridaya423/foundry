// Foreground cutout with Apple Vision (VNGenerateForegroundInstanceMaskRequest).
// usage: swift tools/cutout.swift <in.jpg> <out.png>   -> RGBA PNG, background transparent
import AppKit
import CoreImage
import Vision

let args = CommandLine.arguments
guard args.count == 3, let src = CIImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    print("usage: cutout.swift in out.png"); exit(1)
}
let handler = VNImageRequestHandler(ciImage: src)
let req = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([req])
guard let obs = req.results?.first else { print("no foreground found"); exit(2) }
let mask = try obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler)
let maskImage = CIImage(cvPixelBuffer: mask)
let clear = CIImage(color: .clear).cropped(to: src.extent)
let out = src.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: maskImage])
let ctx = CIContext()
try ctx.writePNGRepresentation(of: out, to: URL(fileURLWithPath: args[2]), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
print("ok \(Int(src.extent.width))x\(Int(src.extent.height))")
