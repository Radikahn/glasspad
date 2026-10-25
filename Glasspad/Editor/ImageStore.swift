import AppKit

/// Saves pasted images as PNGs in ~/Library/Application Support/Glasspad/Images
/// so entries can reference them with a markdown image link.
enum ImageStore {
    static func directory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = support.appendingPathComponent("Glasspad/Images", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// True when the pasteboard holds an image and no plain text to prefer over it.
    static func hasImage(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.string(forType: .string) == nil && NSImage.canInit(with: pasteboard)
    }

    /// Writes the pasteboard image to disk and returns `![](file:///…)`, or nil.
    static func markdownLink(from pasteboard: NSPasteboard) -> String? {
        guard hasImage(pasteboard),
              let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
              let dir = try? directory()
        else { return nil }
        let url = dir.appendingPathComponent(UUID().uuidString.lowercased() + ".png")
        do { try png.write(to: url) } catch { return nil }
        return "![](\(url.absoluteString))"
    }
}
