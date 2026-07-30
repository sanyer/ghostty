//! SCREEN record payload encoding.
//!
//! One SCREEN record represents the live state for one terminal screen. The
//! record is followed immediately by the number of complete PAGE records
//! declared by `page_count`. They are the minimal suffix of native pages needed
//! to cover the active area and are ordered from oldest to newest. A decoder
//! uses the declared count, rather than another record tag, to find the end of
//! the screen's page sequence.
//!
//! The final screen-height rows are the active area. When its boundary falls
//! inside the first encoded page, that page also contains an incidental history
//! prefix. A client may expose or ignore those resident rows, but must not
//! require them or infer the complete history extent from them.
//!
//! Screen dimensions are terminal-wide state and are not repeated here. Page
//! capacities, native page IDs and pointers, authoritative history extent and
//! availability, scrollbar state, selection, viewport, dirty state, and derived
//! semantic-prompt state are also omitted.
//!
//! All integers are unsigned and little-endian.
//!
//! ## Binary Format
//!
//! A SCREEN record is followed immediately by its declared PAGE records:
//!
//! ```text
//!  +----------------------+
//!  | SCREEN record        |
//!  +----------------------+
//!  | PAGE record 0        |
//!  +----------------------+
//!  | ...                  |
//!  +----------------------+
//!  | PAGE record (n - 1)  |
//!  +----------------------+
//!
//!  n = page_count
//! ```
//!
//! The HISTORY record for this screen provides the authoritative history
//! manifest. It counts any incidental prefix above as the SCREEN overlap, then
//! sends the older complete pages after the terminal becomes ready. The prefix
//! is not sent again.
//!
//! The SCREEN payload begins with a fixed header. When the header says there is
//! no saved cursor, the payload is:
//!
//! ```text
//!   0 +----------------------+
//!     | Header               |
//!  45 +----------------------+
//!     | Cursor hyperlink     |
//!     | variable             |
//! end +----------------------+
//! ```
//!
//! When a saved cursor is present, it is inserted before the cursor hyperlink:
//!
//! ```text
//!   0 +----------------------+
//!     | Header               |
//!  45 +----------------------+
//!     | Saved cursor         |
//!  68 +----------------------+
//!     | Cursor hyperlink     |
//!     | variable             |
//! end +----------------------+
//! ```
//!
//! The cursor hyperlink begins with a one-byte kind. Zero means no hyperlink
//! and has no following bytes. Kinds one and two use the implicit and explicit
//! hyperlink encodings documented in `hyperlink.zig`.
//!
//! ### Header
//!
//! ```text
//!   0 +----------------------------------+
//!     | Screen key (u16)                 |
//!   2 +----------------------------------+
//!     | Page count (u16)                 |
//!   4 +----------------------------------+
//!     | Cursor x (u16)                   |
//!   6 +----------------------------------+
//!     | Cursor y (u16)                   |
//!   8 +----------------------------------+
//!     | Cursor visual style (u8)         |
//!   9 +----------------------------------+
//!     | Cursor flags (u8)                |
//!  10 +----------------------------------+
//!     | Concrete cursor pen (Style)      |
//!  26 +----------------------------------+
//!     | Hyperlink implicit counter (u32) |
//!  30 +----------------------------------+
//!     | Current charset (CharsetState)   |
//!  32 +----------------------------------+
//!     | Protected mode (u8)              |
//!  33 +----------------------------------+
//!     | Kitty keyboard stack index (u8)  |
//!  34 +----------------------------------+
//!     | Kitty keyboard stack flags       |
//!     | 8 * u8                           |
//!  42 +----------------------------------+
//!     | Semantic-click kind (u8)         |
//!  43 +----------------------------------+
//!     | Semantic-click value (u8)        |
//!  44 +----------------------------------+
//!     | Saved-cursor-present (u8)        |
//!  45 +----------------------------------+
//! ```
//!
//! The concrete cursor pen uses the fixed style encoding from `style.zig`.
//!
//! ### Cursor flags
//!
//! ```text
//! bit 0 +--------------------------------+
//!       | Pending wrap                   |
//! bit 1 +--------------------------------+
//!       | Protected                      |
//! bit 2 +--------------------------------+
//!       | Semantic content               |
//!       | 2 bits                         |
//! bit 4 +--------------------------------+
//!       | Semantic-content-clear-EOL     |
//! bit 5 +--------------------------------+
//!       | Reserved, zero                 |
//!       | 3 bits                         |
//! bit 8 +--------------------------------+
//! ```
//!
//! ### Charset state
//!
//! The current and saved cursor charset states share this packed layout:
//!
//! ```text
//!  bit 0 +-------------------------------+
//!        | G0 charset                    |
//!        | 2 bits                        |
//!  bit 2 +-------------------------------+
//!        | G1 charset                    |
//!        | 2 bits                        |
//!  bit 4 +-------------------------------+
//!        | G2 charset                    |
//!        | 2 bits                        |
//!  bit 6 +-------------------------------+
//!        | G3 charset                    |
//!        | 2 bits                        |
//!  bit 8 +-------------------------------+
//!        | GL slot                       |
//!        | 2 bits                        |
//! bit 10 +-------------------------------+
//!        | GR slot                       |
//!        | 2 bits                        |
//! bit 12 +-------------------------------+
//!        | Single shift                  |
//!        | 3 bits                        |
//! bit 15 +-------------------------------+
//!        | Reserved, zero                |
//! bit 16 +-------------------------------+
//! ```
//!
//! The Kitty keyboard stack contains its current index followed by all eight
//! flag entries, including disabled entries.
//!
//! ### Saved cursor
//!
//! ```text
//!   0 +-----------------------------+
//!     | Saved cursor x (u16)        |
//!   2 +-----------------------------+
//!     | Saved cursor y (u16)        |
//!   4 +-----------------------------+
//!     | Saved cursor pen (Style)    |
//!  20 +-----------------------------+
//!     | Saved cursor flags (u8)     |
//!  21 +-----------------------------+
//!     | Saved charset state         |
//!  23 +-----------------------------+
//! ```
//!
//! ### Saved cursor flags
//!
//! ```text
//! bit 0 +---------------------------+
//!       | Protected                 |
//! bit 1 +---------------------------+
//!       | Pending wrap              |
//! bit 2 +---------------------------+
//!       | Origin                    |
//! bit 3 +---------------------------+
//!       | Reserved, zero            |
//!       | 5 bits                    |
//! bit 8 +---------------------------+
//! ```
//!
//! Native enum values used below are stable terminal registries. Their wire
//! widths are fixed independently by this payload. Changing those values or
//! any packed bit assignment requires a snapshot version bump.

const std = @import("std");
const build_options = @import("terminal_options");
const Allocator = std.mem.Allocator;
const hyperlink = @import("hyperlink.zig");
const io = @import("io.zig");
const page = @import("page.zig");
const record = @import("record.zig");
const style = @import("style.zig");
const terminal_ansi = @import("../ansi.zig");
const terminal_charsets = @import("../charsets.zig");
const terminal_hyperlink = @import("../hyperlink.zig");
const terminal_kitty = @import("../kitty.zig");
const terminal_osc = @import("../osc.zig");
const terminal_page = @import("../page.zig");
const TerminalPageList = @import("../PageList.zig");
const TerminalScreen = @import("../Screen.zig");
const TerminalScreenKey = @import("../ScreenSet.zig").Key;
const terminal_style = @import("../style.zig");

const TerminalHyperlink = terminal_hyperlink.Hyperlink;
const TerminalStyle = terminal_style.Style;

/// Errors possible while encoding fixed SCREEN payload fields.
const PayloadEncodeError = std.Io.Writer.Error || error{
    InvalidCursorFlags,
    InvalidCharsetState,
    InvalidKittyKeyboardIndex,
    InvalidKittyKeyboardFlags,
    InvalidSavedCursorFlags,
};

/// Errors possible while encoding a SCREEN and its complete PAGE sequence.
pub const EncodeError = PayloadEncodeError || page.EncodeError || error{
    /// The active area spans more pages than the SCREEN header can declare.
    PageCountOverflow,
};

/// Encode one SCREEN and its minimal suffix of complete native pages.
///
/// The suffix begins with the page containing the active area's first row and
/// ends with the newest page. If encoding any record fails, the entire sequence
/// is removed while earlier destination bytes remain.
pub fn encode(
    screen: *const TerminalScreen,
    key: TerminalScreenKey,
    destination: *std.Io.Writer.Allocating,
) EncodeError!void {
    const sequence_start = destination.written().len;
    errdefer destination.shrinkRetainingCapacity(sequence_start);

    // The active top may fall inside this page, leaving an incidental history
    // prefix. Every earlier complete page is history and is omitted.
    const first = screen.pages.getTopLeft(.active).node;
    var page_count: usize = 0;
    var node: ?@TypeOf(first) = first;
    while (node) |current| : (node = current.next) page_count += 1;
    const encoded_page_count = std.math.cast(
        u16,
        page_count,
    ) orelse return error.PageCountOverflow;

    // SCREEN declares exactly how many immediately following PAGE records
    // belong to it.
    {
        var record_writer = try record.Writer.init(destination, .screen);
        errdefer record_writer.cancel();
        try encodePayload(
            screen,
            key,
            encoded_page_count,
            record_writer.payloadWriter(),
        );
        try record_writer.finish();
    }

    // PageList never compresses the active-boundary page or any later page.
    // Encoding this resident suffix therefore does not restore cold history or
    // otherwise mutate the source screen.
    node = first;
    while (node) |current| : (node = current.next) {
        std.debug.assert(current.pageIfResident() != null);
        try page.encode(current.pageAssumeResident(), destination);
    }
}

