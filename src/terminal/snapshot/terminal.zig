//! TERMINAL record payload encoding.
//!
//! One TERMINAL record contains terminal-wide state shared by every screen. It
//! is the first record in a snapshot and declares which SCREEN sequences follow
//! it. Screen contents, cursors, and history are encoded by `screen.zig` and
//! `history.zig`.
//!
//! Snapshot version 1 supports the primary screen and an optional alternate
//! screen. `screen_count` is therefore one or two. SCREEN records identify
//! their destination by key and may appear in either order. Canonical encoders
//! write primary first, then alternate when present. `active_screen_key` must
//! name one of those declared screens.
//!
//! All integers are unsigned and little-endian.
//!
//! ## Binary Format
//!
//! The payload begins with a fixed header followed by terminal-wide variable
//! state. The enclosing record supplies the payload boundary.
//!
//! ```text
//!   0 +--------------------------+
//!     | Header                   |
//! 103 +--------------------------+
//!     | Tab stops                |
//!     | ceil(columns / 8) bytes  |
//!     +--------------------------+
//!     | Original palette         |
//!     | 256 * RGB                |
//!     +--------------------------+
//!     | Palette override mask    |
//!     | 32 bytes                 |
//!     +--------------------------+
//!     | Palette overrides        |
//!     | 3 * popcount(mask) bytes |
//!     +--------------------------+
//!     | PWD length (u32)         |
//!     +--------------------------+
//!     | PWD bytes                |
//!     +--------------------------+
//!     | Title length (u32)       |
//!     +--------------------------+
//!     | Title bytes              |
//! end +--------------------------+
//! ```
//!
//! ### Header
//!
//! ```text
//!   0 +-----------------------------------+
//!     | Columns (u16)                     |
//!   2 +-----------------------------------+
//!     | Rows (u16)                        |
//!   4 +-----------------------------------+
//!     | Pixel width (u32)                 |
//!   8 +-----------------------------------+
//!     | Pixel height (u32)                |
//!  12 +-----------------------------------+
//!     | Scrolling-region top (u16)        |
//!  14 +-----------------------------------+
//!     | Scrolling-region bottom (u16)     |
//!  16 +-----------------------------------+
//!     | Scrolling-region left (u16)       |
//!  18 +-----------------------------------+
//!     | Scrolling-region right (u16)      |
//!  20 +-----------------------------------+
//!     | Status display (u8)               |
//!  21 +-----------------------------------+
//!     | Active screen key (u16)           |
//!  23 +-----------------------------------+
//!     | Screen count (u16)                |
//!  25 +-----------------------------------+
//!     | Previous codepoint (u32)          |
//!  29 +-----------------------------------+
//!     | Cursor is-default (u8)            |
//!  30 +-----------------------------------+
//!     | Cursor default visual style (u8)  |
//!  31 +-----------------------------------+
//!     | Cursor default blink policy (u8)  |
//!  32 +-----------------------------------+
//!     | Shell-redraw policy (u8)          |
//!  33 +-----------------------------------+
//!     | Modify-other-keys level 2 (u8)    |
//!  34 +-----------------------------------+
//!     | Mouse event (u8)                  |
//!  35 +-----------------------------------+
//!     | Mouse format (u8)                 |
//!  36 +-----------------------------------+
//!     | Mouse shift-capture policy (u8)   |
//!  37 +-----------------------------------+
//!     | Mouse shape (u8)                  |
//!  38 +-----------------------------------+
//!     | Password-input flag (u8)          |
//!  39 +-----------------------------------+
//!     | Current modes (ModePacked)        |
//!  47 +-----------------------------------+
//!     | Saved modes (ModePacked)          |
//!  55 +-----------------------------------+
//!     | Default modes (ModePacked)        |
//!  63 +-----------------------------------+
//!     | Background color (DynamicRGB)     |
//!  71 +-----------------------------------+
//!     | Foreground color (DynamicRGB)     |
//!  79 +-----------------------------------+
//!     | Cursor color (DynamicRGB)         |
//!  87 +-----------------------------------+
//!     | Maximum scrollback bytes (u64)    |
//!  95 +-----------------------------------+
//!     | Maximum scrollback rows (u64)     |
//! 103 +-----------------------------------+
//! ```
//!
//! The previous codepoint is a Unicode scalar value or `0xffffffff` when there
//! is no previous character. Boolean fields are zero or one.
//! Cursor blink and mouse shift-capture policies encode null as zero, false as
//! one, and true as two.
//!
//! A scrollback limit of `0xffffffffffffffff` means unlimited. Every other
//! value is finite, including zero. The values are the source primary
//! PageList's explicit policies, not its dimension-adjusted effective limits.
//! Alternate-screen no-scrollback behavior is derived from the screen key.
//!
//! ### Tab stops
//!
//! One bit is encoded for each column, least-significant bit first within each
//! byte. Bit zero of the first byte is column zero. Unused high bits in the last
//! byte are zero.
//!
//! ### Dynamic RGB
//!
//! The three terminal dynamic colors share this layout:
//!
//! ```text
//! 0 +----------------------------+
//!   | Default present (u8)       |
//! 1 +----------------------------+
//!   | Default RGB                |
//! 4 +----------------------------+
//!   | Override present (u8)      |
//! 5 +----------------------------+
//!   | Override RGB               |
//! 8 +----------------------------+
//! ```
//!
//! Presence values are zero or one. The corresponding RGB bytes must be zero
//! when a value is absent.
//!
//! ### Palette
//!
//! The complete original 256-color palette is encoded first in index order.
//! Each mask bit then states whether the current palette entry overrides that
//! original value. Bit zero of the first mask byte is palette index zero.
//! Override RGB values follow in increasing index order with no index or count
//! fields.
//!
//! ### Modes
//!
//! Current, saved, and default modes use the same stable bit registry:
//!
//! ```text
//! bit  0  disable_keyboard
//! bit  1  insert
//! bit  2  send_receive_mode
//! bit  3  linefeed
//! bit  4  cursor_keys
//! bit  5  132_column
//! bit  6  slow_scroll
//! bit  7  reverse_colors
//! bit  8  origin
//! bit  9  wraparound
//! bit 10  autorepeat
//! bit 11  mouse_event_x10
//! bit 12  cursor_blinking
//! bit 13  cursor_visible
//! bit 14  enable_mode_3
//! bit 15  reverse_wrap
//! bit 16  alt_screen_legacy
//! bit 17  keypad_keys
//! bit 18  backarrow_key_mode
//! bit 19  enable_left_and_right_margin
//! bit 20  mouse_event_normal
//! bit 21  mouse_event_button
//! bit 22  mouse_event_any
//! bit 23  focus_event
//! bit 24  mouse_format_utf8
//! bit 25  mouse_format_sgr
//! bit 26  mouse_alternate_scroll
//! bit 27  mouse_format_urxvt
//! bit 28  mouse_format_sgr_pixels
//! bit 29  ignore_keypad_with_numlock
//! bit 30  alt_esc_prefix
//! bit 31  alt_sends_escape
//! bit 32  reverse_wrap_extended
//! bit 33  alt_screen
//! bit 34  save_cursor
//! bit 35  alt_screen_save_cursor_clear_enter
//! bit 36  bracketed_paste
//! bit 37  synchronized_output
//! bit 38  grapheme_cluster
//! bit 39  report_color_scheme
//! bit 40  report_visibility
//! bit 41  in_band_size_reports
//! bits 42-63  reserved, zero
//! ```
//!
//! This is the packed field order of native `ModePacked`. Its layout is
//! well-defined and is the snapshot registry. Moving or adding a native mode
//! therefore requires a snapshot version bump.
//!
//! ## Field classification
//!
//! The TERMINAL payload encodes terminal dimensions, pixel dimensions,
//! scrolling region, status display, tab stops, PWD, title, color state,
//! previous character, all three mode sets, cursor defaults, mouse behavior,
//! password-input state, source scrollback policies, the active screen key, and
//! the set of declared screens.
//!
//! SCREEN and HISTORY sequences encode each Screen's pages, cursor, saved
//! cursor, charset, protected mode, Kitty keyboard stack, semantic-click state,
//! and complete history. The semantic-prompt `seen` bit is derived from
//! restored resident content.
//!
//! Native allocators, I/O implementations, pools, pointers, page IDs, byte
//! accounting, tracked pins, and ScreenSet generations are reconstructed.
//! PageList row totals and the active viewport are derived from decoded pages.
//! The destination surface supplies its own focus state. Selections, scrolled
//! viewports, selection-scroll activity, dirty flags, search flags, hyperlink
//! hover state, and incremental compression state are presentation or cache
//! state and reset during restore.
//!
//! Kitty image state, virtual placeholders, and glyph glossary registrations
//! are unsupported by this snapshot version and are ignored during capture.
//! Build-time terminal behavior, Unicode width policy, parser continuation, and
//! external callbacks are version-level or caller-local requirements.
//!
//! Native enum declaration indices and mode bit positions used by this format
//! are snapshot-version registries. Changing any of them requires a snapshot
//! version bump.

