import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Album covers, as the phones want them and the window shows them: 600 px square JPEGs, in the app's caches, named after a hash of
/// the JPEG (as Legato Desktop names them on the phone), so a changed cover is a new file.
enum Covers {
    static let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "Covers", directoryHint: .isDirectory)

    /// The cover for a track: the picture in the file, else cover.jpg, folder.png and the like beside it. Its path, or nil if there is
    /// none (or it couldn't be read).
    static func cover(for file: URL, in dir: URL = folder) -> String? {
        guard let image = Tags.picture(at: file) ?? folderImage(beside: file), let jpeg = square(image) else { return nil }
        let name = hash16(jpeg) + ".jpg"
        let url = dir.appending(path: name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            guard (try? jpeg.write(to: url, options: .atomic)) != nil else { return nil }
        }
        return url.path
    }

    private static let names = ["cover", "folder", "front", "album"]

    private static func folderImage(beside file: URL) -> Data? {
        let dir = file.deletingLastPathComponent()
        let found = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).first { name in
            let url = URL(filePath: name)
            return ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased())
                && names.contains(url.deletingPathExtension().lastPathComponent.lowercased())
        }
        return found.flatMap { try? Data(contentsOf: dir.appending(path: $0)) }
    }

    /// 600 × 600, cropped to fill, as JPEG
    static func square(_ data: Data, side: Int = 600) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let scale = max(Double(side) / Double(image.width), Double(side) / Double(image.height))
        let w = Double(image.width) * scale, h = Double(image.height) * scale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (Double(side) - w) / 2, y: (Double(side) - h) / 2, width: w, height: h))
        guard let squared = context.makeImage() else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, squared, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }
}

/// The first 16 hex digits of the SHA-1: Legato Desktop's track ids (of the path) and cover names (of the JPEG).
func hash16(_ data: Data) -> String {
    Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(16).description
}

/// A track's id: as Legato Desktop makes it, from the path (composed Unicode, as macOS's decomposed names are not), so a phone synced
/// from either app keeps its songs.
func syncId(_ path: String) -> String {
    hash16(Data(pathKey(path).utf8))
}

/// A path as paths are compared: macOS hands out decomposed (NFD) names, and a playlist written elsewhere usually has composed ones.
func pathKey(_ path: String) -> String {
    (URL(filePath: path).standardized.path as NSString).precomposedStringWithCanonicalMapping
}