/// Errors possible while restoring a SCREEN and its declared PAGE sequence.
pub const DecodeError = PayloadDecodeError ||
    hyperlink.DecodeError ||
    page.DecodeError ||
    record.Reader.InitError ||
    record.Reader.FinishError ||
    TerminalPageList.Builder.FinishError ||
    TerminalPageList.IncreaseCapacityError ||
    error{
        /// The next record is valid but is not a SCREEN.
        UnexpectedRecordTag,

        /// A SCREEN must declare at least one PAGE.
        InvalidPageCount,

        /// The cursor is outside the restored active area.
        InvalidCursorPosition,
    };

/// One decoded SCREEN sequence and the native screen identified by its header.
pub const Decoded = struct {
    key: TerminalScreenKey,
    screen: TerminalScreen,

    /// Release the decoded native screen before ownership is transferred.
    pub fn deinit(self: *Decoded) void {
        self.screen.deinit();
        self.* = undefined;
    }
};

/// Restore one SCREEN and its declared PAGE records into native terminal state.
///
/// The caller supplies terminal-wide dimensions and policy. The record sequence
/// is decoded transactionally: on failure, all page, pin, hyperlink, and
/// temporary allocations are released and no partially restored Screen escapes.
/// The returned key selects the ScreenSet slot that owns the decoded screen.
pub fn decode(
    source: *std.Io.Reader,
    io_: std.Io,
    alloc: Allocator,
    options: TerminalScreen.Options,
) DecodeError!Decoded {
    // Decode and finish the self-contained SCREEN record before consuming any
    // of the PAGE records which follow it.
    var record_reader: record.Reader = undefined;
    try record_reader.init(source);
    if (record_reader.header.tag != .screen) {
        return error.UnexpectedRecordTag;
    }

    // The optional saved cursor and cursor hyperlink are both part of the
    // SCREEN payload. Keep ownership of the decoded hyperlink locally until it
    // has been copied into the native Screen.
    const payload_reader = record_reader.payloadReader();
    const header = try Header.decode(payload_reader);
    const saved_cursor = if (header.saved_cursor_present)
        try SavedCursor.decode(payload_reader)
    else
        null;
    var cursor_hyperlink = try decodeCursorHyperlink(
        payload_reader,
        alloc,
    );
    defer if (cursor_hyperlink) |*value| value.deinit(alloc);
    try record_reader.finish();

    const key = header.key;
    if (header.page_count == 0) return error.InvalidPageCount;

    // Dimensions are terminal-wide state supplied by the enclosing snapshot.
    // Validate them, and all cursor invariants which depend on them, before
    // allocating the declared pages.
    if (options.cols == 0 or options.rows == 0) {
        return error.InvalidDimensions;
    }
    if (header.cursor_x >= options.cols or
        header.cursor_y >= options.rows or
        (header.cursor_flags.pending_wrap and
            header.cursor_x != options.cols - 1))
    {
        return error.InvalidCursorPosition;
    }

    // Build the native page list transactionally. Alternate screens never
    // retain scrollback, while primary screens inherit the caller's limits.
    var result: TerminalScreen = result: {
        var builder = try TerminalPageList.Builder.init(alloc, .{
            .cols = options.cols,
            .rows = options.rows,
            .max_size = if (key == .alternate)
                0
            else
                options.max_scrollback_bytes,
            .max_lines = if (key == .alternate)
                0
            else
                options.max_scrollback_lines,
        });
        defer builder.deinit();

        // Allocate each PAGE at its declared capacity and decode directly into
        // builder-owned storage, avoiding an intermediate page representation.
        for (0..header.page_count) |_| {
            var decoder: page.Decoder = undefined;
            try decoder.init(source);
            const native_page = try builder.allocatePage(decoder.capacity());
            try decoder.decode(native_page, alloc);
        }

        // Finishing validates that the decoded suffix covers the active area
        // and establishes the PageList's active viewport.
        var pages = try builder.finish();
        errdefer pages.deinit();

        // Convert the payload-relative cursor position into the tracked native
        // pin and page-local row/cell pointers required by TerminalScreen.
        const cursor_pin_value = pages.pin(.{ .active = .{
            .x = header.cursor_x,
            .y = header.cursor_y,
        } }) orelse return error.InvalidCursorPosition;
        const cursor_pin = try pages.trackPin(cursor_pin_value);
        const cursor_rac = cursor_pin.rowAndCell();

        // Assemble the remaining native state from stable snapshot registries.
        // Derived state and page-local table references are repaired below.
        break :result .{
            .io = io_,
            .alloc = alloc,
            .pages = pages,
            .no_scrollback = key == .alternate or
                options.max_scrollback_bytes == 0,
            .cursor = .{
                .x = header.cursor_x,
                .y = header.cursor_y,
                .cursor_style = header.cursor_style,
                .pending_wrap = header.cursor_flags.pending_wrap,
                .protected = header.cursor_flags.protected,
                .style = header.cursor_pen,
                .hyperlink_implicit_id = header.hyperlink_implicit_id,
                .semantic_content = header.cursor_flags.semantic_content,
                .semantic_content_clear_eol = header.cursor_flags
                    .semantic_content_clear_eol,
                .page_pin = cursor_pin,
                .page_row = cursor_rac.row,
                .page_cell = cursor_rac.cell,
            },
            .saved_cursor = if (saved_cursor) |value|
                value.terminal()
            else
                null,
            .charset = header.charset,
            .protected_mode = header.protected_mode,
            .kitty_keyboard = header.kitty_keyboard.terminal(),
            .semantic_prompt = .{
                .seen = false,
                .click = header.semantic_click,
            },
        };
    };
    errdefer result.deinit();

    // Reinsert the concrete cursor style into its page-local style table. This
    // existing Screen path grows or splits the page when the decoded table is
    // already full.
    try result.manualStyleUpdate();

    // Reinsert the cursor hyperlink into its page-local hyperlink table. For an
    // implicit link, temporarily seed the counter with the encoded link ID,
    // then restore the independent next-ID counter from the header.
    if (cursor_hyperlink) |value| {
        switch (value.id) {
            .explicit => |id| try result.startHyperlink(value.uri, id),
            .implicit => |id| {
                result.cursor.hyperlink_implicit_id = id;
                try result.startHyperlink(value.uri, null);
                result.cursor.hyperlink_implicit_id =
                    header.hyperlink_implicit_id;
            },
        }
    }

    // `seen` is derived state. Only resident prompt metadata participates
    // because omitted history is outside the restored Screen model.
    result.semantic_prompt.seen = seen: {
        if (result.cursor.semantic_content == .prompt) break :seen true;

        var node = result.pages.getTopLeft(.screen).node;
        while (true) {
            const native_page = node.pageAssumeResident();
            const rows = native_page.rows.ptr(
                native_page.memory,
            )[0..native_page.size.rows];
            for (rows) |row| {
                if (row.semantic_prompt != .none) break :seen true;

                const cells = row.cells.ptr(
                    native_page.memory,
                )[0..native_page.size.cols];
                for (cells) |cell| {
                    if (cell.semantic_content == .prompt) break :seen true;
                }
            }

            node = node.next orelse break :seen false;
        }

        unreachable;
    };

    // Kitty image payloads are outside this record, but the restored Screen
    // must still receive the caller's terminal-wide storage policy.
    if (comptime build_options.kitty_graphics) {
        result.kitty_images.setLimit(
            io_,
            alloc,
            &result,
            options.kitty_image_storage_limit,
        ) catch unreachable;
        result.kitty_images.image_limits = options.kitty_image_loading_limits;
    }

    // All fallible reconstruction is complete; verify the native invariants
    // before transferring ownership to the caller.
    result.pages.assertIntegrity();
    result.assertIntegrity();
    return .{ .key = key, .screen = result };
}

/// Errors possible while decoding fixed SCREEN payload fields.
const PayloadDecodeError = style.DecodeError || error{
    InvalidKey,
    InvalidCursorStyle,
    InvalidCursorFlags,
    InvalidSemanticContent,
    InvalidCharsetState,
    InvalidProtectedMode,
    InvalidKittyKeyboardIndex,
    InvalidKittyKeyboardFlags,
    InvalidSemanticClick,
    InvalidSavedCursorPresent,
    InvalidSavedCursorFlags,
};