const std = @import("std");
const Allocator = std.mem.Allocator;
const test_fixture = @import("fixture.zig");
const io = @import("io.zig");
const record = @import("record.zig");
const terminal_ansi = @import("../ansi.zig");
const terminal_color = @import("../color.zig");
const terminal_modes = @import("../modes.zig");
const terminal_mouse = @import("../mouse.zig");
const terminal_osc = @import("../osc.zig");
const Terminal = @import("../Terminal.zig");
const TerminalScreen = @import("../Screen.zig");
const TerminalScreenKey = @import("../ScreenSet.zig").Key;
const TerminalTabstops = @import("../Tabstops.zig");
const ModeBits = @typeInfo(
    terminal_modes.ModePacked,
).@"struct".backing_integer.?;

/// Reuse the terminal's semantic RGB value without adopting its memory layout
/// as a wire encoding.
pub const RGB = terminal_color.RGB;

/// Reuse the terminal's semantic dynamic color without adopting its memory
/// layout as a wire encoding.
pub const DynamicRGB = terminal_color.DynamicRGB;

const ValidationError = error{
    InvalidDimensions,
    InvalidScrollingRegion,
    InvalidScreenCount,
    InvalidActiveScreenKey,
    InvalidPreviousCodepoint,
    InvalidScrollbackLimit,
};

const HeaderInitError = error{
    ScrollbackLimitOverflow,
};

/// Errors possible while encoding a TERMINAL payload.
const PayloadEncodeError = std.Io.Writer.Error ||
    ValidationError ||
    error{
        InvalidTabStops,
        InvalidPalette,
        StringTooLong,
    };

/// Errors possible while decoding a TERMINAL payload.
const PayloadDecodeError = std.Io.Reader.Error ||
    Allocator.Error ||
    ValidationError ||
    error{
        InvalidStatusDisplay,
        InvalidCursorIsDefault,
        InvalidCursorStyle,
        InvalidCursorBlink,
        InvalidShellRedraw,
        InvalidModifyOtherKeys,
        InvalidMouseEvent,
        InvalidMouseFormat,
        InvalidMouseShiftCapture,
        InvalidMouseShape,
        InvalidPasswordInput,
        InvalidModes,
        InvalidDynamicRGB,
        InvalidTabStops,
    };

