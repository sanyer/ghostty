//! HISTORY record payload encoding.
//!
//! One HISTORY record describes the complete history for a previously encoded
//! screen. It is followed immediately by the number of complete PAGE records
//! declared by `page_count`. Those pages contain the history older than the
//! first page in the corresponding SCREEN sequence and are ordered from newest
//! to oldest.
//!
//! Every encoded SCREEN has one corresponding HISTORY record. A screen with no
//! history uses zero for all three count fields and has no following PAGE
//! records.
//!
//! The first SCREEN page may begin above the active area. Those incidental
//! history rows are counted by `screen_overlap_rows`; they are not repeated
//! after HISTORY. `total_rows` is the canonical number of logical rows before
//! the active area, including both the SCREEN overlap and the rows in the
//! following PAGE records. Decoders derive native row totals from the restored
//! pages and may ignore inconsistent row metadata.
//!
//! All integers are unsigned and little-endian.
//!
//! ## Binary Format
//!
//! A HISTORY record is followed immediately by its declared PAGE records:
//!
//! ```text
//! +----------------------+
//! | HISTORY record       |
//! +----------------------+
//! | PAGE record 0        | newest
//! +----------------------+
//! | ...                  |
//! +----------------------+
//! | PAGE record (n - 1)  | oldest
//! +----------------------+
//!
//! n = page_count
//! ```
//!
//! Newest-to-oldest order lets a reader start showing most-recent
//! history as soon as possible which is more useful to a user.
//!
//! The PAGE sequence may be empty when all history is already included in the
//! first SCREEN page or when the screen has no history.
//!
//! ### Header
//!
//! The HISTORY payload consists only of this fixed header:
//!
//! ```text
//!  0 +--------------------------------+
//!    | Screen key (u16)               |
//!  2 +--------------------------------+
//!    | Following page count (u32)     |
//!  6 +--------------------------------+
//!    | Total logical history rows     |
//!    | u64                            |
//! 14 +--------------------------------+
//!    | SCREEN overlap rows (u16)      |
//! 16 +--------------------------------+
//! ```
//!
//! A canonical encoder sets `total_rows` to the sum of `screen_overlap_rows`
//! and the logical row counts of all following PAGE records. A decoder uses
//! `page_count`, rather than another record tag, to find the end of the page
//! sequence.

const std = @import("std");
const Allocator = std.mem.Allocator;
const test_fixture = @import("fixture.zig");
const io = @import("io.zig");
const page = @import("page.zig");
const record = @import("record.zig");
const screen = @import("screen.zig");
const TerminalPage = @import("../page.zig").Page;
const TerminalPageList = @import("../PageList.zig");
const TerminalScreen = @import("../Screen.zig");
const TerminalScreenKey = @import("../ScreenSet.zig").Key;

/// The complete fixed payload of one HISTORY record.
pub const Header = struct {
    /// Number of encoded bytes in the fixed payload, calculated by its encoder.
    pub const len = computeLen();

    comptime {
        // This size is part of the wire format. If it changes, the snapshot
        // version must also change.
        std.debug.assert(len == 16);
    }

    /// Identifies the previously encoded screen that owns this history.
    key: TerminalScreenKey,

    /// Number of complete PAGE records immediately following this record.
    page_count: u32,

    /// Canonical number of logical rows before the active area.
    total_rows: u64,

    /// History rows already included at the start of the first SCREEN page.
    screen_overlap_rows: u16,

    /// Encode the fixed HISTORY payload.
    pub fn encode(
        self: Header,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try io.writeInt(writer, u16, @intCast(@intFromEnum(self.key)));
        try io.writeInt(writer, u32, self.page_count);
        try io.writeInt(writer, u64, self.total_rows);
        try io.writeInt(writer, u16, self.screen_overlap_rows);
    }

    pub const DecodeError = std.Io.Reader.Error || error{InvalidKey};

    /// Decode and validate the fixed HISTORY payload.
    pub fn decode(reader: *std.Io.Reader) Header.DecodeError!Header {
        const raw = try io.readInt(reader, u16);
        const Tag = @typeInfo(TerminalScreenKey).@"enum".tag_type;
        const value = std.math.cast(Tag, raw) orelse
            return error.InvalidKey;
        const key = std.enums.fromInt(
            TerminalScreenKey,
            value,
        ) orelse return error.InvalidKey;
        return .{
            .key = key,
            .page_count = try io.readInt(reader, u32),
            .total_rows = try io.readInt(reader, u64),
            .screen_overlap_rows = try io.readInt(reader, u16),
        };
    }

    fn computeLen() usize {
        comptime {
            var buf: [128]u8 = undefined;
            var writer: std.Io.Writer = .fixed(&buf);
            const value: Header = .{
                .key = .primary,
                .page_count = 0,
                .total_rows = 0,
                .screen_overlap_rows = 0,
            };
            value.encode(&writer) catch unreachable;
            return writer.end;
        }
    }
};