/// Flags encoded after the cursor's visual shape.
pub const CursorFlags = packed struct(u8) {
    pending_wrap: bool = false,
    protected: bool = false,
    semantic_content: terminal_page.Cell.SemanticContent = .output,
    semantic_content_clear_eol: bool = false,
    _padding: u3 = 0,

    fn init(cursor: *const TerminalScreen.Cursor) CursorFlags {
        return .{
            .pending_wrap = cursor.pending_wrap,
            .protected = cursor.protected,
            .semantic_content = cursor.semantic_content,
            .semantic_content_clear_eol = cursor
                .semantic_content_clear_eol,
        };
    }

    /// Decode and validate the cursor flag registry.
    pub fn decode(reader: *std.Io.Reader) PayloadDecodeError!CursorFlags {
        const raw = try reader.takeByte();
        const semantic_content_raw: u2 = @truncate(raw >> 2);
        _ = std.enums.fromInt(
            terminal_page.Cell.SemanticContent,
            semantic_content_raw,
        ) orelse return error.InvalidSemanticContent;

        const result: CursorFlags = @bitCast(raw);
        if (result._padding != 0) return error.InvalidCursorFlags;
        return result;
    }
};

/// The packed wire bits shared by current and saved cursor charset state.
///
/// Native enum values are stable, but their backing type is `c_int` in C ABI
/// builds. The wire therefore stores only checked integer values at its fixed
/// bit widths.
const CharsetBits = packed struct(u16) {
    g0: u2 = 0,
    g1: u2 = 0,
    g2: u2 = 0,
    g3: u2 = 0,
    gl: u2 = 0,
    gr: u2 = 2,
    single_shift: u3 = 0,
    _padding: u1 = 0,
};

fn enumFromInt(comptime T: type, raw: anytype) ?T {
    const Tag = @typeInfo(T).@"enum".tag_type;
    const value = std.math.cast(Tag, raw) orelse return null;
    return std.enums.fromInt(T, value);
}

fn encodeCharsetState(
    value: TerminalScreen.CharsetState,
) error{InvalidCharsetState}!u16 {
    const g0 = std.math.cast(
        u2,
        @intFromEnum(value.charsets.get(.G0)),
    ) orelse return error.InvalidCharsetState;
    const g1 = std.math.cast(
        u2,
        @intFromEnum(value.charsets.get(.G1)),
    ) orelse return error.InvalidCharsetState;
    const g2 = std.math.cast(
        u2,
        @intFromEnum(value.charsets.get(.G2)),
    ) orelse return error.InvalidCharsetState;
    const g3 = std.math.cast(
        u2,
        @intFromEnum(value.charsets.get(.G3)),
    ) orelse return error.InvalidCharsetState;
    const gl = std.math.cast(
        u2,
        @intFromEnum(value.gl),
    ) orelse return error.InvalidCharsetState;
    const gr = std.math.cast(
        u2,
        @intFromEnum(value.gr),
    ) orelse return error.InvalidCharsetState;
    const single_shift: u3 = if (value.single_shift) |slot| single_shift: {
        const raw = std.math.cast(
            u2,
            @intFromEnum(slot),
        ) orelse return error.InvalidCharsetState;
        break :single_shift @as(u3, raw) + 1;
    } else 0;

    const bits: CharsetBits = .{
        .g0 = g0,
        .g1 = g1,
        .g2 = g2,
        .g3 = g3,
        .gl = gl,
        .gr = gr,
        .single_shift = single_shift,
    };
    return @bitCast(bits);
}

fn decodeCharsetState(
    raw: u16,
) error{InvalidCharsetState}!TerminalScreen.CharsetState {
    const bits: CharsetBits = @bitCast(raw);
    if (bits._padding != 0 or bits.single_shift > 4) {
        return error.InvalidCharsetState;
    }

    var result: TerminalScreen.CharsetState = .{
        .gl = enumFromInt(
            terminal_charsets.Slots,
            bits.gl,
        ) orelse return error.InvalidCharsetState,
        .gr = enumFromInt(
            terminal_charsets.Slots,
            bits.gr,
        ) orelse return error.InvalidCharsetState,
        .single_shift = if (bits.single_shift == 0)
            null
        else
            enumFromInt(
                terminal_charsets.Slots,
                bits.single_shift - 1,
            ) orelse return error.InvalidCharsetState,
    };
    result.charsets.set(
        .G0,
        enumFromInt(
            terminal_charsets.Charset,
            bits.g0,
        ) orelse return error.InvalidCharsetState,
    );
    result.charsets.set(
        .G1,
        enumFromInt(
            terminal_charsets.Charset,
            bits.g1,
        ) orelse return error.InvalidCharsetState,
    );
    result.charsets.set(
        .G2,
        enumFromInt(
            terminal_charsets.Charset,
            bits.g2,
        ) orelse return error.InvalidCharsetState,
    );
    result.charsets.set(
        .G3,
        enumFromInt(
            terminal_charsets.Charset,
            bits.g3,
        ) orelse return error.InvalidCharsetState,
    );
    return result;
}

/// The complete fixed-size Kitty keyboard stack.
pub const KittyKeyboard = struct {
    index: u8 = 0,
    flags: [8]Flags = @splat(.{}),

    /// One byte in the fixed Kitty keyboard flag stack.
    pub const Flags = packed struct(u8) {
        disambiguate: bool = false,
        report_events: bool = false,
        report_alternates: bool = false,
        report_all: bool = false,
        report_associated: bool = false,
        _padding: u3 = 0,

        /// Decode and validate one Kitty keyboard flag byte.
        pub fn decode(reader: *std.Io.Reader) PayloadDecodeError!Flags {
            const result: Flags = @bitCast(try reader.takeByte());
            if (result._padding != 0) {
                return error.InvalidKittyKeyboardFlags;
            }
            return result;
        }
    };

    fn init(value: terminal_kitty.KeyFlagStack) KittyKeyboard {
        var result: KittyKeyboard = .{ .index = value.idx };
        for (value.flags, &result.flags) |native, *snapshot| {
            snapshot.* = .{
                .disambiguate = native.disambiguate,
                .report_events = native.report_events,
                .report_alternates = native.report_alternates,
                .report_all = native.report_all,
                .report_associated = native.report_associated,
            };
        }
        return result;
    }

    fn terminal(self: KittyKeyboard) terminal_kitty.KeyFlagStack {
        var result: terminal_kitty.KeyFlagStack = .{
            .idx = @intCast(self.index),
        };
        for (self.flags, &result.flags) |snapshot, *native| {
            native.* = .{
                .disambiguate = snapshot.disambiguate,
                .report_events = snapshot.report_events,
                .report_alternates = snapshot.report_alternates,
                .report_all = snapshot.report_all,
                .report_associated = snapshot.report_associated,
            };
        }
        return result;
    }

    /// Decode and validate the complete fixed Kitty keyboard stack.
    pub fn decode(reader: *std.Io.Reader) PayloadDecodeError!KittyKeyboard {
        const index = try reader.takeByte();
        if (index >= 8) return error.InvalidKittyKeyboardIndex;

        var flags: [8]Flags = undefined;
        for (&flags) |*entry| entry.* = try Flags.decode(reader);
        return .{ .index = index, .flags = flags };
    }
};

/// Decode and validate the semantic-click kind and value bytes.
fn decodeSemanticClick(
    reader: *std.Io.Reader,
) PayloadDecodeError!TerminalScreen.SemanticPrompt.SemanticClick {
    const kind = enumFromInt(
        TerminalScreen.SemanticPrompt.SemanticClickKind,
        try reader.takeByte(),
    ) orelse return error.InvalidSemanticClick;
    const value = try reader.takeByte();

    return switch (kind) {
        .none => if (value == 0)
            .none
        else
            error.InvalidSemanticClick,
        .click_events => .{ .click_events = enumFromInt(
            terminal_osc.semantic_prompt.ClickEvents,
            value,
        ) orelse return error.InvalidSemanticClick },
        .cl => .{ .cl = enumFromInt(
            terminal_osc.semantic_prompt.Click,
            value,
        ) orelse return error.InvalidSemanticClick },
    };
}

