import AVFoundation
import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fatalError("usage: swift gen-thumb.swift <input.mp4> <output.jpg>")
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])

let asset = AVURLAsset(url: input)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: 360, height: 640)

let image = try generator.copyCGImage(at: .zero, actualTime: nil)
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
    fatalError("failed to encode jpeg")
}
try data.write(to: output)
print("written \(output.path)")