/// Errors possible while encoding one HISTORY and its complete PAGE sequence.
pub const EncodeError = Allocator.Error ||
    page.EncodeError ||
    record.Writer.FinishError ||
    error{
        /// The complete historical prefix has more pages than the header fits.
        PageCountOverflow,

        /// The complete historical prefix has more rows than the header fits.
        RowCountOverflow,
    };

/// Encode one screen's HISTORY and its complete historical pages.
///
/// Pages are encoded newest-to-oldest. Compressed source pages are inspected
/// without changing their storage state. On failure, the entire sequence is
/// removed while earlier destination bytes remain.
pub fn encode(
    terminal_screen: *const TerminalScreen,
    key: TerminalScreenKey,
    destination: *std.Io.Writer.Allocating,
) EncodeError!void {
    const sequence_start = destination.written().len;
    errdefer destination.shrinkRetainingCapacity(sequence_start);

    // SCREEN begins at the page containing the active area's first row. Its
    // leading rows are already resident; every previous complete page belongs
    // to this HISTORY sequence.
    const active_top = terminal_screen.pages.getTopLeft(.active);
    const page_count: usize, const total_rows: u64 = count: {
        var page_count: usize = 0;
        var total_rows: u64 = active_top.y;
        var node = active_top.node.prev;
        while (node) |current| : (node = current.prev) {
            page_count += 1;
            total_rows = std.math.add(
                u64,
                total_rows,
                current.rows(),
            ) catch return error.RowCountOverflow;
        }

        break :count .{ page_count, total_rows };
    };

    const header: Header = .{
        .key = key,
        .page_count = std.math.cast(
            u32,
            page_count,
        ) orelse return error.PageCountOverflow,
        .total_rows = total_rows,
        .screen_overlap_rows = active_top.y,
    };

    // HISTORY declares exactly how many PAGE records follow and how their rows
    // combine with the overlap already carried by SCREEN.
    {
        var record_writer = try record.Writer.init(destination, .history);
        errdefer record_writer.cancel();
        try header.encode(record_writer.payloadWriter());
        try record_writer.finish();
    }

    // Walk backward so each page can be prepended by the decoder immediately.
    // PreservedPage borrows resident pages and clones compressed pages without
    // changing the source node's representation.
    var node = active_top.node.prev;
    while (node) |current| : (node = current.prev) {
        var preserved = try current.pagePreservingState(terminal_screen.alloc);
        defer preserved.deinit();
        try page.encode(preserved.page(), destination);
    }
}

/// Errors possible while restoring one HISTORY and its PAGE sequence.
pub const DecodeError = Decoder.InitError ||
    Decoder.RestoreError ||
    error{
        /// The HISTORY key does not match the caller-selected screen.
        UnexpectedScreenKey,
    };