/// The optional fixed-size saved cursor state.
pub const SavedCursor = struct {
    /// Number of bytes written by `encode`, calculated using the encoder.
    pub const len = computeLen();

    comptime {
        std.debug.assert(len == 23);
    }

    x: u16,
    y: u16,
    pen: TerminalStyle,
    flags: Flags,
    charset: TerminalScreen.CharsetState,

    /// Flags encoded with an optional saved cursor.
    pub const Flags = packed struct(u8) {
        protected: bool = false,
        pending_wrap: bool = false,
        origin: bool = false,
        _padding: u5 = 0,

        /// Decode and validate saved cursor flags.
        pub fn decode(reader: *std.Io.Reader) PayloadDecodeError!Flags {
            const result: Flags = @bitCast(try reader.takeByte());
            if (result._padding != 0) return error.InvalidSavedCursorFlags;
            return result;
        }
    };

    fn init(value: TerminalScreen.SavedCursor) SavedCursor {
        return .{
            .x = value.x,
            .y = value.y,
            .pen = value.style,
            .flags = .{
                .protected = value.protected,
                .pending_wrap = value.pending_wrap,
                .origin = value.origin,
            },
            .charset = value.charset,
        };
    }

    fn terminal(self: SavedCursor) TerminalScreen.SavedCursor {
        return .{
            .x = self.x,
            .y = self.y,
            .style = self.pen,
            .protected = self.flags.protected,
            .pending_wrap = self.flags.pending_wrap,
            .origin = self.flags.origin,
            .charset = self.charset,
        };
    }

    /// Encode one optional saved cursor value.
    pub fn encode(
        self: SavedCursor,
        writer: *std.Io.Writer,
    ) PayloadEncodeError!void {
        if (self.flags._padding != 0) {
            return error.InvalidSavedCursorFlags;
        }
        const charset = try encodeCharsetState(self.charset);

        try io.writeInt(writer, u16, self.x);
        try io.writeInt(writer, u16, self.y);
        try style.encode(self.pen, writer);
        try writer.writeByte(@bitCast(self.flags));
        try io.writeInt(writer, u16, charset);
    }

    /// Decode and validate one optional saved cursor value.
    pub fn decode(reader: *std.Io.Reader) PayloadDecodeError!SavedCursor {
        return .{
            .x = try io.readInt(reader, u16),
            .y = try io.readInt(reader, u16),
            .pen = try style.decode(reader),
            .flags = try Flags.decode(reader),
            .charset = try decodeCharsetState(
                try io.readInt(reader, u16),
            ),
        };
    }

    fn computeLen() usize {
        comptime {
            var buf: [128]u8 = undefined;
            var writer: std.Io.Writer = .fixed(&buf);
            const value: SavedCursor = .{
                .x = 0,
                .y = 0,
                .pen = .{},
                .flags = .{},
                .charset = .{},
            };
            value.encode(&writer) catch unreachable;
            return writer.end;
        }
    }
};

/// The fixed fields at the start of every SCREEN payload.
pub const Header = struct {
    /// Number of bytes written by `encode`, calculated using the encoder.
    pub const len = computeLen();

    comptime {
        std.debug.assert(len == 45);
    }

    key: TerminalScreenKey,
    /// Complete pages in the minimal suffix covering the active area.
    page_count: u16,
    cursor_x: u16,
    cursor_y: u16,
    cursor_style: TerminalScreen.CursorStyle,
    cursor_flags: CursorFlags,
    cursor_pen: TerminalStyle,
    hyperlink_implicit_id: u32,
    charset: TerminalScreen.CharsetState,
    protected_mode: terminal_ansi.ProtectedMode,
    kitty_keyboard: KittyKeyboard,
    semantic_click: TerminalScreen.SemanticPrompt.SemanticClick,
    saved_cursor_present: bool,

    /// Initialize the fixed header from one native screen.
    fn init(
        screen: *const TerminalScreen,
        key: TerminalScreenKey,
        page_count: u16,
    ) Header {
        return .{
            .key = key,
            .page_count = page_count,
            .cursor_x = screen.cursor.x,
            .cursor_y = screen.cursor.y,
            .cursor_style = screen.cursor.cursor_style,
            .cursor_flags = .init(&screen.cursor),
            .cursor_pen = screen.cursor.style,
            .hyperlink_implicit_id = screen.cursor.hyperlink_implicit_id,
            .charset = screen.charset,
            .protected_mode = screen.protected_mode,
            .kitty_keyboard = .init(screen.kitty_keyboard),
            .semantic_click = screen.semantic_prompt.click,
            .saved_cursor_present = screen.saved_cursor != null,
        };
    }

    /// Encode the fixed SCREEN payload header field by field.
    pub fn encode(
        self: Header,
        writer: *std.Io.Writer,
    ) PayloadEncodeError!void {
        // Validate packed cursor state before writing any bytes.
        if (self.cursor_flags._padding != 0) {
            return error.InvalidCursorFlags;
        }

        // Validate and narrow native charset enum values before writing.
        const charset = try encodeCharsetState(self.charset);

        // Validate the complete Kitty keyboard stack.
        if (self.kitty_keyboard.index >= self.kitty_keyboard.flags.len) {
            return error.InvalidKittyKeyboardIndex;
        }
        for (self.kitty_keyboard.flags) |flags| {
            if (flags._padding != 0) {
                return error.InvalidKittyKeyboardFlags;
            }
        }

        // Screen identity and cursor position.
        try io.writeInt(writer, u16, @intCast(@intFromEnum(self.key)));
        try io.writeInt(writer, u16, self.page_count);
        try io.writeInt(writer, u16, self.cursor_x);
        try io.writeInt(writer, u16, self.cursor_y);

        // Current cursor rendering state.
        try writer.writeByte(@intCast(@intFromEnum(self.cursor_style)));
        try writer.writeByte(@bitCast(self.cursor_flags));
        try style.encode(self.cursor_pen, writer);
        try io.writeInt(writer, u32, self.hyperlink_implicit_id);

        // Charset and selective-erase state.
        try io.writeInt(writer, u16, charset);
        try writer.writeByte(@intCast(@intFromEnum(self.protected_mode)));

        // Keyboard modes and semantic-click state.
        try writer.writeByte(self.kitty_keyboard.index);
        for (self.kitty_keyboard.flags) |flags| {
            try writer.writeByte(@bitCast(flags));
        }
        try writer.writeByte(@intCast(@intFromEnum(
            std.meta.activeTag(self.semantic_click),
        )));
        switch (self.semantic_click) {
            .none => try writer.writeByte(0),
            .click_events => |value| try writer.writeByte(
                @intCast(@intFromEnum(value)),
            ),
            .cl => |value| try writer.writeByte(
                @intCast(@intFromEnum(value)),
            ),
        }

        // Presence of the optional saved-cursor suffix.
        try writer.writeByte(@intFromBool(self.saved_cursor_present));
    }

    /// Decode and validate the fixed SCREEN payload header.
    pub fn decode(reader: *std.Io.Reader) PayloadDecodeError!Header {
        // Screen identity and cursor position.
        const key = enumFromInt(
            TerminalScreenKey,
            try io.readInt(reader, u16),
        ) orelse return error.InvalidKey;
        const page_count = try io.readInt(reader, u16);
        const cursor_x = try io.readInt(reader, u16);
        const cursor_y = try io.readInt(reader, u16);

        // Current cursor rendering state.
        const cursor_style = enumFromInt(
            TerminalScreen.CursorStyle,
            try reader.takeByte(),
        ) orelse return error.InvalidCursorStyle;
        const cursor_flags = try CursorFlags.decode(reader);
        const cursor_pen = try style.decode(reader);
        const hyperlink_implicit_id = try io.readInt(reader, u32);

        // Charset and selective-erase state.
        const charset = try decodeCharsetState(
            try io.readInt(reader, u16),
        );
        const protected_mode = enumFromInt(
            terminal_ansi.ProtectedMode,
            try reader.takeByte(),
        ) orelse return error.InvalidProtectedMode;

        // Keyboard modes and semantic-click state.
        const kitty_keyboard = try KittyKeyboard.decode(reader);
        const semantic_click = try decodeSemanticClick(reader);

        // Presence of the optional saved-cursor suffix.
        const saved_cursor_present = switch (try reader.takeByte()) {
            0 => false,
            1 => true,
            else => return error.InvalidSavedCursorPresent,
        };

        return .{
            .key = key,
            .page_count = page_count,
            .cursor_x = cursor_x,
            .cursor_y = cursor_y,

            .cursor_style = cursor_style,
            .cursor_flags = cursor_flags,
            .cursor_pen = cursor_pen,
            .hyperlink_implicit_id = hyperlink_implicit_id,

            .charset = charset,
            .protected_mode = protected_mode,

            .kitty_keyboard = kitty_keyboard,
            .semantic_click = semantic_click,

            .saved_cursor_present = saved_cursor_present,
        };
    }

    fn computeLen() usize {
        comptime {
            var buf: [128]u8 = undefined;
            var writer: std.Io.Writer = .fixed(&buf);
            const value: Header = .{
                .key = .primary,
                .page_count = 0,
                .cursor_x = 0,
                .cursor_y = 0,
                .cursor_style = .bar,
                .cursor_flags = .{},
                .cursor_pen = .{},
                .hyperlink_implicit_id = 0,
                .charset = .{},
                .protected_mode = .off,
                .kitty_keyboard = .{},
                .semantic_click = .none,
                .saved_cursor_present = false,
            };
            value.encode(&writer) catch unreachable;
            return writer.end;
        }
    }
};

/// Encode the SCREEN payload, excluding its following PAGE records.
fn encodePayload(
    screen: *const TerminalScreen,
    key: TerminalScreenKey,
    page_count: u16,
    writer: *std.Io.Writer,
) PayloadEncodeError!void {
    try Header.init(screen, key, page_count).encode(writer);

    if (screen.saved_cursor) |saved_cursor| {
        try SavedCursor.init(saved_cursor).encode(writer);
    }

    const cursor_hyperlink: ?TerminalHyperlink =
        if (screen.cursor.hyperlink) |entry| entry.* else null;
    try encodeCursorHyperlink(cursor_hyperlink, writer);
}