/// The fixed fields at the start of every TERMINAL payload.
pub const Header = struct {
    /// Number of bytes written by `encode`, calculated using the encoder.
    pub const len = computeLen();

    comptime {
        std.debug.assert(len == 103);
    }

    // Terminal geometry and its current scrolling region.
    columns: u16,
    rows: u16,
    width_px: u32,
    height_px: u32,

    scrolling_region_top: u16,
    scrolling_region_bottom: u16,
    scrolling_region_left: u16,
    scrolling_region_right: u16,

    // Status display, screen routing, and character context.
    status_display: terminal_ansi.StatusDisplay,
    active_screen_key: TerminalScreenKey,
    screen_count: u16,
    previous_codepoint: ?u21,

    // Cursor presentation defaults shared by the screens.
    cursor_is_default: bool,
    cursor_default_style: TerminalScreen.CursorStyle,
    cursor_default_blink: ?bool,

    // Terminal input, semantic redraw, and pointer behavior.
    shell_redraw: terminal_osc.semantic_prompt.Redraw,
    modify_other_keys_2: bool,
    mouse_event: terminal_mouse.Event,
    mouse_format: terminal_mouse.Format,
    mouse_shift_capture: ?bool,
    mouse_shape: terminal_mouse.Shape,
    password_input: bool,

    // Runtime, saved, and reset mode sets.
    current_modes: terminal_modes.ModePacked,
    saved_modes: terminal_modes.ModePacked,
    default_modes: terminal_modes.ModePacked,

    // Terminal-wide dynamic color state.
    background: DynamicRGB,
    foreground: DynamicRGB,
    cursor_color: DynamicRGB,

    // Explicit primary-screen scrollback policies.
    max_scrollback_bytes: ?u64,
    max_scrollback_rows: ?u64,

    /// Capture the terminal-wide native state represented by this header.
    fn init(terminal: *const Terminal) HeaderInitError!Header {
        const primary = terminal.screens.get(.primary).?;

        return .{
            // Terminal geometry and its current scrolling region.
            .columns = terminal.cols,
            .rows = terminal.rows,
            .width_px = terminal.width_px,
            .height_px = terminal.height_px,
            .scrolling_region_top = terminal.scrolling_region.top,
            .scrolling_region_bottom = terminal.scrolling_region.bottom,
            .scrolling_region_left = terminal.scrolling_region.left,
            .scrolling_region_right = terminal.scrolling_region.right,

            // Status display, screen routing, and character context.
            .status_display = terminal.status_display,
            .active_screen_key = terminal.screens.active_key,
            .screen_count = if (terminal.screens.get(.alternate) == null)
                1
            else
                2,
            .previous_codepoint = terminal.previous_char,

            // Cursor presentation defaults shared by the screens.
            .cursor_is_default = terminal.cursor.is_default,
            .cursor_default_style = terminal.cursor.default_style,
            .cursor_default_blink = terminal.cursor.default_blink,

            // Terminal input, semantic redraw, and pointer behavior.
            .shell_redraw = terminal.flags.shell_redraws_prompt,
            .modify_other_keys_2 = terminal.flags.modify_other_keys_2,
            .mouse_event = terminal.flags.mouse_event,
            .mouse_format = terminal.flags.mouse_format,
            .mouse_shift_capture = switch (terminal.flags.mouse_shift_capture) {
                .null => null,
                .false => false,
                .true => true,
            },
            .mouse_shape = terminal.mouse_shape,
            .password_input = terminal.flags.password_input,

            // Runtime, saved, and reset mode sets.
            .current_modes = terminal.modes.values,
            .saved_modes = terminal.modes.saved,
            .default_modes = terminal.modes.default,

            // Terminal-wide dynamic color state.
            .background = terminal.colors.background,
            .foreground = terminal.colors.foreground,
            .cursor_color = terminal.colors.cursor,

            // Explicit primary-screen scrollback policies.
            .max_scrollback_bytes = try encodeScrollbackLimit(
                primary.pages.limits.bytes.explicit,
            ),
            .max_scrollback_rows = try encodeScrollbackLimit(
                primary.pages.limits.lines.explicit,
            ),
        };
    }

    /// Encode the fixed TERMINAL payload header field by field.
    pub fn encode(
        self: Header,
        writer: *std.Io.Writer,
    ) PayloadEncodeError!void {
        try self.validate();

        // Terminal geometry and its current scrolling region.
        try io.writeInt(writer, u16, self.columns);
        try io.writeInt(writer, u16, self.rows);
        try io.writeInt(writer, u32, self.width_px);
        try io.writeInt(writer, u32, self.height_px);
        try io.writeInt(writer, u16, self.scrolling_region_top);
        try io.writeInt(writer, u16, self.scrolling_region_bottom);
        try io.writeInt(writer, u16, self.scrolling_region_left);
        try io.writeInt(writer, u16, self.scrolling_region_right);

        // Status display, screen routing, and character context.
        try writer.writeByte(@intCast(@intFromEnum(self.status_display)));
        try io.writeInt(
            writer,
            u16,
            @intCast(@intFromEnum(self.active_screen_key)),
        );
        try io.writeInt(writer, u16, self.screen_count);
        try io.writeInt(
            writer,
            u32,
            if (self.previous_codepoint) |value|
                @intCast(value)
            else
                std.math.maxInt(u32),
        );

        // Cursor presentation defaults shared by the screens.
        try writer.writeByte(@intFromBool(self.cursor_is_default));
        try writer.writeByte(
            @intCast(@intFromEnum(self.cursor_default_style)),
        );
        try writer.writeByte(encodeOptionalBool(self.cursor_default_blink));

        // Terminal input, semantic redraw, and pointer behavior.
        try writer.writeByte(@intCast(@intFromEnum(self.shell_redraw)));
        try writer.writeByte(@intFromBool(self.modify_other_keys_2));
        try writer.writeByte(@intCast(@intFromEnum(self.mouse_event)));
        try writer.writeByte(@intCast(@intFromEnum(self.mouse_format)));
        try writer.writeByte(encodeOptionalBool(self.mouse_shift_capture));
        try writer.writeByte(@intCast(@intFromEnum(self.mouse_shape)));
        try writer.writeByte(@intFromBool(self.password_input));

        // Runtime, saved, and reset mode sets. ModePacked occupies 41 bits;
        // its eight-byte wire slots zero-extend the native packed value.
        const mode_values = [_]terminal_modes.ModePacked{
            self.current_modes,
            self.saved_modes,
            self.default_modes,
        };
        for (mode_values) |value| {
            const bits: ModeBits = @bitCast(value);
            try io.writeInt(writer, u64, @intCast(bits));
        }

        // Terminal-wide dynamic color state.
        try encodeDynamicRGB(self.background, writer);
        try encodeDynamicRGB(self.foreground, writer);
        try encodeDynamicRGB(self.cursor_color, writer);

        // Explicit primary-screen scrollback policies.
        try io.writeInt(
            writer,
            u64,
            self.max_scrollback_bytes orelse std.math.maxInt(u64),
        );
        try io.writeInt(
            writer,
            u64,
            self.max_scrollback_rows orelse std.math.maxInt(u64),
        );
    }

    /// Decode and validate the fixed TERMINAL payload header.
    pub fn decode(reader: *std.Io.Reader) PayloadDecodeError!Header {
        // Terminal geometry and its current scrolling region.
        const columns = try io.readInt(reader, u16);
        const rows = try io.readInt(reader, u16);
        const width_px = try io.readInt(reader, u32);
        const height_px = try io.readInt(reader, u32);
        const scrolling_region_top = try io.readInt(reader, u16);
        const scrolling_region_bottom = try io.readInt(reader, u16);
        const scrolling_region_left = try io.readInt(reader, u16);
        const scrolling_region_right = try io.readInt(reader, u16);

        // Status display, screen routing, and character context.
        const status_display = enumFromInt(
            terminal_ansi.StatusDisplay,
            try reader.takeByte(),
        ) orelse return error.InvalidStatusDisplay;
        const active_screen_key = enumFromInt(
            TerminalScreenKey,
            try io.readInt(reader, u16),
        ) orelse return error.InvalidActiveScreenKey;
        const screen_count = try io.readInt(reader, u16);
        const previous_raw = try io.readInt(reader, u32);
        const previous_codepoint: ?u21 =
            if (previous_raw == std.math.maxInt(u32))
                null
            else
                std.math.cast(u21, previous_raw) orelse
                    return error.InvalidPreviousCodepoint;

        // Cursor presentation defaults shared by the screens.
        const cursor_is_default = switch (try reader.takeByte()) {
            0 => false,
            1 => true,
            else => return error.InvalidCursorIsDefault,
        };
        const cursor_default_style = enumFromInt(
            TerminalScreen.CursorStyle,
            try reader.takeByte(),
        ) orelse return error.InvalidCursorStyle;
        const cursor_default_blink: ?bool = switch (try reader.takeByte()) {
            0 => null,
            1 => false,
            2 => true,
            else => return error.InvalidCursorBlink,
        };

        // Terminal input, semantic redraw, and pointer behavior.
        const shell_redraw = enumFromInt(
            terminal_osc.semantic_prompt.Redraw,
            try reader.takeByte(),
        ) orelse return error.InvalidShellRedraw;
        const modify_other_keys_2 = switch (try reader.takeByte()) {
            0 => false,
            1 => true,
            else => return error.InvalidModifyOtherKeys,
        };
        const mouse_event = enumFromInt(
            terminal_mouse.Event,
            try reader.takeByte(),
        ) orelse return error.InvalidMouseEvent;
        const mouse_format = enumFromInt(
            terminal_mouse.Format,
            try reader.takeByte(),
        ) orelse return error.InvalidMouseFormat;
        const mouse_shift_capture: ?bool = switch (try reader.takeByte()) {
            0 => null,
            1 => false,
            2 => true,
            else => return error.InvalidMouseShiftCapture,
        };
        const mouse_shape = enumFromInt(
            terminal_mouse.Shape,
            try reader.takeByte(),
        ) orelse return error.InvalidMouseShape;
        const password_input = switch (try reader.takeByte()) {
            0 => false,
            1 => true,
            else => return error.InvalidPasswordInput,
        };

        // Runtime, saved, and reset mode sets.
        var mode_values: [3]terminal_modes.ModePacked = undefined;
        for (&mode_values) |*value| {
            const raw = try io.readInt(reader, u64);
            const bits = std.math.cast(ModeBits, raw) orelse
                return error.InvalidModes;
            value.* = @bitCast(bits);
        }

        // Terminal-wide dynamic color state.
        const background = try decodeDynamicRGB(reader);
        const foreground = try decodeDynamicRGB(reader);
        const cursor_color = try decodeDynamicRGB(reader);

        // Explicit primary-screen scrollback policies.
        const max_scrollback_bytes = decodeOptionalLimit(
            try io.readInt(reader, u64),
        );
        const max_scrollback_rows = decodeOptionalLimit(
            try io.readInt(reader, u64),
        );

        const result: Header = .{
            .columns = columns,
            .rows = rows,
            .width_px = width_px,
            .height_px = height_px,

            .scrolling_region_top = scrolling_region_top,
            .scrolling_region_bottom = scrolling_region_bottom,
            .scrolling_region_left = scrolling_region_left,
            .scrolling_region_right = scrolling_region_right,

            .status_display = status_display,
            .active_screen_key = active_screen_key,
            .screen_count = screen_count,
            .previous_codepoint = previous_codepoint,

            .cursor_is_default = cursor_is_default,
            .cursor_default_style = cursor_default_style,
            .cursor_default_blink = cursor_default_blink,

            .shell_redraw = shell_redraw,
            .modify_other_keys_2 = modify_other_keys_2,
            .mouse_event = mouse_event,
            .mouse_format = mouse_format,
            .mouse_shift_capture = mouse_shift_capture,
            .mouse_shape = mouse_shape,
            .password_input = password_input,

            .current_modes = mode_values[0],
            .saved_modes = mode_values[1],
            .default_modes = mode_values[2],

            .background = background,
            .foreground = foreground,
            .cursor_color = cursor_color,

            .max_scrollback_bytes = max_scrollback_bytes,
            .max_scrollback_rows = max_scrollback_rows,
        };
        try result.validate();
        return result;
    }

    fn validate(self: Header) ValidationError!void {
        if (self.columns == 0 or self.rows == 0) {
            return error.InvalidDimensions;
        }
        if (self.scrolling_region_top > self.scrolling_region_bottom or
            self.scrolling_region_bottom >= self.rows or
            self.scrolling_region_left > self.scrolling_region_right or
            self.scrolling_region_right >= self.columns)
        {
            return error.InvalidScrollingRegion;
        }

        if (self.screen_count != 1 and self.screen_count != 2) {
            return error.InvalidScreenCount;
        }
        if (self.active_screen_key == .alternate and self.screen_count != 2) {
            return error.InvalidActiveScreenKey;
        }

        if (self.previous_codepoint) |value| {
            if (value > 0x10FFFF or
                (value >= 0xD800 and value <= 0xDFFF))
            {
                return error.InvalidPreviousCodepoint;
            }
        }

        if (self.max_scrollback_bytes == std.math.maxInt(u64) or
            self.max_scrollback_rows == std.math.maxInt(u64))
        {
            return error.InvalidScrollbackLimit;
        }
    }

    fn computeLen() usize {
        comptime {
            var buf: [128]u8 = undefined;
            var writer: std.Io.Writer = .fixed(&buf);
            const value: Header = .{
                .columns = 1,
                .rows = 1,
                .width_px = 0,
                .height_px = 0,
                .scrolling_region_top = 0,
                .scrolling_region_bottom = 0,
                .scrolling_region_left = 0,
                .scrolling_region_right = 0,
                .status_display = .main,
                .active_screen_key = .primary,
                .screen_count = 1,
                .previous_codepoint = null,
                .cursor_is_default = true,
                .cursor_default_style = .block,
                .cursor_default_blink = null,
                .shell_redraw = .true,
                .modify_other_keys_2 = false,
                .mouse_event = .none,
                .mouse_format = .x10,
                .mouse_shift_capture = null,
                .mouse_shape = .text,
                .password_input = false,
                .current_modes = .{},
                .saved_modes = .{},
                .default_modes = .{},
                .background = .unset,
                .foreground = .unset,
                .cursor_color = .unset,
                .max_scrollback_bytes = null,
                .max_scrollback_rows = null,
            };
            value.encode(&writer) catch unreachable;
            return writer.end;
        }
    }
};