/// A decoded HISTORY manifest ready to restore its following PAGE records.
///
/// Keeping manifest decoding separate lets the full snapshot wrapper route a
/// HISTORY sequence by its encoded key before any pages mutate a Screen.
pub const Decoder = struct {
    source: *std.Io.Reader,
    header: Header,

    pub const InitError = Header.DecodeError ||
        record.Reader.InitError ||
        record.Reader.FinishError ||
        error{
            /// The next record is valid but is not a HISTORY.
            UnexpectedRecordTag,
        };

    pub const RestoreError = Allocator.Error ||
        page.DecodeError ||
        TerminalPageList.PageAllocation.FinalizeError ||
        error{
            /// The Screen already contains complete pages before its active page.
            ExistingHistory,
        };

    /// Decode and finish the self-contained HISTORY manifest.
    pub fn init(self: *Decoder, source: *std.Io.Reader) InitError!void {
        var record_reader: record.Reader = undefined;
        try record_reader.init(source);
        if (record_reader.header.tag != .history) {
            return error.UnexpectedRecordTag;
        }
        const header = try Header.decode(record_reader.payloadReader());
        try record_reader.finish();
        self.* = .{ .source = source, .header = header };
    }

    /// Restore the declared PAGE records into the selected native Screen.
    pub fn decode(
        self: *Decoder,
        alloc: Allocator,
        terminal_screen: *TerminalScreen,
    ) RestoreError!void {
        // A freshly restored SCREEN may carry overlap inside its first page,
        // but cannot already contain a complete historical page before that
        // boundary.
        const active_top = terminal_screen.pages.getTopLeft(.active);
        if (terminal_screen.pages.getTopLeft(.screen).node != active_top.node) {
            return error.ExistingHistory;
        }

        // Row metadata is redundant with the restored SCREEN and PAGE
        // topology. Consume the declared PAGE records, but derive all native
        // row totals from their actual dimensions.
        for (0..self.header.page_count) |_| {
            // PAGE exposes its exact capacity before decoding the payload,
            // allowing the destination PageList to allocate the final backing
            // memory once.
            var decoder: page.Decoder = undefined;
            try decoder.init(self.source);
            var allocation = try terminal_screen.pages.allocatePage(
                decoder.capacity(),
            );
            defer allocation.deinit();
            try decoder.decode(allocation.page(), alloc);

            const contains_prompt = hasSemanticPrompt(allocation.page());
            try allocation.finalize(.prepend);
            if (contains_prompt) terminal_screen.semantic_prompt.seen = true;
        }

        terminal_screen.pages.assertIntegrity();
        terminal_screen.assertIntegrity();
    }
};

/// Restore one HISTORY and its declared PAGE records into a native Screen.
///
/// Each PAGE is decoded directly into a detached PageList-pooled allocation and
/// prepended only after its record and native integrity are validated. If a
/// later PAGE fails, earlier successful pages remain as a contiguous recent
/// history prefix.
pub fn decode(
    source: *std.Io.Reader,
    alloc: Allocator,
    expected_key: TerminalScreenKey,
    terminal_screen: *TerminalScreen,
) DecodeError!void {
    var decoder: Decoder = undefined;
    try decoder.init(source);
    if (decoder.header.key != expected_key) return error.UnexpectedScreenKey;
    try decoder.decode(alloc, terminal_screen);
}

fn hasSemanticPrompt(terminal_page: *const TerminalPage) bool {
    const rows = terminal_page.rows.ptr(terminal_page.memory)[0..terminal_page.size.rows];
    for (rows) |row| {
        if (row.semantic_prompt != .none) return true;

        const cells = row.cells.ptr(
            terminal_page.memory,
        )[0..terminal_page.size.cols];
        for (cells) |cell| {
            if (cell.semantic_content == .prompt) return true;
        }
    }
    return false;
}

const test_header_fixture = test_fixture.parse(@embedFile("testdata/history-header-v1.hex"));

test "HISTORY header golden encoding and decoding" {
    const expected: Header = .{
        .key = .alternate,
        .page_count = 0x01020304,
        .total_rows = 0x0102030405060708,
        .screen_overlap_rows = 0x090a,
    };
    var encoded: [Header.len]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&encoded);
    try expected.encode(&writer);
    try test_fixture.expectEqual(
        .bytes,
        "src/terminal/snapshot/testdata/history-header-v1.hex",
        "snapshot_fixture-history-header-v1.hex",
        &test_header_fixture,
        writer.buffered(),
    );
    try std.testing.expectEqual(Header.len, test_header_fixture.len);

    var reader: std.Io.Reader = .fixed(&test_header_fixture);
    try std.testing.expectEqualDeep(expected, try Header.decode(&reader));
    for (0..Header.len) |fixture_len| {
        var truncated: std.Io.Reader = .fixed(
            test_header_fixture[0..fixture_len],
        );
        try std.testing.expectError(
            error.EndOfStream,
            Header.decode(&truncated),
        );
    }

    var invalid_key = test_header_fixture;
    invalid_key[0] = 2;
    var invalid_key_reader: std.Io.Reader = .fixed(&invalid_key);
    try std.testing.expectError(
        error.InvalidKey,
        Header.decode(&invalid_key_reader),
    );
}