/// The variable cursor hyperlink at the end of every SCREEN payload.
pub const CursorHyperlink = ?TerminalHyperlink;

/// Encode the optional cursor hyperlink at the end of a SCREEN payload.
pub fn encodeCursorHyperlink(
    value: CursorHyperlink,
    writer: *std.Io.Writer,
) hyperlink.EncodeError!void {
    if (value) |entry| return hyperlink.encode(entry, writer);
    try writer.writeByte(0);
}

/// Decode one allocator-owned optional cursor hyperlink.
///
/// The caller owns a non-null returned value and must call `Hyperlink.deinit`.
pub fn decodeCursorHyperlink(
    reader: *std.Io.Reader,
    alloc: Allocator,
) hyperlink.DecodeError!CursorHyperlink {
    if (try reader.peekByte() == 0) {
        _ = try reader.takeByte();
        return null;
    }
    return try hyperlink.decode(reader, alloc);
}

const test_header_fixture =
    "\x01\x00\x03\x02\x05\x04\x07\x06\x03\x19" ++
    "\x00\x00\x00\x00\x01\x7f\x00\x00" ++
    "\x02\x12\x34\x56\xff\x03\x00\x00" ++
    "\x0d\x0c\x0b\x0a\xe4\x3d\x02\x07" ++
    "\x01\x02\x04\x08\x10\x1f\x00\x11" ++
    "\x02\x03\x01";

const test_saved_cursor_fixture =
    "\x02\x01\x04\x03" ++
    "\x00\x00\x00\x00\x00\x00\x00\x00" ++
    "\x00\x00\x00\x00\x00\x00\x00\x00" ++
    "\x07\xe4\x3d";

fn testCharsetState() TerminalScreen.CharsetState {
    var result: TerminalScreen.CharsetState = .{
        .gl = .G1,
        .gr = .G3,
        .single_shift = .G2,
    };
    result.charsets.set(.G0, .utf8);
    result.charsets.set(.G1, .ascii);
    result.charsets.set(.G2, .british);
    result.charsets.set(.G3, .dec_special);
    return result;
}

fn testHeader() Header {
    return .{
        .key = .alternate,
        .page_count = 0x0203,
        .cursor_x = 0x0405,
        .cursor_y = 0x0607,
        .cursor_style = .block_hollow,
        .cursor_flags = .{
            .pending_wrap = true,
            .semantic_content = .prompt,
            .semantic_content_clear_eol = true,
        },
        .cursor_pen = .{
            .fg_color = .none,
            .bg_color = .{ .palette = 0x7f },
            .underline_color = .{ .rgb = .{
                .r = 0x12,
                .g = 0x34,
                .b = 0x56,
            } },
            .flags = .{
                .bold = true,
                .italic = true,
                .faint = true,
                .blink = true,
                .inverse = true,
                .invisible = true,
                .strikethrough = true,
                .overline = true,
                .underline = .curly,
            },
        },
        .hyperlink_implicit_id = 0x0a0b0c0d,
        .charset = testCharsetState(),
        .protected_mode = .dec,
        .kitty_keyboard = .{
            .index = 7,
            .flags = .{
                .{ .disambiguate = true },
                .{ .report_events = true },
                .{ .report_alternates = true },
                .{ .report_all = true },
                .{ .report_associated = true },
                .{
                    .disambiguate = true,
                    .report_events = true,
                    .report_alternates = true,
                    .report_all = true,
                    .report_associated = true,
                },
                .{},
                .{
                    .disambiguate = true,
                    .report_associated = true,
                },
            },
        },
        .semantic_click = .{ .cl = .smart_vertical },
        .saved_cursor_present = true,
    };
}

fn testSavedCursor() SavedCursor {
    return .{
        .x = 0x0102,
        .y = 0x0304,
        .pen = .{},
        .flags = .{
            .protected = true,
            .pending_wrap = true,
            .origin = true,
        },
        .charset = testCharsetState(),
    };
}

test "SCREEN header golden encoding and decoding" {
    try std.testing.expectEqual(Header.len, test_header_fixture.len);

    var encoded: [Header.len]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&encoded);
    try testHeader().encode(&writer);

    try std.testing.expectEqualStrings(
        test_header_fixture,
        writer.buffered(),
    );

    var source: std.Io.Reader = .fixed(test_header_fixture);
    var buffer: [1]u8 = undefined;
    var limited = source.limited(.unlimited, &buffer);

    try std.testing.expectEqualDeep(
        testHeader(),
        try Header.decode(&limited.interface),
    );
}

test "native enum values used by the SCREEN format" {
    const keys = [_]TerminalScreenKey{ .primary, .alternate };
    for (keys, 0..) |value, expected| {
        try std.testing.expectEqual(
            expected,
            @as(usize, @intCast(@intFromEnum(value))),
        );
    }

    const cursor_styles = [_]TerminalScreen.CursorStyle{
        .bar,
        .block,
        .underline,
        .block_hollow,
    };
    for (cursor_styles, 0..) |value, expected| {
        try std.testing.expectEqual(
            expected,
            @as(usize, @intCast(@intFromEnum(value))),
        );
    }

    const semantic_contents = [_]terminal_page.Cell.SemanticContent{
        .output,
        .input,
        .prompt,
    };
    for (semantic_contents, 0..) |value, expected| {
        try std.testing.expectEqual(
            expected,
            @as(usize, @intCast(@intFromEnum(value))),
        );
    }

    const charsets = [_]terminal_charsets.Charset{
        .utf8,
        .ascii,
        .british,
        .dec_special,
    };
    for (charsets, 0..) |value, expected| {
        try std.testing.expectEqual(
            expected,
            @as(usize, @intCast(@intFromEnum(value))),
        );
    }

    const slots = [_]terminal_charsets.Slots{ .G0, .G1, .G2, .G3 };
    for (slots, 0..) |value, expected| {
        try std.testing.expectEqual(
            expected,
            @as(usize, @intCast(@intFromEnum(value))),
        );
    }

    const protected_modes = [_]terminal_ansi.ProtectedMode{
        .off,
        .iso,
        .dec,
    };
    for (protected_modes, 0..) |value, expected| {
        try std.testing.expectEqual(
            expected,
            @as(usize, @intCast(@intFromEnum(value))),
        );
    }

    const click_kinds = [_]TerminalScreen.SemanticPrompt.SemanticClickKind{
        .none,
        .click_events,
        .cl,
    };
    for (click_kinds, 0..) |value, expected| {
        try std.testing.expectEqual(
            expected,
            @as(usize, @intCast(@intFromEnum(value))),
        );
    }

    const click_events = [_]terminal_osc.semantic_prompt.ClickEvents{
        .absolute,
        .relative,
    };
    for (click_events, 0..) |value, expected| {
        try std.testing.expectEqual(
            expected,
            @as(usize, @intCast(@intFromEnum(value))),
        );
    }

    const clicks = [_]terminal_osc.semantic_prompt.Click{
        .line,
        .multiple,
        .conservative_vertical,
        .smart_vertical,
    };
    for (clicks, 0..) |value, expected| {
        try std.testing.expectEqual(
            expected,
            @as(usize, @intCast(@intFromEnum(value))),
        );
    }
}

test "cursor, Kitty, and saved cursor flag bit layouts" {
    const CursorCase = struct {
        value: CursorFlags,
        expected: u8,
    };
    const cursor_cases = [_]CursorCase{
        .{ .value = .{ .pending_wrap = true }, .expected = 1 << 0 },
        .{ .value = .{ .protected = true }, .expected = 1 << 1 },
        .{
            .value = .{ .semantic_content = .input },
            .expected = 1 << 2,
        },
        .{
            .value = .{ .semantic_content = .prompt },
            .expected = 2 << 2,
        },
        .{
            .value = .{ .semantic_content_clear_eol = true },
            .expected = 1 << 4,
        },
    };
    for (cursor_cases) |case| {
        try std.testing.expectEqual(
            case.expected,
            @as(u8, @bitCast(case.value)),
        );
    }

    const KittyCase = struct {
        value: KittyKeyboard.Flags,
        expected: u8,
    };
    const kitty_cases = [_]KittyCase{
        .{ .value = .{ .disambiguate = true }, .expected = 1 << 0 },
        .{ .value = .{ .report_events = true }, .expected = 1 << 1 },
        .{
            .value = .{ .report_alternates = true },
            .expected = 1 << 2,
        },
        .{ .value = .{ .report_all = true }, .expected = 1 << 3 },
        .{
            .value = .{ .report_associated = true },
            .expected = 1 << 4,
        },
    };
    for (kitty_cases) |case| {
        try std.testing.expectEqual(
            case.expected,
            @as(u8, @bitCast(case.value)),
        );
    }

    const SavedCase = struct {
        value: SavedCursor.Flags,
        expected: u8,
    };
    const saved_cases = [_]SavedCase{
        .{ .value = .{ .protected = true }, .expected = 1 << 0 },
        .{ .value = .{ .pending_wrap = true }, .expected = 1 << 1 },
        .{ .value = .{ .origin = true }, .expected = 1 << 2 },
    };
    for (saved_cases) |case| {
        try std.testing.expectEqual(
            case.expected,
            @as(u8, @bitCast(case.value)),
        );
    }
}