/// Allocator-owned semantic state decoded from one TERMINAL payload.
///
/// The palette and fixed header are values. `tabstops`, `pwd`, and `title`
/// own allocations and are released by `deinit`.
const DecodedPayload = struct {
    header: Header,
    tabstops: TerminalTabstops,
    palette: terminal_color.DynamicPalette,
    pwd: []u8,
    title: []u8,

    fn deinit(self: *DecodedPayload, alloc: Allocator) void {
        self.tabstops.deinit(alloc);
        alloc.free(self.pwd);
        alloc.free(self.title);
        self.* = undefined;
    }
};

/// Encode one complete TERMINAL payload without record framing.
fn encodePayload(
    header: Header,
    tabstops: *const TerminalTabstops,
    palette: *const terminal_color.DynamicPalette,
    pwd: []const u8,
    title: []const u8,
    writer: *std.Io.Writer,
) PayloadEncodeError!void {
    // Validate the complete semantic value before writing any bytes.
    try header.validate();
    if (tabstops.cols != @as(usize, header.columns)) {
        return error.InvalidTabStops;
    }
    if (pwd.len > std.math.maxInt(u32) or
        title.len > std.math.maxInt(u32))
    {
        return error.StringTooLong;
    }
    for (palette.original, palette.current, 0..) |original, current, index| {
        if (!palette.mask.isSet(index) and !original.eql(current)) {
            return error.InvalidPalette;
        }
    }

    try header.encode(writer);

    // Tab stops are packed least-significant bit first.
    const tabstop_len = (@as(usize, header.columns) + 7) / 8;
    for (0..tabstop_len) |byte_index| {
        var raw: u8 = 0;
        for (0..8) |bit| {
            const column = byte_index * 8 + bit;
            if (column >= header.columns) break;
            if (tabstops.get(column)) {
                raw |= @as(u8, 1) << @intCast(bit);
            }
        }
        try writer.writeByte(raw);
    }

    // Encode the original palette, then a compact mask and only the active
    // overrides in increasing palette-index order.
    for (palette.original) |value| try encodeRGB(value, writer);
    for (0..32) |byte_index| {
        var raw: u8 = 0;
        for (0..8) |bit| {
            if (palette.mask.isSet(byte_index * 8 + bit)) {
                raw |= @as(u8, 1) << @intCast(bit);
            }
        }
        try writer.writeByte(raw);
    }
    for (palette.current, 0..) |value, index| {
        if (palette.mask.isSet(index)) try encodeRGB(value, writer);
    }

    // Length-prefixed terminal strings end the payload.
    try io.writeInt(writer, u32, @intCast(pwd.len));
    try writer.writeAll(pwd);
    try io.writeInt(writer, u32, @intCast(title.len));
    try writer.writeAll(title);
}

/// Decode one complete allocator-owned TERMINAL payload.
///
/// The enclosing record reader remains responsible for verifying exact payload
/// exhaustion. On success, the caller owns the result and must call `deinit`.
fn decodePayload(
    reader: *std.Io.Reader,
    alloc: Allocator,
) PayloadDecodeError!DecodedPayload {
    const header = try Header.decode(reader);

    // Restore the native tab-stop representation from its packed wire bits.
    var tabstops = try TerminalTabstops.init(alloc, header.columns, 0);
    errdefer tabstops.deinit(alloc);
    const tabstop_len = (@as(usize, header.columns) + 7) / 8;
    for (0..tabstop_len) |byte_index| {
        const raw = try reader.takeByte();
        for (0..8) |bit| {
            const mask = @as(u8, 1) << @intCast(bit);
            const column = byte_index * 8 + bit;
            if (column >= header.columns) {
                if (raw & mask != 0) return error.InvalidTabStops;
            } else if (raw & mask != 0) {
                tabstops.set(column);
            }
        }
    }

    // Reconstruct the dynamic palette from its original values and sparse
    // current-value overrides.
    var original: terminal_color.Palette = undefined;
    for (&original) |*value| value.* = try decodeRGB(reader);
    var override_mask: [32]u8 = undefined;
    try reader.readSliceAll(&override_mask);

    var palette: terminal_color.DynamicPalette = .init(original);
    for (0..256) |index| {
        const mask = @as(u8, 1) << @intCast(index % 8);
        if (override_mask[index / 8] & mask != 0) {
            palette.set(@intCast(index), try decodeRGB(reader));
        }
    }

    // Read the two allocator-owned terminal strings last so all earlier
    // fixed-size validation happens before allocating them.
    const pwd_len: usize = @intCast(try io.readInt(reader, u32));
    const pwd = try alloc.alloc(u8, pwd_len);
    errdefer alloc.free(pwd);
    try reader.readSliceAll(pwd);

    const title_len: usize = @intCast(try io.readInt(reader, u32));
    const title = try alloc.alloc(u8, title_len);
    errdefer alloc.free(title);
    try reader.readSliceAll(title);

    return .{
        .header = header,
        .tabstops = tabstops,
        .palette = palette,
        .pwd = pwd,
        .title = title,
    };
}