test "HISTORY encodes newest first and restores complete history" {
    // Choose an active height which spans two native pages, then grow until
    // exactly two additional complete pages precede the active boundary.
    var probe = try TerminalScreen.init(
        std.testing.io,
        std.testing.allocator,
        .{ .cols = 80, .rows = 1, .max_scrollback_bytes = 0 },
    );
    const page_rows = probe.pages.getTopLeft(.screen).node.capacity().rows;
    probe.deinit();
    const screen_rows = page_rows + 1;

    var source_screen = try TerminalScreen.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .cols = 80,
            .rows = screen_rows,
            .max_scrollback_bytes = null,
        },
    );
    defer source_screen.deinit();
    source_screen.cursorAbsolute(0, screen_rows - 1);
    while (source_screen.pages.totalPages() < 4) {
        try source_screen.testWriteString("\n");
    }

    const active_top = source_screen.pages.getTopLeft(.active);
    const newest_history = active_top.node.prev.?;
    const oldest_history = newest_history.prev.?;
    try std.testing.expectEqual(
        source_screen.pages.getTopLeft(.screen).node,
        oldest_history,
    );
    try std.testing.expectEqual(null, oldest_history.prev);

    // Mark the two complete historical pages so the wire sequence and final
    // native order are visible. The oldest prompt also verifies derived state
    // is updated only when that page is restored.
    oldest_history.page().getRowAndCell(0, 0).cell.* = .init('A');
    oldest_history.page().getRowAndCell(
        0,
        0,
    ).cell.semantic_content = .prompt;
    newest_history.page().getRowAndCell(0, 0).cell.* = .init('B');

    // Encode SCREEN before history compression, then compress eligible history
    // and require HISTORY encoding to preserve each source storage state.
    var destination: std.Io.Writer.Allocating = .init(
        std.testing.allocator,
    );
    defer destination.deinit();
    try screen.encode(&source_screen, .primary, &destination);
    const history_offset = destination.written().len;

    _ = source_screen.pages.compress(.full);
    const oldest_storage = oldest_history.storage();
    const newest_storage = newest_history.storage();
    try encode(&source_screen, .primary, &destination);
    try std.testing.expectEqual(oldest_storage, oldest_history.storage());
    try std.testing.expectEqual(newest_storage, newest_history.storage());

    // Inspect the manifest and PAGE records independently. Newest history is
    // sent first even though native PageList order is oldest-to-newest.
    var history_source: std.Io.Reader = .fixed(
        destination.written()[history_offset..],
    );
    var history_record: record.Reader = undefined;
    try history_record.init(&history_source);
    try std.testing.expectEqual(record.Tag.history, history_record.header.tag);
    const header = try Header.decode(history_record.payloadReader());
    try history_record.finish();
    try std.testing.expectEqual(TerminalScreenKey.primary, header.key);
    try std.testing.expectEqual(@as(u32, 2), header.page_count);
    try std.testing.expectEqual(
        @as(u16, active_top.y),
        header.screen_overlap_rows,
    );
    try std.testing.expectEqual(
        @as(u64, active_top.y) +
            oldest_history.rows() +
            newest_history.rows(),
        header.total_rows,
    );

    var decoded_newest = try page.decode(
        &history_source,
        std.testing.allocator,
    );
    defer decoded_newest.deinit();
    try std.testing.expectEqual(
        @as(u21, 'B'),
        decoded_newest.getRowAndCell(0, 0).cell.codepoint(),
    );
    var decoded_oldest = try page.decode(
        &history_source,
        std.testing.allocator,
    );
    defer decoded_oldest.deinit();
    try std.testing.expectEqual(
        @as(u21, 'A'),
        decoded_oldest.getRowAndCell(0, 0).cell.codepoint(),
    );
    try std.testing.expectError(error.EndOfStream, history_source.takeByte());

    // Restore SCREEN first, then prepend HISTORY directly into that PageList.
    var restore_source: std.Io.Reader = .fixed(destination.written());
    var decoded_screen = try screen.decode(
        &restore_source,
        std.testing.io,
        std.testing.allocator,
        .{
            .cols = 80,
            .rows = screen_rows,
            .max_scrollback_bytes = null,
        },
    );
    defer decoded_screen.deinit();
    try std.testing.expectEqual(
        TerminalScreenKey.primary,
        decoded_screen.key,
    );
    const restored = &decoded_screen.screen;
    try std.testing.expect(!restored.semantic_prompt.seen);
    try decode(
        &restore_source,
        std.testing.allocator,
        .primary,
        restored,
    );

    try std.testing.expectEqual(
        source_screen.pages.totalPages(),
        restored.pages.totalPages(),
    );
    const restored_oldest = restored.pages.getTopLeft(.screen).node;
    try std.testing.expectEqual(
        @as(u21, 'A'),
        restored_oldest.page().getRowAndCell(0, 0).cell.codepoint(),
    );
    try std.testing.expectEqual(
        @as(u21, 'B'),
        restored_oldest.next.?
            .page().getRowAndCell(0, 0).cell.codepoint(),
    );
    try std.testing.expect(restored.semantic_prompt.seen);
    try std.testing.expectError(error.EndOfStream, restore_source.takeByte());

    // Reuse a writable copy of the sequence for failure-path fixtures.
    const encoded = try std.testing.allocator.dupe(
        u8,
        destination.written(),
    );
    defer std.testing.allocator.free(encoded);
    const first_page_offset = history_offset + record.Header.len + Header.len;
    const first_payload_len = std.mem.readInt(
        u32,
        encoded[first_page_offset + 2 ..][0..4],
        .little,
    );
    const second_page_offset =
        first_page_offset + record.Header.len + first_payload_len;

    // Truncate the first PAGE only after its header has exposed a capacity.
    // Its detached allocation is discarded and the live SCREEN list remains
    // completely unchanged.
    var truncated_source: std.Io.Reader = .fixed(
        encoded[0 .. second_page_offset - 1],
    );
    var decoded_truncated = try screen.decode(
        &truncated_source,
        std.testing.io,
        std.testing.allocator,
        .{
            .cols = 80,
            .rows = screen_rows,
            .max_scrollback_bytes = null,
        },
    );
    defer decoded_truncated.deinit();
    const truncated = &decoded_truncated.screen;
    const truncated_screen_first = truncated.pages.getTopLeft(.screen).node;
    const truncated_screen_page_count = truncated.pages.totalPages();
    try std.testing.expectError(
        error.EndOfStream,
        decode(
            &truncated_source,
            std.testing.allocator,
            .primary,
            truncated,
        ),
    );
    try std.testing.expectEqual(
        truncated_screen_page_count,
        truncated.pages.totalPages(),
    );
    try std.testing.expectEqual(
        truncated_screen_first,
        truncated.pages.getTopLeft(.screen).node,
    );
    truncated.pages.assertIntegrity();
    truncated.assertIntegrity();

    // Corrupt only the older PAGE tag. A failure in a later PAGE keeps only
    // the successfully prepended newer pages, contiguous with SCREEN.
    std.mem.writeInt(
        u16,
        encoded[second_page_offset..][0..2],
        @intFromEnum(record.Tag.screen),
        .little,
    );

    var partial_source: std.Io.Reader = .fixed(encoded);
    var decoded_partial = try screen.decode(
        &partial_source,
        std.testing.io,
        std.testing.allocator,
        .{
            .cols = 80,
            .rows = screen_rows,
            .max_scrollback_bytes = null,
        },
    );
    defer decoded_partial.deinit();
    const partial = &decoded_partial.screen;
    const screen_page_count = partial.pages.totalPages();
    try std.testing.expectError(
        error.UnexpectedRecordTag,
        decode(
            &partial_source,
            std.testing.allocator,
            .primary,
            partial,
        ),
    );
    try std.testing.expectEqual(
        screen_page_count + 1,
        partial.pages.totalPages(),
    );
    try std.testing.expectEqual(
        @as(u21, 'B'),
        partial.pages.getTopLeft(.screen).node
            .page().getRowAndCell(0, 0).cell.codepoint(),
    );
    try std.testing.expect(!partial.semantic_prompt.seen);
    partial.pages.assertIntegrity();
    partial.assertIntegrity();
}