test "header encoding rejects invalid state" {
    var encoded: [Header.len]u8 = undefined;

    var invalid_cursor_flags = testHeader();
    invalid_cursor_flags.cursor_flags._padding = 1;
    var cursor_flags_writer: std.Io.Writer = .fixed(&encoded);
    try std.testing.expectError(
        error.InvalidCursorFlags,
        invalid_cursor_flags.encode(&cursor_flags_writer),
    );

    var invalid_kitty_index = testHeader();
    invalid_kitty_index.kitty_keyboard.index = 8;
    var kitty_index_writer: std.Io.Writer = .fixed(&encoded);
    try std.testing.expectError(
        error.InvalidKittyKeyboardIndex,
        invalid_kitty_index.encode(&kitty_index_writer),
    );

    var invalid_kitty_flags = testHeader();
    invalid_kitty_flags.kitty_keyboard.flags[3]._padding = 1;
    var kitty_flags_writer: std.Io.Writer = .fixed(&encoded);
    try std.testing.expectError(
        error.InvalidKittyKeyboardFlags,
        invalid_kitty_flags.encode(&kitty_flags_writer),
    );
}

test "header decoding rejects invalid values" {
    const valid = [_]u8{0} ** Header.len;

    var invalid_key = valid;
    invalid_key[0] = 2;
    var key_reader: std.Io.Reader = .fixed(&invalid_key);
    try std.testing.expectError(error.InvalidKey, Header.decode(&key_reader));

    var invalid_cursor_style = valid;
    invalid_cursor_style[8] = 4;
    var cursor_style_reader: std.Io.Reader = .fixed(&invalid_cursor_style);
    try std.testing.expectError(
        error.InvalidCursorStyle,
        Header.decode(&cursor_style_reader),
    );

    var invalid_cursor_flags = valid;
    invalid_cursor_flags[9] = 1 << 5;
    var cursor_flags_reader: std.Io.Reader = .fixed(&invalid_cursor_flags);
    try std.testing.expectError(
        error.InvalidCursorFlags,
        Header.decode(&cursor_flags_reader),
    );

    var invalid_semantic_content = valid;
    invalid_semantic_content[9] = 3 << 2;
    var semantic_content_reader: std.Io.Reader = .fixed(
        &invalid_semantic_content,
    );
    try std.testing.expectError(
        error.InvalidSemanticContent,
        Header.decode(&semantic_content_reader),
    );

    var invalid_style = valid;
    invalid_style[10] = 3;
    var style_reader: std.Io.Reader = .fixed(&invalid_style);
    try std.testing.expectError(
        error.InvalidColorKind,
        Header.decode(&style_reader),
    );

    var invalid_charset_reserved = valid;
    invalid_charset_reserved[31] = 1 << 7;
    var charset_reserved_reader: std.Io.Reader = .fixed(
        &invalid_charset_reserved,
    );
    try std.testing.expectError(
        error.InvalidCharsetState,
        Header.decode(&charset_reserved_reader),
    );

    var invalid_single_shift = valid;
    invalid_single_shift[31] = 5 << 4;
    var single_shift_reader: std.Io.Reader = .fixed(&invalid_single_shift);
    try std.testing.expectError(
        error.InvalidCharsetState,
        Header.decode(&single_shift_reader),
    );

    var invalid_protected_mode = valid;
    invalid_protected_mode[32] = 3;
    var protected_mode_reader: std.Io.Reader = .fixed(
        &invalid_protected_mode,
    );
    try std.testing.expectError(
        error.InvalidProtectedMode,
        Header.decode(&protected_mode_reader),
    );

    var invalid_kitty_index = valid;
    invalid_kitty_index[33] = 8;
    var kitty_index_reader: std.Io.Reader = .fixed(&invalid_kitty_index);
    try std.testing.expectError(
        error.InvalidKittyKeyboardIndex,
        Header.decode(&kitty_index_reader),
    );

    for (34..42) |offset| {
        var invalid_kitty_flags = valid;
        invalid_kitty_flags[offset] = 1 << 5;
        var reader: std.Io.Reader = .fixed(&invalid_kitty_flags);
        try std.testing.expectError(
            error.InvalidKittyKeyboardFlags,
            Header.decode(&reader),
        );
    }

    var invalid_semantic_click_kind = valid;
    invalid_semantic_click_kind[42] = 3;
    var semantic_click_kind_reader: std.Io.Reader = .fixed(
        &invalid_semantic_click_kind,
    );
    try std.testing.expectError(
        error.InvalidSemanticClick,
        Header.decode(&semantic_click_kind_reader),
    );

    const invalid_semantic_clicks = [_][2]u8{
        .{ 0, 1 },
        .{ 1, 2 },
        .{ 2, 4 },
    };
    for (invalid_semantic_clicks) |invalid| {
        var fixture = valid;
        fixture[42] = invalid[0];
        fixture[43] = invalid[1];
        var reader: std.Io.Reader = .fixed(&fixture);
        try std.testing.expectError(
            error.InvalidSemanticClick,
            Header.decode(&reader),
        );
    }

    var invalid_saved_cursor_present = valid;
    invalid_saved_cursor_present[44] = 2;
    var saved_cursor_present_reader: std.Io.Reader = .fixed(
        &invalid_saved_cursor_present,
    );
    try std.testing.expectError(
        error.InvalidSavedCursorPresent,
        Header.decode(&saved_cursor_present_reader),
    );
}

test "header decoding rejects every truncation" {
    for (0..Header.len) |fixture_len| {
        var reader: std.Io.Reader = .fixed(
            test_header_fixture[0..fixture_len],
        );
        try std.testing.expectError(error.EndOfStream, Header.decode(&reader));
    }
}

test "native SCREEN payload omits absent optional state" {
    var screen = try TerminalScreen.init(
        std.testing.io,
        std.testing.allocator,
        .{ .cols = 2, .rows = 2, .max_scrollback_bytes = 0 },
    );
    defer screen.deinit();

    var encoded: [Header.len + 1]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&encoded);
    try encodePayload(&screen, .primary, 1, &writer);
    try std.testing.expectEqual(encoded.len, writer.end);

    var reader: std.Io.Reader = .fixed(writer.buffered());
    const header = try Header.decode(&reader);
    try std.testing.expectEqual(TerminalScreenKey.primary, header.key);
    try std.testing.expectEqual(@as(u16, 1), header.page_count);
    try std.testing.expect(!header.saved_cursor_present);
    try std.testing.expectEqual(
        null,
        try decodeCursorHyperlink(&reader, std.testing.allocator),
    );
}

test "saved cursor golden encoding and decoding" {
    try std.testing.expectEqual(
        SavedCursor.len,
        test_saved_cursor_fixture.len,
    );

    var encoded: [SavedCursor.len]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&encoded);
    try testSavedCursor().encode(&writer);
    try std.testing.expectEqualStrings(
        test_saved_cursor_fixture,
        writer.buffered(),
    );

    var source: std.Io.Reader = .fixed(test_saved_cursor_fixture);
    var buffer: [1]u8 = undefined;
    var limited = source.limited(.unlimited, &buffer);
    try std.testing.expectEqualDeep(
        testSavedCursor(),
        try SavedCursor.decode(&limited.interface),
    );
}

test "saved cursor rejects invalid state" {
    var encoded: [SavedCursor.len]u8 = undefined;

    var invalid_flags = testSavedCursor();
    invalid_flags.flags._padding = 1;
    var flags_writer: std.Io.Writer = .fixed(&encoded);
    try std.testing.expectError(
        error.InvalidSavedCursorFlags,
        invalid_flags.encode(&flags_writer),
    );

    const valid = [_]u8{0} ** SavedCursor.len;

    var invalid_flags_bytes = valid;
    invalid_flags_bytes[20] = 1 << 3;
    var flags_reader: std.Io.Reader = .fixed(&invalid_flags_bytes);
    try std.testing.expectError(
        error.InvalidSavedCursorFlags,
        SavedCursor.decode(&flags_reader),
    );

    var invalid_charset_reserved = valid;
    invalid_charset_reserved[22] = 1 << 7;
    var charset_reserved_reader: std.Io.Reader = .fixed(
        &invalid_charset_reserved,
    );
    try std.testing.expectError(
        error.InvalidCharsetState,
        SavedCursor.decode(&charset_reserved_reader),
    );

    var invalid_single_shift = valid;
    invalid_single_shift[22] = 5 << 4;
    var single_shift_reader: std.Io.Reader = .fixed(&invalid_single_shift);
    try std.testing.expectError(
        error.InvalidCharsetState,
        SavedCursor.decode(&single_shift_reader),
    );
}

