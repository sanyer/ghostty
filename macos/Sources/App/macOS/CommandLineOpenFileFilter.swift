import Foundation

/// Filters the open-file events AppKit creates from command arguments following
/// `-e`. Each matching event is consumed once so later requests to open the same
/// file are handled normally.
final class CommandLineOpenFileFilter {
    private let workingDirectory: String
    private var filesToIgnore: Set<String>

    init(
        arguments: [String],
        workingDirectory: String,
        fileExists: (String) -> Bool
    ) {
        self.workingDirectory = workingDirectory

        guard let commandIndex = arguments.firstIndex(of: "-e") else {
            self.filesToIgnore = []
            return
        }

        // Ghostty treats every argument following `-e` as part of the child
        // command. Existing paths in that suffix are the arguments AppKit can
        // independently turn into open-file events.
        self.filesToIgnore = Set(arguments[arguments.index(after: commandIndex)...]
            .compactMap { argument in
                // Command arguments can be relative, while AppKit normally
                // reports absolute paths for the corresponding open event.
                let path = Self.absolutePath(argument, relativeTo: workingDirectory)

                // Ignore only paths that exist during launch. A non-path
                // argument cannot produce the duplicate event and retaining it
                // could suppress a legitimate open if that path appears later.
                return fileExists(path) ? path : nil
            })
    }

    func shouldIgnore(_ filename: String) -> Bool {
        let path = Self.absolutePath(filename, relativeTo: workingDirectory)

        // Consume each match once. Later requests to open the same file may
        // come from Finder, the Dock, or another invocation and must proceed.
        return filesToIgnore.remove(path) != nil
    }

    private static func absolutePath(_ path: String, relativeTo workingDirectory: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let absolute = if (expanded as NSString).isAbsolutePath {
            expanded
        } else {
            (workingDirectory as NSString).appendingPathComponent(expanded)
        }

        return (absolute as NSString).standardizingPath
    }
}