test "HISTORY encodes and restores an empty sequence" {
    var terminal_screen = try TerminalScreen.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .cols = 2,
            .rows = 2,
            .max_scrollback_bytes = null,
        },
    );
    defer terminal_screen.deinit();

    var destination: std.Io.Writer.Allocating = .init(
        std.testing.allocator,
    );
    defer destination.deinit();
    try encode(&terminal_screen, .primary, &destination);

    var inspect_source: std.Io.Reader = .fixed(destination.written());
    var history_record: record.Reader = undefined;
    try history_record.init(&inspect_source);
    const header = try Header.decode(history_record.payloadReader());
    try history_record.finish();
    try std.testing.expectEqual(@as(u32, 0), header.page_count);
    try std.testing.expectEqual(@as(u64, 0), header.total_rows);
    try std.testing.expectEqual(@as(u16, 0), header.screen_overlap_rows);
    try std.testing.expectError(error.EndOfStream, inspect_source.takeByte());

    var decode_source: std.Io.Reader = .fixed(destination.written());
    const initial_first = terminal_screen.pages.getTopLeft(.screen).node;
    try decode(
        &decode_source,
        std.testing.allocator,
        .primary,
        &terminal_screen,
    );
    try std.testing.expectEqual(
        initial_first,
        terminal_screen.pages.getTopLeft(.screen).node,
    );
    try std.testing.expectError(error.EndOfStream, decode_source.takeByte());
}

