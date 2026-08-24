import AppKit
import GhosttyKit
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    /// Initialize a pasteboard type from a MIME type string
    init?(mimeType: String) {
        // Explicit mappings for common MIME types
        switch mimeType {
        case "text/plain":
            self = .string
            return
        default:
            break
        }

        // Try to get UTType from MIME type
        guard let utType = UTType(mimeType: mimeType) else {
            // Fallback: use the MIME type directly as identifier
            self.init(mimeType)
            return
        }

        // Use the UTType's identifier
        self.init(utType.identifier)
    }
}

extension NSPasteboard {
    /// The pasteboard to used for Ghostty selection.
    static var ghosttySelection: NSPasteboard = {
        NSPasteboard(name: .init("com.mitchellh.ghostty.selection"))
    }()

    /// Gets the contents of the pasteboard as a string following a specific set of semantics.
    /// Does these things in order:
    /// - Tries to get the absolute filesystem path of the file in the pasteboard if there is one and ensures the file path is properly escaped.
    /// - Tries to get any string from the pasteboard.
    /// If all of the above fail, returns None.
    func getOpinionatedStringContents() -> String? {
        let strings = (pasteboardItems ?? []).compactMap { item in
            if let plist = item.propertyList(forType: .fileURL),
               let fileURL = NSURL(pasteboardPropertyList: plist, ofType: .fileURL) as URL?,
               fileURL.isFileURL {
                return Ghostty.Shell.escape(fileURL.path)
            } else {
                return item.string(forType: .string)
            }
        }

        guard !strings.isEmpty else {
            return nil
        }
        return strings.joined(separator: " ")
    }

    /// The data for the given MIME type, if the pasteboard can serve it.
    ///
    /// The canonical "text/plain" type uses the opinionated string
    /// contents so that e.g. copying a file yields its escaped path;
    /// this matches what pasting into the terminal produces. All other
    /// types are mapped through UTType.
    func ghosttyData(forMime mime: String) -> Data? {
        if mime == "text/plain" {
            guard let str = getOpinionatedStringContents() else { return nil }
            return Data(str.utf8)
        }

        guard let type = NSPasteboard.PasteboardType(mimeType: mime) else { return nil }
        return data(forType: type)
    }

    /// The MIME types available on the pasteboard, best-effort mapped
    /// from the pasteboard types. Types without a MIME mapping are not
    /// reported.
    func ghosttyAvailableMimes() -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        // Any text-like contents are reported under the canonical type,
        // matching what ghosttyData(forMime:) serves.
        if getOpinionatedStringContents() != nil {
            result.append("text/plain")
            seen.insert("text/plain")
        }

        for type in types ?? [] {
            guard let utType = UTType(type.rawValue),
                  let mime = utType.preferredMIMEType,
                  !seen.contains(mime) else { continue }
            seen.insert(mime)
            result.append(mime)
        }

        return result
    }

    /// The pasteboard for the Ghostty enum type.
    static func ghostty(_ clipboard: ghostty_clipboard_e) -> NSPasteboard? {
        switch clipboard {
        case GHOSTTY_CLIPBOARD_STANDARD:
            return Self.general

        case GHOSTTY_CLIPBOARD_SELECTION:
            return Self.ghosttySelection

        default:
            return nil
        }
    }
}