/// Errors possible while encoding one native TERMINAL record.
pub const EncodeError = HeaderInitError ||
    PayloadEncodeError ||
    record.Writer.FinishError;

/// Encode terminal-wide native state as one framed TERMINAL record.
///
/// State not represented by this snapshot version is ignored. Any failure
/// removes the incomplete record while preserving bytes that were already
/// present in `destination`.
pub fn encode(
    terminal: *const Terminal,
    destination: *std.Io.Writer.Allocating,
) EncodeError!void {
    const header = try Header.init(terminal);

    var record_writer = try record.Writer.init(destination, .terminal);
    errdefer record_writer.cancel();
    try encodePayload(
        header,
        &terminal.tabstops,
        &terminal.colors.palette,
        terminal.getPwd() orelse "",
        terminal.getTitle() orelse "",
        record_writer.payloadWriter(),
    );
    try record_writer.finish();
}

/// Errors possible while decoding one native TERMINAL record.
pub const DecodeError = PayloadDecodeError ||
    record.Reader.InitError ||
    record.Reader.FinishError ||
    error{
        /// The next record is valid but is not a TERMINAL.
        UnexpectedRecordTag,

        /// A wire scrollback policy does not fit the native platform.
        ScrollbackLimitOverflow,
    };

/// Decode one framed TERMINAL record directly into native terminal state.
///
/// The returned terminal owns every decoded allocation and contains empty
/// primary and optional alternate screens with the declared routing. Later
/// SCREEN records replace those screens in place. On failure, all decoded and
/// partially initialized native state is released.
pub fn decode(
    source: *std.Io.Reader,
    io_: std.Io,
    alloc: Allocator,
) DecodeError!Terminal {
    // Finish the complete record before constructing native terminal state.
    var payload: DecodedPayload = payload: {
        var record_reader: record.Reader = undefined;
        try record_reader.init(source);
        if (record_reader.header.tag != .terminal) {
            return error.UnexpectedRecordTag;
        }

        var payload = try decodePayload(record_reader.payloadReader(), alloc);
        errdefer payload.deinit(alloc);
        try record_reader.finish();
        break :payload payload;
    };
    defer payload.deinit(alloc);

    const header = payload.header;
    const max_scrollback_bytes = try nativeScrollbackLimit(
        header.max_scrollback_bytes,
    );
    const max_scrollback_lines = try nativeScrollbackLimit(
        header.max_scrollback_rows,
    );

    // Terminal.init establishes native pools, pins, defaults, and ownership.
    var result = try Terminal.init(io_, alloc, .{
        .cols = header.columns,
        .rows = header.rows,
        .max_scrollback_bytes = max_scrollback_bytes,
        .max_scrollback_lines = max_scrollback_lines,
        .colors = .{
            .background = header.background,
            .foreground = header.foreground,
            .cursor = header.cursor_color,
            .palette = payload.palette,
        },
        .default_modes = header.default_modes,
        .default_cursor_style = header.cursor_default_style,
        .default_cursor_blink = header.cursor_default_blink,
    });
    errdefer result.deinit(alloc);

    // Recreate the optional screen now so ScreenSet routing is complete before
    // its empty screens are replaced by the following SCREEN records.
    if (header.screen_count == 2) {
        _ = try result.screens.getInit(io_, alloc, .alternate, .{
            .cols = header.columns,
            .rows = header.rows,
            .max_scrollback_bytes = 0,
        });
    }
    result.screens.switchTo(header.active_screen_key);

    // Restore terminal-wide runtime state that is not an initialization
    // policy. Presentation-only flags retain Terminal.init defaults.
    result.width_px = header.width_px;
    result.height_px = header.height_px;
    result.scrolling_region = .{
        .top = header.scrolling_region_top,
        .bottom = header.scrolling_region_bottom,
        .left = header.scrolling_region_left,
        .right = header.scrolling_region_right,
    };
    result.status_display = header.status_display;
    result.previous_char = header.previous_codepoint;
    result.cursor = .{
        .is_default = header.cursor_is_default,
        .default_style = header.cursor_default_style,
        .default_blink = header.cursor_default_blink,
    };
    result.modes = .{
        .values = header.current_modes,
        .saved = header.saved_modes,
        .default = header.default_modes,
    };
    result.flags.shell_redraws_prompt = header.shell_redraw;
    result.flags.modify_other_keys_2 = header.modify_other_keys_2;
    result.flags.mouse_event = header.mouse_event;
    result.flags.mouse_format = header.mouse_format;
    result.flags.mouse_shift_capture = if (header.mouse_shift_capture) |value|
        if (value) .true else .false
    else
        .null;
    result.flags.password_input = header.password_input;
    result.mouse_shape = header.mouse_shape;

    // Native strings retain trailing NUL sentinels. Setters construct those
    // without exposing that detail in the wire format.
    try result.setPwd(payload.pwd);
    try result.setTitle(payload.title);

    // Transfer decoded tab-stop ownership last. The deferred payload cleanup
    // releases the table originally allocated by Terminal.init.
    const initialized_tabstops = result.tabstops;
    result.tabstops = payload.tabstops;
    payload.tabstops = initialized_tabstops;

    result.screens.active.pages.assertIntegrity();
    return result;
}

fn enumFromInt(comptime T: type, raw: anytype) ?T {
    const Tag = @typeInfo(T).@"enum".tag_type;
    const value = std.math.cast(Tag, raw) orelse return null;
    return std.enums.fromInt(T, value);
}

fn encodeOptionalBool(value: ?bool) u8 {
    return if (value) |present|
        if (present) 2 else 1
    else
        0;
}

fn encodeRGB(
    value: RGB,
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    try writer.writeByte(value.r);
    try writer.writeByte(value.g);
    try writer.writeByte(value.b);
}

fn decodeRGB(reader: *std.Io.Reader) std.Io.Reader.Error!RGB {
    return .{
        .r = try reader.takeByte(),
        .g = try reader.takeByte(),
        .b = try reader.takeByte(),
    };
}

fn encodeDynamicRGB(
    value: DynamicRGB,
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    if (value.default) |rgb| {
        try writer.writeByte(1);
        try encodeRGB(rgb, writer);
    } else {
        try writer.writeByte(0);
        try writer.splatByteAll(0, 3);
    }

    if (value.override) |rgb| {
        try writer.writeByte(1);
        try encodeRGB(rgb, writer);
    } else {
        try writer.writeByte(0);
        try writer.splatByteAll(0, 3);
    }
}

