import AppKit

/// Pasted images. The app stores them in its database (see EntryStore) and links
/// them as `glasspad://image/<id>`; older `file://` links still render.
enum ImageStore {
    struct Backend {
        var save: (Data) -> String?
        var load: (String) -> Data?
    }

    /// In-memory until the app installs the database-backed one.
    static var backend: Backend = {
        var images: [String: Data] = [:]
        return Backend(
            save: { data in
                let id = UUID().uuidString.lowercased()
                images[id] = data
                return id
            },
            load: { images[$0] })
    }()

    static let scheme = "glasspad"

    static let maxDisplayHeight: CGFloat = 320
    private static let cache = NSCache<NSURL, NSImage>()

    /// A local image referenced from an entry, loaded once and cached.
    static func image(at url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let image: NSImage?
        if url.scheme == scheme, url.host == "image" {
            image = backend.load(url.lastPathComponent).flatMap(NSImage.init(data:))
        } else if url.isFileURL {
            image = NSImage(contentsOf: url)
        } else {
            return nil
        }
        guard let image else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    static let minDisplayWidth: CGFloat = 40

    /// The image's size at `requested` width (from `![|300](…)`), or by default scaled
    /// down to `maxDisplayHeight`; either way no wider than `available`.
    static func displaySize(of image: NSImage, requested: CGFloat?, available: CGFloat) -> NSSize {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return .zero }
        var scale = requested.map { $0 / size.width } ?? min(1, maxDisplayHeight / size.height)
        scale = min(scale, available / size.width)
        return NSSize(width: size.width * scale, height: size.height * scale)
    }

    /// Markdown for an image, with the Obsidian-style `|width` suffix when sized.
    static func link(to url: URL, width: Int?) -> String {
        "![\(width.map { "|\($0)" } ?? "")](\(url.absoluteString))"
    }

    /// True when the pasteboard holds an image and no plain text to prefer over it.
    static func hasImage(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.string(forType: .string) == nil && NSImage.canInit(with: pasteboard)
    }

    /// Saves the pasteboard image and returns `![](glasspad://image/<id>)`, or nil.
    static func markdownLink(from pasteboard: NSPasteboard) -> String? {
        guard hasImage(pasteboard),
              let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
              let id = backend.save(png),
              let url = URL(string: "\(scheme)://image/\(id)")
        else { return nil }
        return link(to: url, width: nil)
    }
}

/// The value of `.gpImage`: which image a line shows and how wide.
final class ImageRef: NSObject {
    let url: URL
    let width: CGFloat?

    init(url: URL, width: CGFloat?) {
        self.url = url
        self.width = width
    }
}