test "saved cursor decoding rejects every truncation" {
    for (0..SavedCursor.len) |fixture_len| {
        var reader: std.Io.Reader = .fixed(
            test_saved_cursor_fixture[0..fixture_len],
        );
        try std.testing.expectError(
            error.EndOfStream,
            SavedCursor.decode(&reader),
        );
    }
}

test "cursor hyperlink null encoding and decoding" {
    var none_encoded: [1]u8 = undefined;
    var none_writer: std.Io.Writer = .fixed(&none_encoded);
    try encodeCursorHyperlink(null, &none_writer);
    try std.testing.expectEqualStrings("\x00", none_writer.buffered());

    var none_reader: std.Io.Reader = .fixed(none_writer.buffered());
    try std.testing.expectEqual(
        null,
        try decodeCursorHyperlink(&none_reader, std.testing.allocator),
    );
}

test "framed native SCREEN and PAGE sequence" {
    var screen = try TerminalScreen.init(
        std.testing.io,
        std.testing.allocator,
        .{ .cols = 8, .rows = 8, .max_scrollback_bytes = 0 },
    );
    defer screen.deinit();

    // Configure the live cursor state represented by the fixed header.
    screen.cursorAbsolute(7, 6);
    screen.cursor.cursor_style = .block_hollow;
    screen.cursor.pending_wrap = true;
    screen.cursor.protected = false;
    screen.cursor.semantic_content = .prompt;
    screen.cursor.semantic_content_clear_eol = true;
    screen.cursor.style = testHeader().cursor_pen;
    screen.cursor.hyperlink_implicit_id = 0x0a0b0c0d;

    // Configure the screen-wide modes and packed charset state.
    var charset: TerminalScreen.CharsetState = .{
        .gl = .G1,
        .gr = .G3,
        .single_shift = .G2,
    };
    charset.charsets.set(.G0, .utf8);
    charset.charsets.set(.G1, .ascii);
    charset.charsets.set(.G2, .british);
    charset.charsets.set(.G3, .dec_special);
    screen.charset = charset;
    screen.protected_mode = .dec;
    screen.kitty_keyboard = .{
        .idx = 7,
        .flags = .{
            .{ .disambiguate = true },
            .{ .report_events = true },
            .{ .report_alternates = true },
            .{ .report_all = true },
            .{ .report_associated = true },
            .{
                .disambiguate = true,
                .report_events = true,
                .report_alternates = true,
                .report_all = true,
                .report_associated = true,
            },
            .{},
            .{
                .disambiguate = true,
                .report_associated = true,
            },
        },
    };
    screen.semantic_prompt = .{
        .seen = true,
        .click = .{ .cl = .smart_vertical },
    };

    // Configure the optional cursor state encoded after the fixed header.
    screen.saved_cursor = .{
        .x = 0x0102,
        .y = 0x0304,
        .style = .{},
        .protected = true,
        .pending_wrap = true,
        .origin = true,
        .charset = charset,
    };
    try screen.startHyperlink("cursor-uri", null);

    var destination: std.Io.Writer.Allocating = .init(
        std.testing.allocator,
    );
    defer destination.deinit();
    try destination.writer.writeAll("prefix");
    try encode(&screen, .alternate, &destination);

    try std.testing.expectEqualStrings(
        "prefix",
        destination.written()[0..6],
    );

    // The complete sequence restores directly into native Screen/PageList
    // state, including page-local cursor references.
    var restore_source: std.Io.Reader = .fixed(destination.written()[6..]);
    var decoded = try decode(
        &restore_source,
        std.testing.io,
        std.testing.allocator,
        .{ .cols = 8, .rows = 8, .max_scrollback_bytes = 0 },
    );
    defer decoded.deinit();
    try std.testing.expectEqual(TerminalScreenKey.alternate, decoded.key);
    const restored = &decoded.screen;

    try std.testing.expect(restored.no_scrollback);
    try std.testing.expectEqual(@as(u16, 7), restored.cursor.x);
    try std.testing.expectEqual(@as(u16, 6), restored.cursor.y);
    try std.testing.expectEqual(
        TerminalScreen.CursorStyle.block_hollow,
        restored.cursor.cursor_style,
    );
    try std.testing.expect(restored.cursor.pending_wrap);
    try std.testing.expectEqual(
        terminal_page.Cell.SemanticContent.prompt,
        restored.cursor.semantic_content,
    );
    try std.testing.expect(
        restored.cursor.style.eql(testHeader().cursor_pen),
    );
    try std.testing.expect(restored.cursor.style_id != terminal_style.default_id);
    try std.testing.expectEqual(
        @as(u32, 0x0a0b0c0e),
        restored.cursor.hyperlink_implicit_id,
    );
    const restored_hyperlink = restored.cursor.hyperlink.?.*;
    try std.testing.expectEqualStrings(
        "cursor-uri",
        restored_hyperlink.uri,
    );
    switch (restored_hyperlink.id) {
        .implicit => |id| try std.testing.expectEqual(
            @as(u32, 0x0a0b0c0d),
            id,
        ),
        .explicit => try std.testing.expect(false),
    }

    const restored_saved = restored.saved_cursor.?;
    try std.testing.expectEqual(@as(u16, 0x0102), restored_saved.x);
    try std.testing.expectEqual(@as(u16, 0x0304), restored_saved.y);
    try std.testing.expect(restored_saved.protected);
    try std.testing.expect(restored_saved.pending_wrap);
    try std.testing.expect(restored_saved.origin);
    try std.testing.expectEqual(
        terminal_charsets.Charset.ascii,
        restored.charset.charsets.get(.G1),
    );
    try std.testing.expectEqual(
        terminal_ansi.ProtectedMode.dec,
        restored.protected_mode,
    );
    try std.testing.expectEqual(@as(u8, 7), restored.kitty_keyboard.idx);
    try std.testing.expect(restored.semantic_prompt.seen);
    try std.testing.expectEqual(
        TerminalScreen.SemanticPrompt.SemanticClick{
            .cl = .smart_vertical,
        },
        restored.semantic_prompt.click,
    );

    // Restored page-local cursor IDs are immediately usable by normal writes.
    try restored.testWriteString("Z");
    const written = restored.pages.getCell(.{ .active = .{
        .x = 0,
        .y = 7,
    } }).?;
    try std.testing.expectEqual(@as(u21, 'Z'), written.cell.codepoint());
    try std.testing.expectEqual(
        restored.cursor.style_id,
        written.cell.style_id,
    );
    try std.testing.expectEqual(
        restored.cursor.hyperlink_id,
        written.node.page().lookupHyperlink(written.cell).?,
    );
    try std.testing.expectEqual(
        terminal_page.Cell.SemanticContent.prompt,
        written.cell.semantic_content,
    );
    try std.testing.expectError(error.EndOfStream, restore_source.takeByte());
}