fn decodeDynamicRGB(
    reader: *std.Io.Reader,
) (std.Io.Reader.Error || error{InvalidDynamicRGB})!DynamicRGB {
    const default_present = try reader.takeByte();
    const default_rgb = try decodeRGB(reader);
    const default: ?RGB = switch (default_present) {
        0 => if (default_rgb.eql(.{}))
            null
        else
            return error.InvalidDynamicRGB,
        1 => default_rgb,
        else => return error.InvalidDynamicRGB,
    };

    const override_present = try reader.takeByte();
    const override_rgb = try decodeRGB(reader);
    const override: ?RGB = switch (override_present) {
        0 => if (override_rgb.eql(.{}))
            null
        else
            return error.InvalidDynamicRGB,
        1 => override_rgb,
        else => return error.InvalidDynamicRGB,
    };

    return .{ .default = default, .override = override };
}

fn decodeOptionalLimit(raw: u64) ?u64 {
    return if (raw == std.math.maxInt(u64)) null else raw;
}

fn encodeScrollbackLimit(value: usize) HeaderInitError!?u64 {
    if (value == std.math.maxInt(usize)) return null;
    const result = std.math.cast(u64, value) orelse
        return error.ScrollbackLimitOverflow;
    if (result == std.math.maxInt(u64)) {
        return error.ScrollbackLimitOverflow;
    }
    return result;
}

fn nativeScrollbackLimit(
    value: ?u64,
) error{ScrollbackLimitOverflow}!?usize {
    const present = value orelse return null;
    return std.math.cast(usize, present) orelse
        error.ScrollbackLimitOverflow;
}

const test_header: Header = header: {
    var current_modes = std.mem.zeroes(terminal_modes.ModePacked);
    current_modes.disable_keyboard = true;
    var saved_modes = std.mem.zeroes(terminal_modes.ModePacked);
    saved_modes.in_band_size_reports = true;
    var default_modes = current_modes;
    default_modes.in_band_size_reports = true;

    break :header .{
        .columns = 0x0102,
        .rows = 0x0304,
        .width_px = 0x05060708,
        .height_px = 0x090a0b0c,

        .scrolling_region_top = 1,
        .scrolling_region_bottom = 2,
        .scrolling_region_left = 3,
        .scrolling_region_right = 4,

        .status_display = .status_line,
        .active_screen_key = .alternate,
        .screen_count = 2,
        .previous_codepoint = 'A',

        .cursor_is_default = true,
        .cursor_default_style = .block_hollow,
        .cursor_default_blink = true,

        .shell_redraw = .last,
        .modify_other_keys_2 = true,
        .mouse_event = .any,
        .mouse_format = .sgr_pixels,
        .mouse_shift_capture = false,
        .mouse_shape = .zoom_out,
        .password_input = true,

        .current_modes = current_modes,
        .saved_modes = saved_modes,
        .default_modes = default_modes,

        .background = .{
            .default = .{ .r = 1, .g = 2, .b = 3 },
            .override = null,
        },
        .foreground = .{
            .default = null,
            .override = .{ .r = 4, .g = 5, .b = 6 },
        },
        .cursor_color = .{
            .default = .{ .r = 7, .g = 8, .b = 9 },
            .override = .{ .r = 10, .g = 11, .b = 12 },
        },

        .max_scrollback_bytes = null,
        .max_scrollback_rows = 0x0102030405060708,
    };
};

const test_header_fixture = test_fixture.parse(
    @embedFile("testdata/terminal-header-v1.hex"),
);

test "TERMINAL mode bit layout" {
    try std.testing.expectEqual(
        @as(usize, 42),
        @bitSizeOf(terminal_modes.ModePacked),
    );

    var first: terminal_modes.ModePacked = std.mem.zeroes(
        terminal_modes.ModePacked,
    );
    first.disable_keyboard = true;
    try std.testing.expectEqual(
        @as(u42, 1) << 0,
        @as(u42, @bitCast(first)),
    );

    var visibility: terminal_modes.ModePacked = std.mem.zeroes(
        terminal_modes.ModePacked,
    );
    visibility.report_visibility = true;
    try std.testing.expectEqual(
        @as(u42, 1) << 40,
        @as(u42, @bitCast(visibility)),
    );

    var last: terminal_modes.ModePacked = std.mem.zeroes(
        terminal_modes.ModePacked,
    );
    last.in_band_size_reports = true;
    try std.testing.expectEqual(
        @as(u42, 1) << 41,
        @as(u42, @bitCast(last)),
    );
}

test "TERMINAL header golden encoding and decoding" {
    const testing = std.testing;

    var encoded: [Header.len]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&encoded);
    try test_header.encode(&writer);
    try test_fixture.expectEqual(
        .bytes,
        "src/terminal/snapshot/testdata/terminal-header-v1.hex",
        "snapshot_fixture-terminal-header-v1.hex",
        &test_header_fixture,
        writer.buffered(),
    );
    try testing.expectEqual(Header.len, test_header_fixture.len);

    // Exercise the streaming path with less buffered data than every integer.
    var source: std.Io.Reader = .fixed(&test_header_fixture);
    var buffer: [1]u8 = undefined;
    var limited = source.limited(.unlimited, &buffer);
    try testing.expectEqualDeep(
        test_header,
        try Header.decode(&limited.interface),
    );

    for (0..Header.len) |fixture_len| {
        var truncated: std.Io.Reader = .fixed(
            test_header_fixture[0..fixture_len],
        );
        try testing.expectError(
            error.EndOfStream,
            Header.decode(&truncated),
        );
    }
}

