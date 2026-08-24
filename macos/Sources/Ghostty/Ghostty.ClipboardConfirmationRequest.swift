import Foundation
import GhosttyKit

extension Ghostty {
    /// The type of a clipboard request.
    enum ClipboardRequest {
        /// A direct paste of clipboard contents.
        case paste

        /// An application is attempting to read from the clipboard using OSC 52.
        case osc_52_read

        /// An application is attempting to write to the clipboard using OSC 52.
        case osc_52_write

        /// An application is attempting to read from the clipboard using
        /// the Kitty clipboard protocol (OSC 5522).
        case kitty_read

        /// The text to show in the clipboard confirmation prompt for this request.
        func text() -> String {
            switch self {
            case .paste:
                return """
                Pasting this text to the terminal may be dangerous as it looks like some commands may be executed.
                """
            case .osc_52_read, .kitty_read:
                return """
                An application is attempting to read from the clipboard.
                The current clipboard contents are shown below.
                """
            case .osc_52_write:
                return """
                An application is attempting to write to the clipboard.
                The content to write is shown below.
                """
            }
        }

        static func from(request: ghostty_clipboard_request_e) -> ClipboardRequest? {
            switch request {
            case GHOSTTY_CLIPBOARD_REQUEST_PASTE:
                return .paste
            case GHOSTTY_CLIPBOARD_REQUEST_OSC_52_READ:
                return .osc_52_read
            case GHOSTTY_CLIPBOARD_REQUEST_OSC_52_WRITE:
                return .osc_52_write
            case GHOSTTY_CLIPBOARD_REQUEST_KITTY_READ:
                return .kitty_read
            default:
                return nil
            }
        }
    }

    /// A one-shot clipboard confirmation originating from libghostty.
    ///
    /// This object owns the callback state until it is completed or cancelled.
    /// Dropping an unresolved request schedules its cancellation so raw
    /// libghostty state cannot leak when no UI is available to handle the
    /// notification. Cancellation is deferred because notification delivery
    /// occurs from inside the libghostty callback that created the request.
    final class ClipboardConfirmationRequest {
        private(set) weak var surface: SurfaceView?

        /// The textual preview of the clipboard contents shown in the
        /// confirmation dialog. The actual representations served on
        /// confirmation are held by the completion.
        let contents: String

        let kind: ClipboardRequest

        /// Called exactly once with whether the user confirmed the request.
        private var completion: ((SurfaceView, Bool) -> Void)?

        init(
            surface: SurfaceView,
            contents: String,
            kind: ClipboardRequest,
            completion: @escaping (SurfaceView, Bool) -> Void
        ) {
            self.surface = surface
            self.contents = contents
            self.kind = kind
            self.completion = completion
        }

        deinit {
            guard let surface, let completion else { return }
            self.completion = nil
            DispatchQueue.main.async {
                completion(surface, false)
            }
        }

        /// Complete the request with the displayed clipboard contents.
        func complete() {
            finish(true)
        }

        /// Cancel the request, denying access to the clipboard contents.
        func cancel() {
            finish(false)
        }

        /// Cancel using the owning surface explicitly. SurfaceView uses this
        /// for replacement and teardown because its weak reference is already
        /// nil during the owner's deinitialization.
        func cancel(from surface: SurfaceView) {
            finish(false, on: surface)
        }

        private func finish(
            _ confirmed: Bool,
            on explicitSurface: SurfaceView? = nil
        ) {
            guard let surface = explicitSurface ?? self.surface,
                  let completion else {
                self.completion = nil
                return
            }
            self.completion = nil
            completion(surface, confirmed)
        }
    }
}
