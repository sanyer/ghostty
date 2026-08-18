import AppKit
import Carbon

class KeyboardLayout {
    /// Return a string ID of the current keyboard input source.
    static var id: String? {
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let sourceIdPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let sourceId = unsafeBitCast(sourceIdPointer, to: CFString.self)
            return sourceId as String
        }

        return nil
    }

    /// Translate a physical keycode for use as a menu key equivalent.
    ///
    /// Must be called on the main thread because Text Input Sources APIs are not thread-safe.
    static func character(
        for keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> Character? {
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = unsafeBitCast(dataPointer, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return nil }

        // Command can select a distinct layout table. Other modifiers remain
        // separate in the menu's modifier mask and must not affect this character.
        let carbonModifiers = modifiers.contains(.command) ? UInt32(cmdKey) >> 8 : 0

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                carbonModifiers,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                characters.count,
                &length,
                &characters)
        }
        guard status == noErr else { return nil }

        let result = String(utf16CodeUnits: characters, count: length)
        guard result.count == 1 else { return nil }
        return result.first
    }
}