test "TERMINAL header rejects invalid values" {
    const testing = std.testing;

    // Semantic values are validated before encoding writes anything.
    var invalid_header = test_header;
    invalid_header.columns = 0;
    var encoded: [Header.len]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&encoded);
    try testing.expectError(
        error.InvalidDimensions,
        invalid_header.encode(&writer),
    );
    try testing.expectEqual(@as(usize, 0), writer.end);

    invalid_header = test_header;
    invalid_header.max_scrollback_bytes = std.math.maxInt(u64);
    writer = .fixed(&encoded);
    try testing.expectError(
        error.InvalidScrollbackLimit,
        invalid_header.encode(&writer),
    );
    try testing.expectEqual(@as(usize, 0), writer.end);

    // Single-byte registries and boolean encodings reject every value just
    // beyond their current snapshot range.
    const ByteCase = struct {
        offset: usize,
        value: u8,
        expected: anyerror,
    };
    const byte_cases = [_]ByteCase{
        .{ .offset = 20, .value = 2, .expected = error.InvalidStatusDisplay },
        .{ .offset = 21, .value = 2, .expected = error.InvalidActiveScreenKey },
        .{ .offset = 29, .value = 2, .expected = error.InvalidCursorIsDefault },
        .{ .offset = 30, .value = 4, .expected = error.InvalidCursorStyle },
        .{ .offset = 31, .value = 3, .expected = error.InvalidCursorBlink },
        .{ .offset = 32, .value = 3, .expected = error.InvalidShellRedraw },
        .{ .offset = 33, .value = 2, .expected = error.InvalidModifyOtherKeys },
        .{ .offset = 34, .value = 5, .expected = error.InvalidMouseEvent },
        .{ .offset = 35, .value = 5, .expected = error.InvalidMouseFormat },
        .{ .offset = 36, .value = 3, .expected = error.InvalidMouseShiftCapture },
        .{ .offset = 37, .value = 34, .expected = error.InvalidMouseShape },
        .{ .offset = 38, .value = 2, .expected = error.InvalidPasswordInput },
        .{ .offset = 44, .value = 4, .expected = error.InvalidModes },
        .{ .offset = 63, .value = 2, .expected = error.InvalidDynamicRGB },
        .{ .offset = 68, .value = 1, .expected = error.InvalidDynamicRGB },
    };
    for (byte_cases) |case| {
        var fixture = test_header_fixture;
        fixture[case.offset] = case.value;
        var reader: std.Io.Reader = .fixed(&fixture);
        try testing.expectError(case.expected, Header.decode(&reader));
    }

    // Cross-field and multi-byte invariants are validated after decoding.
    var invalid_screen_count = test_header_fixture;
    invalid_screen_count[23] = 3;
    var screen_count_reader: std.Io.Reader = .fixed(&invalid_screen_count);
    try testing.expectError(
        error.InvalidScreenCount,
        Header.decode(&screen_count_reader),
    );

    var missing_active_screen = test_header_fixture;
    missing_active_screen[23] = 1;
    var active_screen_reader: std.Io.Reader = .fixed(&missing_active_screen);
    try testing.expectError(
        error.InvalidActiveScreenKey,
        Header.decode(&active_screen_reader),
    );

    var invalid_scrolling_region = test_header_fixture;
    invalid_scrolling_region[14] = 0x04;
    invalid_scrolling_region[15] = 0x03;
    var scrolling_region_reader: std.Io.Reader = .fixed(
        &invalid_scrolling_region,
    );
    try testing.expectError(
        error.InvalidScrollingRegion,
        Header.decode(&scrolling_region_reader),
    );

    var invalid_codepoint = test_header_fixture;
    invalid_codepoint[25] = 0x00;
    invalid_codepoint[26] = 0xd8;
    invalid_codepoint[27] = 0x00;
    invalid_codepoint[28] = 0x00;
    var codepoint_reader: std.Io.Reader = .fixed(&invalid_codepoint);
    try testing.expectError(
        error.InvalidPreviousCodepoint,
        Header.decode(&codepoint_reader),
    );
}

test "TERMINAL payload round trip" {
    const testing = std.testing;

    // Include a partial final tab-stop byte so its bit order and padding are
    // both exercised.
    var tabstops = try TerminalTabstops.init(
        testing.allocator,
        test_header.columns,
        0,
    );
    defer tabstops.deinit(testing.allocator);
    tabstops.set(0);
    tabstops.set(8);
    tabstops.set(test_header.columns - 1);

    // Use overrides at both ends of the palette to make ordering explicit.
    var palette: terminal_color.DynamicPalette = .init(
        terminal_color.default,
    );
    palette.set(0, .{ .r = 1, .g = 2, .b = 3 });
    palette.set(255, .{ .r = 4, .g = 5, .b = 6 });

    var destination: std.Io.Writer.Allocating = .init(testing.allocator);
    defer destination.deinit();
    try encodePayload(
        test_header,
        &tabstops,
        &palette,
        "file:///tmp/example",
        "snapshot title",
        &destination.writer,
    );

    // Tab stops and the sparse palette mask both use least-significant-bit
    // first ordering.
    const bytes = destination.written();
    const tabstop_len = (@as(usize, test_header.columns) + 7) / 8;
    try testing.expectEqual(@as(u8, 0x01), bytes[Header.len]);
    try testing.expectEqual(@as(u8, 0x01), bytes[Header.len + 1]);
    try testing.expectEqual(
        @as(u8, 0x02),
        bytes[Header.len + tabstop_len - 1],
    );
    const palette_mask_offset = Header.len + tabstop_len + 256 * 3;
    try testing.expectEqual(@as(u8, 0x01), bytes[palette_mask_offset]);
    try testing.expectEqual(
        @as(u8, 0x80),
        bytes[palette_mask_offset + 31],
    );

    // Decode through a one-byte reader buffer to cover streaming of the large
    // fixed palette and allocator-owned strings.
    var source: std.Io.Reader = .fixed(bytes);
    var buffer: [1]u8 = undefined;
    var limited = source.limited(.unlimited, &buffer);
    var decoded = try decodePayload(
        &limited.interface,
        testing.allocator,
    );
    defer decoded.deinit(testing.allocator);

    try testing.expectEqualDeep(test_header, decoded.header);
    for (0..test_header.columns) |column| {
        try testing.expectEqual(
            tabstops.get(column),
            decoded.tabstops.get(column),
        );
    }
    try testing.expectEqualDeep(palette, decoded.palette);
    try testing.expectEqualStrings("file:///tmp/example", decoded.pwd);
    try testing.expectEqualStrings("snapshot title", decoded.title);
}

test "TERMINAL payload rejects noncanonical state" {
    const testing = std.testing;

    // A tab-stop set for different dimensions cannot represent this header.
    var tabstops = try TerminalTabstops.init(
        testing.allocator,
        test_header.columns - 1,
        0,
    );
    defer tabstops.deinit(testing.allocator);
    var palette: terminal_color.DynamicPalette = .init(
        terminal_color.default,
    );
    var encoded: [2048]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&encoded);
    try testing.expectError(
        error.InvalidTabStops,
        encodePayload(
            test_header,
            &tabstops,
            &palette,
            "",
            "",
            &writer,
        ),
    );
    try testing.expectEqual(@as(usize, 0), writer.end);

    // Unmasked current colors must remain equal to their originals.
    tabstops.cols = test_header.columns;
    palette.current[7] = .{ .r = 1, .g = 2, .b = 3 };
    writer = .fixed(&encoded);
    try testing.expectError(
        error.InvalidPalette,
        encodePayload(
            test_header,
            &tabstops,
            &palette,
            "",
            "",
            &writer,
        ),
    );
    try testing.expectEqual(@as(usize, 0), writer.end);
}

test "TERMINAL payload rejects tab-stop padding" {
    const testing = std.testing;

    var tabstops = try TerminalTabstops.init(
        testing.allocator,
        test_header.columns,
        0,
    );
    defer tabstops.deinit(testing.allocator);
    var palette: terminal_color.DynamicPalette = .init(
        terminal_color.default,
    );
    palette.set(1, .{ .r = 1, .g = 2, .b = 3 });

    var destination: std.Io.Writer.Allocating = .init(testing.allocator);
    defer destination.deinit();
    try encodePayload(
        test_header,
        &tabstops,
        &palette,
        "pwd",
        "title",
        &destination.writer,
    );

    // Only two bits in the last byte correspond to terminal columns.
    const tabstop_len = (@as(usize, test_header.columns) + 7) / 8;
    const last_tabstop = Header.len + tabstop_len - 1;
    const invalid_padding = try testing.allocator.dupe(
        u8,
        destination.written(),
    );
    defer testing.allocator.free(invalid_padding);
    invalid_padding[last_tabstop] |= 1 << 7;
    var padding_reader: std.Io.Reader = .fixed(invalid_padding);
    try testing.expectError(
        error.InvalidTabStops,
        decodePayload(&padding_reader, testing.allocator),
    );
}