test "SCREEN encodes the minimal complete-page active suffix" {
    var probe = try TerminalScreen.init(
        std.testing.io,
        std.testing.allocator,
        .{ .cols = 80, .rows = 1, .max_scrollback_bytes = 0 },
    );
    const page_rows = probe.pages.getTopLeft(.screen).node.capacity().rows;
    probe.deinit();
    const screen_rows = page_rows + 1;

    var screen = try TerminalScreen.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .cols = 80,
            .rows = screen_rows,
            .max_scrollback_bytes = null,
        },
    );
    defer screen.deinit();

    // Create one complete historical page followed by a mixed page whose
    // first row is history and whose remaining rows begin the active area.
    screen.cursorAbsolute(0, screen_rows - 1);
    for (0..screen_rows) |_| try screen.testWriteString("\n");
    try std.testing.expectEqual(@as(usize, 3), screen.pages.totalPages());

    const active_top = screen.pages.getTopLeft(.active);
    const historical = screen.pages.getTopLeft(.screen).node;
    const mixed = historical.next.?;
    const newest = mixed.next.?;
    try std.testing.expectEqual(mixed, active_top.node);
    try std.testing.expectEqual(@as(u16, 1), active_top.y);
    try std.testing.expectEqual(null, newest.next);

    // Mark each native page so the encoded sequence proves both omission and
    // oldest-to-newest ordering. The mixed page's marker is in its incidental
    // history prefix and must survive because complete pages are encoded.
    historical.page().getRowAndCell(0, 0).cell.* = .init('A');
    mixed.page().getRowAndCell(0, 0).cell.* = .init('B');
    newest.page().getRowAndCell(0, 0).cell.* = .init('C');

    var destination: std.Io.Writer.Allocating = .init(
        std.testing.allocator,
    );
    defer destination.deinit();
    try encode(&screen, .primary, &destination);

    var source: std.Io.Reader = .fixed(destination.written());
    var screen_record: record.Reader = undefined;
    try screen_record.init(&source);
    try std.testing.expectEqual(record.Tag.screen, screen_record.header.tag);

    const payload_reader = screen_record.payloadReader();
    const header = try Header.decode(payload_reader);
    try std.testing.expectEqual(TerminalScreenKey.primary, header.key);
    try std.testing.expectEqual(@as(u16, 2), header.page_count);
    try std.testing.expect(!header.saved_cursor_present);
    try std.testing.expectEqual(
        null,
        try decodeCursorHyperlink(payload_reader, std.testing.allocator),
    );
    try screen_record.finish();

    var decoded_mixed = try page.decode(&source, std.testing.allocator);
    defer decoded_mixed.deinit();
    try std.testing.expectEqual(
        @as(u21, 'B'),
        decoded_mixed.getRowAndCell(0, 0).cell.codepoint(),
    );

    var decoded_newest = try page.decode(&source, std.testing.allocator);
    defer decoded_newest.deinit();
    try std.testing.expectEqual(
        @as(u21, 'C'),
        decoded_newest.getRowAndCell(0, 0).cell.codepoint(),
    );
    try std.testing.expectError(error.EndOfStream, source.takeByte());

    // Native restoration keeps the incidental history prefix and positions
    // the active top within the first decoded page.
    var restore_source: std.Io.Reader = .fixed(destination.written());
    var decoded = try decode(
        &restore_source,
        std.testing.io,
        std.testing.allocator,
        .{
            .cols = 80,
            .rows = screen_rows,
            .max_scrollback_bytes = null,
        },
    );
    defer decoded.deinit();
    try std.testing.expectEqual(TerminalScreenKey.primary, decoded.key);
    const restored = &decoded.screen;

    try std.testing.expectEqual(@as(usize, 2), restored.pages.totalPages());
    const restored_top = restored.pages.getTopLeft(.active);
    try std.testing.expectEqual(@as(u16, 1), restored_top.y);
    try std.testing.expectEqual(
        @as(u21, 'B'),
        restored.pages.getTopLeft(.screen).node
            .page().getRowAndCell(0, 0).cell.codepoint(),
    );
    try std.testing.expectEqual(
        @as(u21, 'C'),
        restored.pages.getTopLeft(.screen).node.next.?
            .page().getRowAndCell(0, 0).cell.codepoint(),
    );

    // The restored PageList resumes ordinary scrolling and row growth.
    try restored.testWriteString("\n");
    restored.pages.assertIntegrity();
    restored.assertIntegrity();
    try std.testing.expectError(error.EndOfStream, restore_source.takeByte());
}

test "SCREEN restoration rejects invalid and incomplete sequences" {
    var screen = try TerminalScreen.init(
        std.testing.io,
        std.testing.allocator,
        .{ .cols = 2, .rows = 2, .max_scrollback_bytes = 0 },
    );
    defer screen.deinit();

    var destination: std.Io.Writer.Allocating = .init(
        std.testing.allocator,
    );
    defer destination.deinit();
    try encode(&screen, .primary, &destination);

    // Every truncation must fail without leaking a partially restored
    // PageList, cursor pin, or cursor-owned state.
    for (0..destination.written().len) |fixture_len| {
        var source: std.Io.Reader = .fixed(
            destination.written()[0..fixture_len],
        );
        var restored = decode(
            &source,
            std.testing.io,
            std.testing.allocator,
            .{ .cols = 2, .rows = 2, .max_scrollback_bytes = 0 },
        ) catch continue;
        restored.deinit();
        try std.testing.expect(false);
    }

    // Native PageList construction is transactional on allocation failure.
    {
        var failing = std.testing.FailingAllocator.init(
            std.testing.allocator,
            .{ .fail_index = 0 },
        );
        var source: std.Io.Reader = .fixed(destination.written());
        try std.testing.expectError(
            error.OutOfMemory,
            decode(
                &source,
                std.testing.io,
                failing.allocator(),
                .{ .cols = 2, .rows = 2, .max_scrollback_bytes = 0 },
            ),
        );
    }

    // A syntactically valid SCREEN cannot declare an empty PAGE sequence.
    var empty_sequence: std.Io.Writer.Allocating = .init(
        std.testing.allocator,
    );
    defer empty_sequence.deinit();
    {
        var record_writer = try record.Writer.init(
            &empty_sequence,
            .screen,
        );
        try Header.init(&screen, .primary, 0).encode(
            record_writer.payloadWriter(),
        );
        try record_writer.payloadWriter().writeByte(0);
        try record_writer.finish();
    }
    var empty_source: std.Io.Reader = .fixed(empty_sequence.written());
    try std.testing.expectError(
        error.InvalidPageCount,
        decode(
            &empty_source,
            std.testing.io,
            std.testing.allocator,
            .{ .cols = 2, .rows = 2, .max_scrollback_bytes = 0 },
        ),
    );
}

test "SCREEN sequence failure preserves preceding bytes" {
    var screen = try TerminalScreen.init(
        std.testing.io,
        std.testing.allocator,
        .{ .cols = 2, .rows = 2, .max_scrollback_bytes = 0 },
    );
    defer screen.deinit();

    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{},
    );
    var destination = try std.Io.Writer.Allocating.initCapacity(
        failing.allocator(),
        6 + record.Header.len + Header.len + 1,
    );
    defer destination.deinit();
    try destination.writer.writeAll("prefix");

    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(
        error.WriteFailed,
        encode(&screen, .primary, &destination),
    );
    try std.testing.expectEqualStrings("prefix", destination.written());
}

test "SCREEN decode rejects an empty cursor hyperlink URI" {
    var destination: std.Io.Writer.Allocating = .init(
        std.testing.allocator,
    );
    defer destination.deinit();

    var header = testHeader();
    header.key = .primary;
    header.page_count = 1;
    header.cursor_x = 0;
    header.cursor_y = 0;
    header.cursor_flags.pending_wrap = false;
    header.saved_cursor_present = false;

    var record_writer = try record.Writer.init(&destination, .screen);
    try header.encode(record_writer.payloadWriter());
    try hyperlink.encode(.{
        .id = .{ .implicit = 1 },
        .uri = "",
    }, record_writer.payloadWriter());
    try record_writer.finish();

    var source: std.Io.Reader = .fixed(destination.written());
    try std.testing.expectError(
        error.InvalidUri,
        decode(
            &source,
            std.testing.io,
            std.testing.allocator,
            .{ .cols = 1, .rows = 1 },
        ),
    );
}

test "SCREEN decode ignores a PAGE with an empty hyperlink URI" {
    var destination: std.Io.Writer.Allocating = .init(
        std.testing.allocator,
    );
    defer destination.deinit();

    var header = testHeader();
    header.key = .primary;
    header.page_count = 1;
    header.cursor_x = 0;
    header.cursor_y = 0;
    header.cursor_flags.pending_wrap = false;
    header.saved_cursor_present = false;

    var screen_writer = try record.Writer.init(&destination, .screen);
    try header.encode(screen_writer.payloadWriter());
    try screen_writer.payloadWriter().writeByte(0);
    try screen_writer.finish();

    const page_header: page.Header = .{
        .columns = 1,
        .rows = 1,
        .style_count = 0,
        .hyperlink_count = 1,
        .style_capacity = 16,
        .hyperlink_capacity_bytes = 512,
        .grapheme_capacity_bytes = 0,
        .string_capacity_bytes = 0,
    };
    var page_writer = try record.Writer.init(&destination, .page);
    try page_header.encode(page_writer.payloadWriter());
    try io.writeInt(
        page_writer.payloadWriter(),
        terminal_hyperlink.Id,
        1,
    );
    try hyperlink.encode(.{
        .id = .{ .implicit = 1 },
        .uri = "",
    }, page_writer.payloadWriter());

    // One narrow codepoint cell refers to the hyperlink table entry above.
    // Since that entry is ignored, the cell must restore without a hyperlink.
    try page_writer.payloadWriter().writeByte(0);
    try page_writer.payloadWriter().writeAll(&.{ 0, 0, 0, 0 });
    try io.writeInt(
        page_writer.payloadWriter(),
        terminal_style.Id,
        0,
    );
    try io.writeInt(
        page_writer.payloadWriter(),
        terminal_hyperlink.Id,
        1,
    );
    try io.writeInt(page_writer.payloadWriter(), u32, 'A');
    try io.writeInt(page_writer.payloadWriter(), u32, 0);
    try page_writer.finish();

    var source: std.Io.Reader = .fixed(destination.written());
    var decoded = try decode(
        &source,
        std.testing.io,
        std.testing.allocator,
        .{ .cols = 1, .rows = 1 },
    );
    defer decoded.deinit();

    try std.testing.expectEqual(
        @as(u21, 'A'),
        decoded.screen.cursor.page_cell.codepoint(),
    );
    try std.testing.expect(!decoded.screen.cursor.page_cell.hyperlink);

    // Resizing copies the restored cells into a wider page. The ignored
    // hyperlink must not leave a zero-length PageEntry to duplicate later.
    try decoded.screen.resize(.{ .cols = 2, .rows = 1 });
    try std.testing.expect(!decoded.screen.cursor.page_cell.hyperlink);
}
