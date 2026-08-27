import Foundation

extension URL {
    /// The decoded path with trailing separators removed, except for the root path.
    var pathWithoutTrailingSlash: String {
        var result = path(percentEncoded: false)
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