test "TERMINAL record encodes native terminal state" {
    const testing = std.testing;

    var terminal = try Terminal.init(testing.io, testing.allocator, .{
        .cols = 10,
        .rows = 3,
        .max_scrollback_bytes = 12_345,
        .max_scrollback_lines = 67,
    });
    defer terminal.deinit(testing.allocator);

    // Exercise every native header section plus sentinel-backed strings.
    terminal.width_px = 800;
    terminal.height_px = 600;
    terminal.scrolling_region = .{
        .top = 1,
        .bottom = 2,
        .left = 2,
        .right = 8,
    };
    terminal.status_display = .status_line;
    terminal.previous_char = 'X';
    terminal.cursor = .{
        .is_default = false,
        .default_style = .underline,
        .default_blink = true,
    };
    terminal.flags.shell_redraws_prompt = .last;
    terminal.flags.modify_other_keys_2 = true;
    terminal.flags.mouse_event = .button;
    terminal.flags.mouse_format = .sgr;
    terminal.flags.mouse_shift_capture = .true;
    terminal.flags.password_input = true;
    terminal.mouse_shape = .pointer;
    terminal.modes.values.disable_keyboard = true;
    terminal.modes.saved.in_band_size_reports = true;
    terminal.modes.default.bracketed_paste = true;
    terminal.colors.background = .{
        .default = .{ .r = 1, .g = 2, .b = 3 },
        .override = .{ .r = 4, .g = 5, .b = 6 },
    };
    terminal.colors.palette.set(7, .{ .r = 7, .g = 8, .b = 9 });
    terminal.tabstops.reset(0);
    terminal.tabstops.set(1);
    terminal.tabstops.set(9);
    try terminal.setPwd("file:///tmp/native");
    try terminal.setTitle("native title");

    // Encode and restore through the public record codec.
    var destination: std.Io.Writer.Allocating = .init(testing.allocator);
    defer destination.deinit();
    try encode(&terminal, &destination);

    var source: std.Io.Reader = .fixed(destination.written());
    var restored = try decode(
        &source,
        testing.io,
        testing.allocator,
    );
    defer restored.deinit(testing.allocator);

    try testing.expectEqual(@as(u16, 10), restored.cols);
    try testing.expectEqual(@as(u16, 3), restored.rows);
    try testing.expectEqual(@as(u32, 800), restored.width_px);
    try testing.expectEqual(@as(u32, 600), restored.height_px);
    try testing.expectEqual(terminal.scrolling_region, restored.scrolling_region);
    try testing.expectEqual(terminal.status_display, restored.status_display);
    try testing.expectEqual(.primary, restored.screens.active_key);
    try testing.expect(restored.screens.get(.alternate) == null);
    try testing.expectEqual(@as(?u21, 'X'), restored.previous_char);
    try testing.expectEqualDeep(terminal.cursor, restored.cursor);
    try testing.expectEqual(
        terminal.flags.shell_redraws_prompt,
        restored.flags.shell_redraws_prompt,
    );
    try testing.expectEqual(
        terminal.flags.modify_other_keys_2,
        restored.flags.modify_other_keys_2,
    );
    try testing.expectEqual(
        terminal.flags.mouse_event,
        restored.flags.mouse_event,
    );
    try testing.expectEqual(
        terminal.flags.mouse_format,
        restored.flags.mouse_format,
    );
    try testing.expectEqual(
        terminal.flags.mouse_shift_capture,
        restored.flags.mouse_shift_capture,
    );
    try testing.expectEqual(
        terminal.flags.password_input,
        restored.flags.password_input,
    );
    try testing.expectEqual(terminal.mouse_shape, restored.mouse_shape);
    try testing.expectEqualDeep(terminal.modes, restored.modes);
    try testing.expectEqualDeep(terminal.colors, restored.colors);
    try testing.expectEqual(
        @as(usize, 12_345),
        restored.screens.active.pages.limits.bytes.explicit,
    );
    try testing.expectEqual(
        @as(usize, 67),
        restored.screens.active.pages.limits.lines.explicit,
    );
    try testing.expect(restored.tabstops.get(1));
    try testing.expect(restored.tabstops.get(9));
    try testing.expectEqualStrings(
        "file:///tmp/native",
        restored.getPwd().?,
    );
    try testing.expectEqualStrings("native title", restored.getTitle().?);
}

test "TERMINAL record declares an initialized alternate screen" {
    const testing = std.testing;

    var terminal = try Terminal.init(testing.io, testing.allocator, .{
        .cols = 10,
        .rows = 3,
    });
    defer terminal.deinit(testing.allocator);
    _ = try terminal.switchScreen(.alternate);

    var destination: std.Io.Writer.Allocating = .init(testing.allocator);
    defer destination.deinit();
    try encode(&terminal, &destination);

    var source: std.Io.Reader = .fixed(destination.written());
    var restored = try decode(
        &source,
        testing.io,
        testing.allocator,
    );
    defer restored.deinit(testing.allocator);

    const primary = restored.screens.get(.primary).?;
    const alternate = restored.screens.get(.alternate).?;
    try testing.expectEqual(.alternate, restored.screens.active_key);
    try testing.expectEqual(alternate, restored.screens.active);
    try testing.expect(primary != alternate);
    try testing.expectEqual(@as(u16, 10), alternate.pages.cols);
    try testing.expectEqual(@as(u16, 3), alternate.pages.rows);
    try testing.expectEqual(
        @as(usize, 0),
        alternate.pages.limits.bytes.explicit,
    );
}

test "TERMINAL record encoding is transactional" {
    const testing = std.testing;

    var terminal = try Terminal.init(testing.io, testing.allocator, .{
        .cols = 10,
        .rows = 3,
    });
    defer terminal.deinit(testing.allocator);

    var destination: std.Io.Writer.Allocating = .init(testing.allocator);
    defer destination.deinit();
    try destination.writer.writeAll("prefix");

    // Payload validation occurs after framing is reserved, so this covers the
    // record writer's rollback path.
    terminal.colors.palette.current[7] = .{ .r = 1, .g = 2, .b = 3 };
    try testing.expectError(
        error.InvalidPalette,
        encode(&terminal, &destination),
    );
    try testing.expectEqualStrings("prefix", destination.written());
}

test "TERMINAL record decoding rejects malformed input transactionally" {
    const testing = std.testing;

    // A valid record of another type is not accepted as TERMINAL state.
    var wrong_tag: std.Io.Writer.Allocating = .init(testing.allocator);
    defer wrong_tag.deinit();
    {
        var record_writer = try record.Writer.init(&wrong_tag, .screen);
        try record_writer.finish();
    }
    var wrong_tag_source: std.Io.Reader = .fixed(wrong_tag.written());
    try testing.expectError(
        error.UnexpectedRecordTag,
        decode(&wrong_tag_source, testing.io, testing.allocator),
    );

    // Build one canonical record for exhaustive truncation and allocation
    // failure checks below.
    var terminal = try Terminal.init(testing.io, testing.allocator, .{
        .cols = 10,
        .rows = 3,
    });
    defer terminal.deinit(testing.allocator);
    try terminal.setPwd("pwd");
    try terminal.setTitle("title");

    var encoded: std.Io.Writer.Allocating = .init(testing.allocator);
    defer encoded.deinit();
    try encode(&terminal, &encoded);

    for (0..encoded.written().len) |fixture_len| {
        var source: std.Io.Reader = .fixed(
            encoded.written()[0..fixture_len],
        );
        var restored = decode(
            &source,
            testing.io,
            testing.allocator,
        ) catch continue;
        restored.deinit(testing.allocator);
        try testing.expect(false);
    }

    var failing = testing.FailingAllocator.init(
        testing.allocator,
        .{ .fail_index = 0 },
    );
    var failing_source: std.Io.Reader = .fixed(encoded.written());
    try testing.expectError(
        error.OutOfMemory,
        decode(&failing_source, testing.io, failing.allocator()),
    );
}