test "HISTORY accepts row metadata mismatches and rejects structural ones" {
    var terminal_screen = try TerminalScreen.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .cols = 2,
            .rows = 2,
            .max_scrollback_bytes = null,
        },
    );
    defer terminal_screen.deinit();

    // Row counts are redundant metadata. Even internally inconsistent values
    // do not prevent restoring the topology declared by page_count.
    const accepted = [_]Header{
        .{
            .key = .primary,
            .page_count = 0,
            .total_rows = 0,
            .screen_overlap_rows = 1,
        },
        .{
            .key = .primary,
            .page_count = 0,
            .total_rows = std.math.maxInt(u64),
            .screen_overlap_rows = std.math.maxInt(u16),
        },
    };
    for (accepted) |header| {
        var destination: std.Io.Writer.Allocating = .init(
            std.testing.allocator,
        );
        defer destination.deinit();
        var record_writer = try record.Writer.init(&destination, .history);
        try header.encode(record_writer.payloadWriter());
        try record_writer.finish();

        var source: std.Io.Reader = .fixed(destination.written());
        try decode(
            &source,
            std.testing.allocator,
            .primary,
            &terminal_screen,
        );
        try std.testing.expectError(error.EndOfStream, source.takeByte());
        terminal_screen.pages.assertIntegrity();
        terminal_screen.assertIntegrity();
    }

    // Routing and sequence length still determine which native screen is
    // mutated and where the following record begins, so they remain strict.
    const Case = struct {
        header: Header,
        expected: anyerror,
    };
    const cases = [_]Case{
        .{
            .header = .{
                .key = .alternate,
                .page_count = 0,
                .total_rows = 0,
                .screen_overlap_rows = 0,
            },
            .expected = error.UnexpectedScreenKey,
        },
        .{
            .header = .{
                .key = .primary,
                .page_count = 1,
                .total_rows = 1,
                .screen_overlap_rows = 0,
            },
            .expected = error.EndOfStream,
        },
    };
    for (cases) |case| {
        var destination: std.Io.Writer.Allocating = .init(
            std.testing.allocator,
        );
        defer destination.deinit();
        var record_writer = try record.Writer.init(&destination, .history);
        try case.header.encode(record_writer.payloadWriter());
        try record_writer.finish();

        var source: std.Io.Reader = .fixed(destination.written());
        try std.testing.expectError(
            case.expected,
            decode(
                &source,
                std.testing.allocator,
                .primary,
                &terminal_screen,
            ),
        );
        terminal_screen.pages.assertIntegrity();
        terminal_screen.assertIntegrity();
    }
}
