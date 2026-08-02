//! Grid (rows, cells, and grapheme suffixes) encoding.
//!
//! A grid contains the rows and cells of a terminal page. Its dimensions are
//! supplied by the containing record rather than repeated here. The encoder
//! writes exactly `rows` row records followed by one grapheme suffix section.
//!
//! All records are tightly packed with no padding between them. All integers
//! are unsigned and little-endian.
//!
//! The layout is designed so the common case decodes with bulk copies: cells
//! are fixed-size words, trailing default cells are elided per row, and the
//! variable-length grapheme suffixes live outside the row data.
//!
//! ```text
//! +---------------------------+
//! | Row 0                     |
//! +---------------------------+
//! | ...                       |
//! +---------------------------+
//! | Row (rows - 1)            |
//! +---------------------------+
//! | Grapheme suffix section   |
//! +---------------------------+
//! ```
//!
//! ## Row
//!
//! Each row has the following format:
//!
//! | Offset | Size        | Field                     |
//! | -----: | ----------: | :------------------------ |
//! |      0 |           1 | Row flags                 |
//! |      1 |           2 | Encoded cell count (`u16`)|
//! |      3 | 8 * `count` | Encoded cells             |
//!
//! The row flag byte has the following format:
//!
//! | Bits | Field                     |
//! | ---: | :------------------------ |
//! |    0 | Wrap                      |
//! |    1 | Wrap continuation         |
//! |  2-3 | Semantic prompt           |
//! |  4-7 | Reserved, zero            |
//!
//! Semantic prompt values are:
//!
//! | Value | Meaning             |
//! | ----: | :------------------ |
//! |     0 | None                |
//! |     1 | Prompt              |
//! |     2 | Prompt continuation |
//!
//! Value 3 is not emitted in snapshot version 1. Decoders treat it as none.
//!
//! The encoded cell count must not exceed the grid's column count; it is a
//! structural field and decoders reject larger values. Cells at and beyond
//! the count are the default cell: all sixty-four bits zero, meaning an
//! empty narrow codepoint cell with the default style and no hyperlink.
//! Canonical encoders emit exactly through the row's last non-default cell,
//! so a fully default row has a zero count and no cell words.
//!
//! Native row cache flags are not encoded. In particular, the Kitty virtual
//! placeholder hint is derived while decoding cells containing U+10EEEE.
//!
//! ## Cell
//!
//! Each cell is one 64-bit little-endian word:
//!
//! ```text
//!  bit 0 +-------------------------------+
//!        | Content kind                  |
//!        | 2 bits                        |
//!  bit 2 +-------------------------------+
//!        | Content                       |
//!        | 24 bits                       |
//! bit 26 +-------------------------------+
//!        | Style ID                      |
//!        | 16 bits                       |
//! bit 42 +-------------------------------+
//!        | Width kind                    |
//!        | 2 bits                        |
//! bit 44 +-------------------------------+
//!        | Protected                     |
//! bit 45 +-------------------------------+
//!        | Hyperlink flag                |
//! bit 46 +-------------------------------+
//!        | Semantic content              |
//!        | 2 bits                        |
//! bit 48 +-------------------------------+
//!        | Hyperlink ID                  |
//!        | 16 bits                       |
//! bit 64 +-------------------------------+
//! ```
//!
//! Content kinds are:
//!
//! | Value | Meaning                          |
//! | ----: | :------------------------------- |
//! |     0 | Codepoint                        |
//! |     1 | Codepoint with grapheme suffix   |
//! |     2 | Palette background               |
//! |     3 | RGB background                   |
//!
//! The content kind selects the layout of the 24-bit content field. All
//! content bit positions below are relative to the start of the content
//! field, so content bit 0 is cell word bit 2.
//!
//! For codepoint content (kinds 0 and 1), the content field is a Unicode
//! scalar value. Values above U+10FFFF and surrogates decode as U+FFFD.
//! Kind 1 additionally declares that the grapheme suffix section contains
//! one entry for this cell; the cell is otherwise identical to kind 0.
//!
//! ```text
//!  bit 0 +-------------------------------+
//!        | Unicode scalar value          |
//!        | 24 bits                       |
//! bit 24 +-------------------------------+
//! ```
//!
//! For a palette background (kind 2), the low byte is the palette index.
//! The remaining content bits are reserved, canonically zero, and ignored
//! by decoders.
//!
//! ```text
//!  bit 0 +-------------------------------+
//!        | Palette index                 |
//!        | 8 bits                        |
//!  bit 8 +-------------------------------+
//!        | Reserved, zero                |
//!        | 16 bits                       |
//! bit 24 +-------------------------------+
//! ```
//!
//! For an RGB background (kind 3), the content field is one byte per
//! channel:
//!
//! ```text
//!  bit 0 +-------------------------------+
//!        | Red                           |
//!        | 8 bits                        |
//!  bit 8 +-------------------------------+
//!        | Green                         |
//!        | 8 bits                        |
//! bit 16 +-------------------------------+
//!        | Blue                          |
//!        | 8 bits                        |
//! bit 24 +-------------------------------+
//! ```
//!
//! Width kinds are:
//!
//! | Value | Meaning     |
//! | ----: | :---------- |
//! |     0 | Narrow      |
//! |     1 | Wide        |
//! |     2 | Spacer tail |
//! |     3 | Spacer head |
//!
//! Semantic content values are:
//!
//! | Value | Meaning |
//! | ----: | :------ |
//! |     0 | Output  |
//! |     1 | Input   |
//! |     2 | Prompt  |
//!
//! Value 3 is not emitted in snapshot version 1. Decoders treat it as output.
//!
//! Style and hyperlink ID zero mean no style and no hyperlink. Other IDs
//! refer to entries in the containing record's separate style and hyperlink
//! tables. The hyperlink flag is set exactly when the hyperlink ID is
//! nonzero; decoders derive cell linkage from the remapped ID and ignore the
//! flag itself.
//!
//! ## Grapheme suffix section
//!
//! The section begins with an entry count followed by that many entries:
//!
//! | Offset | Size    | Field                |
//! | -----: | ------: | :------------------- |
//! |      0 |       4 | Entry count (`u32`)  |
//! |      4 | varies  | Entries              |
//!
//! Each entry:
//!
//! | Offset | Size        | Field                       |
//! | -----: | ----------: | :-------------------------- |
//! |      0 |           2 | Row (`u16`)                 |
//! |      2 |           2 | Column (`u16`)              |
//! |      4 |           2 | Codepoint count (`u16`)     |
//! |      6 | 4 * `count` | Codepoints (`u32` each)     |
//!
//! Each codepoint is a Unicode scalar; invalid scalars are individually
//! ignored by decoders. Canonical encoders emit exactly one entry, with at
//! least one codepoint, for every kind 1 cell, in ascending row-then-column
//! order. Decoders consume every declared entry and ignore entries whose
//! target is out of range, is not a codepoint cell, has a zero codepoint, or
//! already received an entry. A kind 1 cell that receives no suffix
//! codepoints decodes as a plain codepoint cell.

const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const test_fixture = @import("fixture.zig");
const io = @import("io.zig");
const kitty = @import("../kitty.zig");
const terminal_hyperlink = @import("../hyperlink.zig");
const terminal_page = @import("../page.zig");
const terminal_style = @import("../style.zig");

const TerminalCell = terminal_page.Cell;
const TerminalHyperlinkId = terminal_hyperlink.Id;
const TerminalPage = terminal_page.Page;
const TerminalRow = terminal_page.Row;
const TerminalStyleId = terminal_style.Id;

/// The header before every row's encoded cells.
///
/// The semantic prompt is a raw integer for the same reason as the wire
/// cell fields: decoders must accept its reserved value without
/// instantiating an invalid native enum, so every header byte bit-casts to
/// a valid value.
pub const Row = packed struct(u8) {
    wrap: bool = false,
    wrap_continuation: bool = false,
    semantic_prompt: u2 = 0,
    _padding: u4 = 0,
};

/// The wire layout of one encoded cell. This is its own registry: the bit
/// positions and field meanings are part of the snapshot format and are
/// documented above independently of the native cell.
///
/// Enum-like fields are raw integers because decoders must accept reserved
/// values (for example semantic content 3) without instantiating an invalid
/// native enum.
pub const Cell = packed struct(u64) {
    kind: u2 = @intFromEnum(Kind.codepoint),
    content: u24 = 0,
    style_id: u16 = 0,
    width: u2 = 0,
    protected: bool = false,
    hyperlink: bool = false,
    semantic_content: u2 = 0,
    hyperlink_id: u16 = 0,

    /// Determines how `content` is interpreted.
    pub const Kind = enum(u2) {
        codepoint = 0,
        codepoint_grapheme = 1,
        bg_color_palette = 2,
        bg_color_rgb = 3,
    };
};

/// Whether the native cell's in-memory layout matches the wire cell layout
/// bit for bit, with the wire hyperlink ID occupying the native padding.
///
/// The wire format does not require this: it is an optimization. When it
/// holds, whole rows encode and decode as bulk copies. If the native layout
/// ever diverges, the portable field-by-field codec below remains correct
/// and this constant simply becomes false.
const native_matches_wire = native: {
    if (@bitSizeOf(TerminalCell) != 64) break :native false;

    // The bulk copies above are only sound if we can prove the two layouts
    // agree, and we want native cell changes to demote us to the portable
    // codec automatically rather than corrupt snapshots.
    //
    // Instead of pinning every native field offset and enum value w/ assertions
    // that must be maintained by hand, each probe below pairs a native
    // cell with the wire cell that must share its exact bit pattern; both
    // sides bit cast to a word and any difference means some field moved
    // or some enum member was renumbered.
    //
    // Three probes, one per content payload, cover the whole cell.
    const probes = [_]struct {
        native: TerminalCell,
        wire: Cell,
    }{
        .{
            .native = .{
                .content_tag = .codepoint_grapheme,
                .content = .{ .codepoint = .{ .data = 0x10FFFF } },
                .style_id = 0xBEEF,
                .wide = .spacer_tail,
                .protected = true,
                ._padding = 0x1D2C,
            },
            .wire = .{
                .kind = 1,
                .content = 0x10FFFF,
                .style_id = 0xBEEF,
                .width = 2,
                .protected = true,
                // The native padding position, canonical wire or not.
                .hyperlink_id = 0x1D2C,
            },
        },
        .{
            .native = .{
                .content_tag = .bg_color_palette,
                .content = .{ .color_palette = .{ .data = 0xAB } },
                .wide = .spacer_head,
                .hyperlink = true,
                .semantic_content = .input,
            },
            .wire = .{
                .kind = 2,
                .content = 0xAB,
                .width = 3,
                .hyperlink = true,
                .semantic_content = 1,
            },
        },
        .{
            .native = .{
                .content_tag = .bg_color_rgb,
                .content = .{ .color_rgb = .{
                    .r = 0x12,
                    .g = 0x34,
                    .b = 0x56,
                } },
                .wide = .wide,
                .semantic_content = .prompt,
            },
            .wire = .{
                .kind = 3,
                .content = 0x563412,
                .width = 1,
                .semantic_content = 2,
            },
        },
    };
    for (probes) |probe| {
        const native_bits: u64 = @bitCast(probe.native);
        const wire_bits: u64 = @bitCast(probe.wire);
        if (native_bits != wire_bits) break :native false;
    }

    break :native true;
};

/// Whether rows of cells can be copied between native and wire storage
/// without per-cell transformation.
const bulk_codec = native_matches_wire and
    builtin.cpu.arch.endian() == .little;

pub const EncodeError = std.Io.Writer.Error || error{
    /// Wide and spacer cells do not form a valid row.
    InvalidWideCell,

    /// One cell's grapheme suffix exceeds the entry's u16 codepoint count.
    TooManyGraphemes,
};

/// Encode every row, cell, and grapheme suffix directly from a page.
///
/// If an error is returned, partial data may have been written. If you
/// want transactional writing, the caller is responsible for using something
/// like a seekable stream and rolling back.
pub fn encode(
    page: *const TerminalPage,
    writer: *std.Io.Writer,
) EncodeError!void {
    defer page.assertIntegrity();
    for (0..page.size.rows) |y| {
        const row = page.getRow(y);
        const cells = page.getCells(row);

        // Trailing default cells decode implicitly. Wide/spacer pairs and
        // hyperlinked or styled cells are always nonzero, so eliding the
        // zero suffix never drops encoded state.
        const count: usize = count: {
            var i: usize = cells.len;
            while (i > 0) : (i -= 1) {
                if (!cells[i - 1].isZero()) break :count i;
            }
            break :count 0;
        };

        // Row header: flags then the encoded cell count.
        {
            const row_header: Row = .{
                .wrap = row.wrap,
                .wrap_continuation = row.wrap_continuation,
                .semantic_prompt = @intFromEnum(row.semantic_prompt),
            };
            var header_bytes: [3]u8 = undefined;
            header_bytes[0] = @bitCast(row_header);
            std.mem.writeInt(u16, header_bytes[1..3], @intCast(count), .little);
            try writer.writeAll(&header_bytes);
        }

        // Validate the wide state of every encoded cell so we don't encode
        // corrupt data, and detect the cells that keep this row off the
        // direct-copy path. Trailing default cells are narrow, so checking
        // the encoded prefix against the full row width covers every pair.
        var direct = true;
        for (cells[0..count], 0..) |*cell, x| {
            switch (cell.wide) {
                .narrow => {},
                .wide => if (x + 1 == cells.len or
                    cells[x + 1].wide != .spacer_tail)
                {
                    return error.InvalidWideCell;
                },
                .spacer_tail => if (x == 0 or
                    cells[x - 1].wide != .wide)
                {
                    return error.InvalidWideCell;
                },
                .spacer_head => if (x + 1 != cells.len or !row.wrap) {
                    return error.InvalidWideCell;
                },
            }

            // Hyperlink IDs live in a native side table, and nonzero native
            // padding would leak into the wire hyperlink ID field.
            if (cell.hyperlink or cell._padding != 0) direct = false;
        }

        if (comptime bulk_codec) {
            if (direct) {
                try writer.writeAll(std.mem.sliceAsBytes(cells[0..count]));
                continue;
            }
        }

        for (cells[0..count]) |*cell| {
            const link_id: TerminalHyperlinkId = if (cell.hyperlink)
                page.lookupHyperlink(cell) orelse unreachable
            else
                0;
            try io.writeInt(writer, u64, cellBits(cell.*, link_id));
        }
    }

    try encodeGraphemes(page, writer);
}

/// Encode the grapheme suffix section for every kind 1 cell in the grid.
fn encodeGraphemes(
    page: *const TerminalPage,
    writer: *std.Io.Writer,
) EncodeError!void {
    // Count and validate entries before the section header so the count is
    // always exact. Rows without the native grapheme hint contain no
    // grapheme cells in any intact page.
    var entries: u32 = 0;
    for (0..page.size.rows) |y| {
        const row = page.getRow(y);
        if (!row.grapheme) continue;
        for (page.getCells(row)) |*cell| {
            if (!cell.hasGrapheme()) continue;
            const cps = page.lookupGrapheme(cell) orelse unreachable;
            if (cps.len > std.math.maxInt(u16)) return error.TooManyGraphemes;
            entries += 1;
        }
    }

    try io.writeInt(writer, u32, entries);
    if (entries == 0) return;

    for (0..page.size.rows) |y| {
        const row = page.getRow(y);
        if (!row.grapheme) continue;
        for (page.getCells(row), 0..) |*cell, x| {
            if (!cell.hasGrapheme()) continue;
            const cps = page.lookupGrapheme(cell) orelse unreachable;
            try io.writeInt(writer, u16, @intCast(y));
            try io.writeInt(writer, u16, @intCast(x));
            try io.writeInt(writer, u16, @intCast(cps.len));
            for (cps) |cp| try io.writeInt(writer, u32, cp);
        }
    }
}

pub const DecodeError = std.Io.Reader.Error || error{
    /// A row declares more encoded cells than the grid has columns.
    InvalidRowCellCount,
};

/// Maps encoded style table IDs to page-assigned style IDs.
pub const StyleRemap = Remap(TerminalStyleId);

/// Maps encoded hyperlink table IDs to page-assigned hyperlink IDs.
pub const HyperlinkRemap = Remap(TerminalHyperlinkId);

/// Decode every row, cell, and grapheme suffix directly into an
/// initialized, empty page.
///
/// The grid does not encode dimensions, so `page` must already have the
/// exact row and column count expected by the containing record. Capacity
/// hints are advisory. Graphemes and cell hyperlink references that do not
/// fit are discarded without affecting the rest of the grid.
///
/// Style and hyperlink table entries must be inserted into `page` before
/// calling this function, with their encoded and page-assigned IDs recorded
/// in `style_remap` and `hyperlink_remap`. ID zero always means the default
/// style or no hyperlink. A nonzero ID missing from its remap is also
/// treated as zero so unknown table references do not prevent the rest of
/// the grid from decoding.
///
/// Invalid semantic data is normalized into a degraded form while
/// preserving the declared byte boundaries. Unknown semantic values use
/// their neutral variants, invalid Unicode becomes U+FFFD, invalid optional
/// data is ignored, and malformed wide-cell relationships become narrow
/// cells. The encoded cell count is the only structural field.
pub fn decode(
    page: *TerminalPage,
    reader: *std.Io.Reader,
    style_remap: *const StyleRemap,
    hyperlink_remap: *const HyperlinkRemap,
) DecodeError!void {
    for (0..page.size.rows) |y| {
        // Read the row header and cell count.
        const row_header: Row, const count: u16 = header: {
            // The staged payload path has every header buffered.
            var row_header_bytes: [3]u8 = undefined;
            if (reader.bufferedLen() >= 3) {
                row_header_bytes = reader.buffered()[0..3].*;
                reader.toss(3);
            } else {
                try reader.readSliceAll(&row_header_bytes);
            }

            // Every bit pattern is a valid header: booleans decode directly
            // and the raw semantic value gets a default below. Reserved
            // bits do not change the known fields.
            const row_header: Row = @bitCast(row_header_bytes[0]);
            const count = std.mem.readInt(u16, row_header_bytes[1..3], .little);
            break :header .{ row_header, count };
        };

        const row = page.getRow(y);
        row.wrap = row_header.wrap;
        row.wrap_continuation = row_header.wrap_continuation;
        row.semantic_prompt = std.enums.fromInt(
            TerminalRow.SemanticPrompt,
            row_header.semantic_prompt,
        ) orelse .none;

        const cells = page.getCells(row);
        if (count > cells.len) return error.InvalidRowCellCount;
        if (count == 0) continue;

        if (comptime bulk_codec) {
            // Read the encoded words directly into page storage, then
            // normalize them in place. The raw words are only ever touched
            // as integers until normalization makes them valid cells.
            const words: [*]u64 = @ptrCast(cells.ptr);
            try reader.readSliceAll(
                std.mem.sliceAsBytes(cells[0..count]),
            );
            for (0..count) |x| {
                applyCell(
                    page,
                    row,
                    cells,
                    x,
                    words[x],
                    style_remap,
                    hyperlink_remap,
                );
            }
        } else {
            for (0..count) |x| {
                const bits = try io.readInt(reader, u64);
                applyCell(
                    page,
                    row,
                    cells,
                    x,
                    bits,
                    style_remap,
                    hyperlink_remap,
                );
            }
        }

        // The implicit cell after a short row is narrow, which resolves a
        // trailing wide marker exactly like an explicit narrow neighbor.
        if (count < cells.len and cells[count - 1].wide == .wide) {
            cells[count - 1].wide = .narrow;
        }
    }

    try decodeGraphemes(page, reader);
}

/// Normalize one encoded cell word and store it at `cells[x]`.
///
/// This owns every per-cell decode rule except grapheme suffixes: content
/// validation, reserved-value degradation, style and hyperlink remapping
/// with reference counting, and wide-pair normalization against already
/// decoded neighbors.
fn applyCell(
    page: *TerminalPage,
    row: *TerminalRow,
    cells: []TerminalCell,
    x: usize,
    bits_wire: u64,
    style_remap: *const StyleRemap,
    hyperlink_remap: *const HyperlinkRemap,
) void {
    const cell = &cells[x];

    // The default cell is the common case and needs no normalization,
    // reference counting, or table lookups.
    if (bits_wire == 0) {
        storeCell(cell, 0);
        normalizeWide(row, cells, x);
        return;
    }

    // Any word is a valid wire cell because its fields are raw integers,
    // so all normalization below is plain field access.
    var wire: Cell = @bitCast(bits_wire);

    // Hyperlink linkage is derived from the remapped ID below. The stored
    // native cell starts unlinked either way.
    const link_encoded = wire.hyperlink_id;
    wire.hyperlink_id = 0;
    wire.hyperlink = false;

    switch (@as(Cell.Kind, @enumFromInt(wire.kind))) {
        // Kind 1 differs from 0 only by declaring a grapheme suffix section
        // entry, which reattaches through the native grapheme APIs later.
        .codepoint, .codepoint_grapheme => {
            wire.kind = @intFromEnum(Cell.Kind.codepoint);
            if (!validScalar(wire.content)) wire.content = 0xFFFD;

            // Kitty image and placement state is not part of this snapshot
            // version, but the placeholder is still a valid Unicode scalar.
            // Preserve it and derive the native row hint so later row
            // operations remain correct.
            if (wire.content == kitty.graphics.unicode.placeholder) {
                row.kitty_virtual_placeholder = true;
            }
        },

        // Only the palette index is meaningful; the remaining content bits
        // are reserved and must not obscure it.
        .bg_color_palette => wire.content = @as(u8, @truncate(wire.content)),

        .bg_color_rgb => {},
    }

    // Reserved semantic content degrades to plain output.
    wire.semantic_content = @intFromEnum(std.enums.fromInt(
        TerminalCell.SemanticContent,
        wire.semantic_content,
    ) orelse .output);

    // IDs belong to the encoded page. Translate them to IDs assigned by the
    // destination page before storing them on cells. The table owns one
    // reference and each decoded cell owns one additional reference.
    if (wire.style_id != 0) {
        wire.style_id = style_remap.get(wire.style_id);
        if (wire.style_id != 0) {
            page.styles.use(page.memory, wire.style_id);
            row.styled = true;
        }
    }

    storeCell(cell, @bitCast(wire));

    if (link_encoded != 0) link: {
        const link_native = hyperlink_remap.get(link_encoded);
        if (link_native == 0) break :link;

        // setHyperlink records the cell mapping but intentionally does not
        // increment the set's reference count. If its map is full, undo our
        // reference and leave this cell unlinked.
        page.hyperlink_set.use(page.memory, link_native);
        page.setHyperlink(row, cell, link_native) catch {
            page.hyperlink_set.release(page.memory, link_native);
        };
    }

    normalizeWide(row, cells, x);
}

/// Resolve wide-pair relationships for the cell at `x` against its already
/// normalized predecessors.
fn normalizeWide(row: *const TerminalRow, cells: []TerminalCell, x: usize) void {
    // A following cell resolves whether the previous wide marker owns a
    // tail. Normalize the current marker immediately when possible,
    // including a wide marker at the row end.
    if (x > 0 and
        cells[x - 1].wide == .wide and
        cells[x].wide != .spacer_tail)
    {
        cells[x - 1].wide = .narrow;
    }
    switch (cells[x].wide) {
        .narrow => {},

        // A non-final wide marker remains pending until the next cell.
        .wide => if (x + 1 == cells.len) {
            cells[x].wide = .narrow;
        },

        .spacer_tail => if (x == 0 or
            cells[x - 1].wide != .wide)
        {
            cells[x].wide = .narrow;
        },

        .spacer_head => if (x + 1 != cells.len or !row.wrap) {
            cells[x].wide = .narrow;
        },
    }
}

/// Whether the value is a valid Unicode scalar value.
inline fn validScalar(cp: u32) bool {
    return cp <= 0x10FFFF and (cp < 0xD800 or cp > 0xDFFF);
}

/// Decode the grapheme suffix section into already decoded cells.
fn decodeGraphemes(
    page: *TerminalPage,
    reader: *std.Io.Reader,
) DecodeError!void {
    const entries = try io.readInt(reader, u32);
    for (0..entries) |_| {
        const y = try io.readInt(reader, u16);
        const x = try io.readInt(reader, u16);
        const cp_count = try io.readInt(reader, u16);

        // Resolve the target cell. Entries whose target cannot carry a
        // suffix are optional detail: their codepoints are consumed to
        // preserve framing and then dropped.
        const target: ?struct {
            row: *TerminalRow,
            cell: *TerminalCell,
        } = target: {
            if (y >= page.size.rows or x >= page.size.cols) {
                break :target null;
            }
            const row = page.getRow(y);
            const cell = &page.getCells(row)[x];

            // Cell decoding stores every kind 1 cell as a plain codepoint,
            // so this also gives duplicate entries first-wins semantics.
            if (cell.content_tag != .codepoint) break :target null;
            if (cell.content.codepoint.data == 0) break :target null;
            break :target .{ .row = row, .cell = cell };
        };

        // Always consume every declared codepoint. Invalid scalars and
        // suffixes that exceed the native capacity are dropped
        // independently without affecting the rest of the grid.
        var accept = target != null;
        for (0..cp_count) |_| {
            const cp = try io.readInt(reader, u32);
            if (!accept) continue;
            if (!validScalar(cp)) continue;

            page.appendGrapheme(
                target.?.row,
                target.?.cell,
                @intCast(cp),
            ) catch {
                accept = false;
            };
        }
    }
}

/// The encoded word for one native cell and its hyperlink ID.
fn cellBits(cell: TerminalCell, link_id: TerminalHyperlinkId) u64 {
    if (comptime native_matches_wire) {
        var wire: Cell = @bitCast(cell);
        wire.hyperlink = link_id != 0;
        wire.hyperlink_id = link_id;
        return @bitCast(wire);
    }

    const wire: Cell = .{
        .kind = @intFromEnum(cell.content_tag),
        .content = switch (cell.content_tag) {
            .codepoint,
            .codepoint_grapheme,
            => cell.content.codepoint.data,
            .bg_color_palette => cell.content.color_palette.data,
            .bg_color_rgb => @as(u24, cell.content.color_rgb.r) |
                (@as(u24, cell.content.color_rgb.g) << 8) |
                (@as(u24, cell.content.color_rgb.b) << 16),
        },
        .style_id = cell.style_id,
        .width = switch (cell.wide) {
            .narrow => 0,
            .wide => 1,
            .spacer_tail => 2,
            .spacer_head => 3,
        },
        .protected = cell.protected,
        .hyperlink = link_id != 0,
        .semantic_content = switch (cell.semantic_content) {
            .output => 0,
            .input => 1,
            .prompt => 2,
        },
        .hyperlink_id = link_id,
    };
    return @bitCast(wire);
}

/// Store one normalized, hyperlink-free wire word as a native cell.
fn storeCell(cell: *TerminalCell, bits: u64) void {
    if (comptime native_matches_wire) {
        const words: [*]u64 = @ptrCast(cell);
        words[0] = bits;
        return;
    }

    const wire: Cell = @bitCast(bits);
    var native: TerminalCell = .init(0);
    switch (@as(Cell.Kind, @enumFromInt(wire.kind))) {
        .codepoint, .codepoint_grapheme => native.content = .{
            .codepoint = .{ .data = @intCast(wire.content) },
        },
        .bg_color_palette => {
            native.content_tag = .bg_color_palette;
            native.content = .{
                .color_palette = .{ .data = @truncate(wire.content) },
            };
        },
        .bg_color_rgb => {
            native.content_tag = .bg_color_rgb;
            native.content = .{ .color_rgb = .{
                .r = @truncate(wire.content),
                .g = @truncate(wire.content >> 8),
                .b = @truncate(wire.content >> 16),
            } };
        },
    }
    native.style_id = wire.style_id;
    native.wide = @enumFromInt(wire.width);
    native.protected = wire.protected;
    native.semantic_content = @enumFromInt(wire.semantic_content);
    cell.* = native;
}

/// Maps encoded table IDs to IDs assigned by the destination page.
///
/// Build this by inserting each decoded table entry into the page, then
/// recording the encoded ID and the ID returned by the page's set. ID zero
/// is implicit and does not need an entry. Lookup must be cheap because the
/// grid decoder consults it for every styled or linked cell, so this is a
/// direct-indexed table rather than a hash map.
fn Remap(comptime Id: type) type {
    return struct {
        const Self = @This();

        /// One slot for every possible encoded ID.
        pub const capacity = std.math.maxInt(Id) + 1;

        /// Indexed by encoded ID; zero means unmapped or default.
        entries: []Id,

        /// Tracks IDs that received an entry, including ones mapped to the
        /// default, so callers can give duplicate table entries first-wins
        /// semantics.
        seen: std.DynamicBitSetUnmanaged,

        pub fn init(alloc: Allocator) Allocator.Error!Self {
            const entries = try alloc.alloc(Id, capacity);
            errdefer alloc.free(entries);
            @memset(entries, 0);
            const seen = try std.DynamicBitSetUnmanaged.initEmpty(
                alloc,
                capacity,
            );
            return .{ .entries = entries, .seen = seen };
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            alloc.free(self.entries);
            self.seen.deinit(alloc);
            self.* = undefined;
        }

        /// Record one encoded-to-native mapping.
        pub fn put(self: *Self, encoded: Id, native: Id) void {
            assert(!self.seen.isSet(encoded));
            self.entries[encoded] = native;
            self.seen.set(encoded);
        }

        /// Whether the encoded ID already has an entry, even a default one.
        pub fn contains(self: *const Self, encoded: Id) bool {
            return self.seen.isSet(encoded);
        }

        /// The native ID for an encoded ID, or zero when unmapped.
        pub inline fn get(self: *const Self, encoded: Id) Id {
            return self.entries[encoded];
        }
    };
}

const test_golden_fixture = test_fixture.parse(
    @embedFile("testdata/grid-v1.hex"),
);

test "cell wire layout registry" {
    const testing = std.testing;

    // The wire bit positions are format constants. The shifts and masks
    // derive from the packed struct, so pin the struct itself to the
    // documented registry so an edit cannot silently move wire bits.
    try testing.expectEqual(0, @bitOffsetOf(Cell, "kind"));
    try testing.expectEqual(2, @bitOffsetOf(Cell, "content"));
    try testing.expectEqual(26, @bitOffsetOf(Cell, "style_id"));
    try testing.expectEqual(42, @bitOffsetOf(Cell, "width"));
    try testing.expectEqual(44, @bitOffsetOf(Cell, "protected"));
    try testing.expectEqual(45, @bitOffsetOf(Cell, "hyperlink"));
    try testing.expectEqual(46, @bitOffsetOf(Cell, "semantic_content"));
    try testing.expectEqual(48, @bitOffsetOf(Cell, "hyperlink_id"));

    // The native cell currently matches the wire registry, which enables
    // the bulk row codec. If this fails, the native layout diverged: either
    // restore it or accept the portable codec and update this expectation.
    try testing.expect(native_matches_wire);
}

test "grid golden encoding and decoding" {
    const capacity: terminal_page.Capacity = .{
        .cols = 3,
        .rows = 2,
        .styles = 0,
        .hyperlink_bytes = 0,
        .grapheme_bytes = 64,
        .string_bytes = 0,
    };
    var source = try TerminalPage.init(capacity);
    defer source.deinit();

    // The first row covers semantic metadata, a wide-cell pair, and a
    // multi-codepoint grapheme.
    const wide = source.getRowAndCell(0, 0);
    wide.row.semantic_prompt = .prompt;
    wide.cell.* = .init('A');
    wide.cell.wide = .wide;
    wide.cell.protected = true;
    wide.cell.semantic_content = .prompt;

    const tail = source.getRowAndCell(1, 0);
    tail.cell.wide = .spacer_tail;
    tail.cell.semantic_content = .input;

    const grapheme = source.getRowAndCell(2, 0);
    grapheme.cell.* = .init('x');
    try source.setGraphemes(
        grapheme.row,
        grapheme.cell,
        &.{ 0x0301, 0x0302 },
    );

    // The second row covers both background-color kinds and a wrapped spacer
    // head with the remaining row semantic value.
    const palette = source.getRowAndCell(0, 1);
    palette.cell.content_tag = .bg_color_palette;
    palette.cell.content = .{ .color_palette = .{ .data = 7 } };

    const rgb = source.getRowAndCell(1, 1);
    rgb.cell.content_tag = .bg_color_rgb;
    rgb.cell.content = .{ .color_rgb = .{
        .r = 0xaa,
        .g = 0xbb,
        .b = 0xcc,
    } };
    rgb.cell.protected = true;

    const head = source.getRowAndCell(2, 1);
    head.cell.wide = .spacer_head;
    head.row.wrap = true;
    head.row.wrap_continuation = true;
    head.row.semantic_prompt = .prompt_continuation;

    var encoded: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&encoded);
    try encode(&source, &writer);
    try test_fixture.expectEqual(
        .bytes,
        "src/terminal/snapshot/testdata/grid-v1.hex",
        "snapshot_fixture-grid-v1.hex",
        &test_golden_fixture,
        writer.buffered(),
    );

    var destination = try TerminalPage.init(capacity);
    defer destination.deinit();
    var style_remap = try StyleRemap.init(std.testing.allocator);
    defer style_remap.deinit(std.testing.allocator);
    var hyperlink_remap = try HyperlinkRemap.init(std.testing.allocator);
    defer hyperlink_remap.deinit(std.testing.allocator);

    // Decode the checked-in reference through a one-byte reader buffer.
    var fixture_reader: std.Io.Reader = .fixed(&test_golden_fixture);
    var read_buffer: [1]u8 = undefined;
    var limited = fixture_reader.limited(.unlimited, &read_buffer);
    try decode(
        &destination,
        &limited.interface,
        &style_remap,
        &hyperlink_remap,
    );
    try destination.verifyIntegrity(std.testing.allocator);

    const decoded_wide = destination.getRowAndCell(0, 0);
    try std.testing.expectEqual(@as(u21, 'A'), decoded_wide.cell.codepoint());
    try std.testing.expectEqual(TerminalCell.Wide.wide, decoded_wide.cell.wide);
    try std.testing.expect(decoded_wide.cell.protected);
    try std.testing.expectEqual(
        TerminalCell.SemanticContent.prompt,
        decoded_wide.cell.semantic_content,
    );
    try std.testing.expectEqual(
        TerminalRow.SemanticPrompt.prompt,
        decoded_wide.row.semantic_prompt,
    );

    const decoded_tail = destination.getRowAndCell(1, 0);
    try std.testing.expectEqual(
        TerminalCell.Wide.spacer_tail,
        decoded_tail.cell.wide,
    );
    try std.testing.expectEqual(
        TerminalCell.SemanticContent.input,
        decoded_tail.cell.semantic_content,
    );

    const decoded_grapheme = destination.getRowAndCell(2, 0);
    try std.testing.expectEqualSlices(
        u21,
        &.{ 0x0301, 0x0302 },
        destination.lookupGrapheme(decoded_grapheme.cell).?,
    );

    const decoded_palette = destination.getRowAndCell(0, 1);
    try std.testing.expectEqual(
        TerminalCell.ContentTag.bg_color_palette,
        decoded_palette.cell.content_tag,
    );
    try std.testing.expectEqual(
        @as(u8, 7),
        decoded_palette.cell.content.color_palette.data,
    );

    const decoded_rgb = destination.getRowAndCell(1, 1);
    try std.testing.expectEqual(
        TerminalCell.ContentTag.bg_color_rgb,
        decoded_rgb.cell.content_tag,
    );
    try std.testing.expectEqual(
        TerminalCell.RGB{ .r = 0xaa, .g = 0xbb, .b = 0xcc },
        decoded_rgb.cell.content.color_rgb,
    );
    try std.testing.expect(decoded_rgb.cell.protected);

    const decoded_head = destination.getRowAndCell(2, 1);
    try std.testing.expectEqual(
        TerminalCell.Wide.spacer_head,
        decoded_head.cell.wide,
    );
    try std.testing.expect(decoded_head.row.wrap);
    try std.testing.expect(decoded_head.row.wrap_continuation);
    try std.testing.expectEqual(
        TerminalRow.SemanticPrompt.prompt_continuation,
        decoded_head.row.semantic_prompt,
    );

    // A re-encode proves the decoded native page retains every wire field.
    var reencoded: [128]u8 = undefined;
    var rewriter: std.Io.Writer = .fixed(&reencoded);
    try encode(&destination, &rewriter);
    try std.testing.expectEqualStrings(
        &test_golden_fixture,
        rewriter.buffered(),
    );
}

test "grid elides trailing default cells" {
    const testing = std.testing;
    var page = try TerminalPage.init(.{ .cols = 80, .rows = 3 });
    defer page.deinit();

    // Row 0 is fully default. Row 1 has content in columns zero and two.
    // Row 2 has one protected-only cell at column four.
    const middle = page.getRowAndCell(2, 1);
    middle.cell.* = .init('b');
    page.getRowAndCell(0, 1).cell.* = .init('a');
    page.getRowAndCell(4, 2).cell.protected = true;

    var encoded: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&encoded);
    try encode(&page, &writer);

    // 3 bytes per row header, cells only through the last non-default
    // cell, and an empty grapheme section.
    try testing.expectEqual(
        @as(usize, 3 + (3 + 3 * 8) + (3 + 5 * 8) + 4),
        writer.buffered().len,
    );

    var destination = try TerminalPage.init(.{ .cols = 80, .rows = 3 });
    defer destination.deinit();
    var style_remap = try StyleRemap.init(testing.allocator);
    defer style_remap.deinit(testing.allocator);
    var hyperlink_remap = try HyperlinkRemap.init(testing.allocator);
    defer hyperlink_remap.deinit(testing.allocator);

    var reader: std.Io.Reader = .fixed(writer.buffered());
    try decode(&destination, &reader, &style_remap, &hyperlink_remap);
    try destination.verifyIntegrity(testing.allocator);

    try testing.expectEqual(
        @as(u21, 'a'),
        destination.getRowAndCell(0, 1).cell.codepoint(),
    );
    try testing.expectEqual(
        @as(u21, 'b'),
        destination.getRowAndCell(2, 1).cell.codepoint(),
    );
    try testing.expect(destination.getRowAndCell(4, 2).cell.protected);
    try testing.expect(destination.getRowAndCell(79, 1).cell.isZero());
}

test "grid rejects a row cell count above the column count" {
    const testing = std.testing;
    var page = try TerminalPage.init(.{ .cols = 2, .rows = 1 });
    defer page.deinit();
    var style_remap = try StyleRemap.init(testing.allocator);
    defer style_remap.deinit(testing.allocator);
    var hyperlink_remap = try HyperlinkRemap.init(testing.allocator);
    defer hyperlink_remap.deinit(testing.allocator);

    var payload: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&payload);
    try writer.writeByte(@bitCast(Row{}));
    try io.writeInt(&writer, u16, 3);
    for (0..3) |_| try io.writeInt(&writer, u64, 0);
    try io.writeInt(&writer, u32, 0);

    var reader: std.Io.Reader = .fixed(writer.buffered());
    try testing.expectError(
        error.InvalidRowCellCount,
        decode(&page, &reader, &style_remap, &hyperlink_remap),
    );
}

test "grid normalizes incomplete wide cells" {
    const testing = std.testing;
    // One column puts the wide cell at the row end. Two columns put an
    // ordinary narrow cell after it. Neither case supplies a spacer tail.
    // Both rely on the implicit narrow cell rule when the tail is elided.
    for ([_]u16{ 1, 2 }) |columns| {
        const capacity: terminal_page.Capacity = .{
            .cols = columns,
            .rows = 1,
        };

        // Craft the malformed row directly on the wire. Decoding keeps its
        // content but makes the incomplete wide cell narrow.
        var payload: [64]u8 = undefined;
        var payload_writer: std.Io.Writer = .fixed(&payload);
        try payload_writer.writeByte(@bitCast(Row{}));
        try io.writeInt(&payload_writer, u16, columns);
        try io.writeInt(&payload_writer, u64, @bitCast(Cell{
            .width = 1, // wide
            .content = 'A',
        }));
        if (columns > 1) try io.writeInt(&payload_writer, u64, @bitCast(Cell{
            .content = 'B',
        }));
        try io.writeInt(&payload_writer, u32, 0);

        var destination = try TerminalPage.init(capacity);
        defer destination.deinit();
        var style_remap = try StyleRemap.init(testing.allocator);
        defer style_remap.deinit(testing.allocator);
        var hyperlink_remap = try HyperlinkRemap.init(testing.allocator);
        defer hyperlink_remap.deinit(testing.allocator);

        var payload_reader: std.Io.Reader = .fixed(
            payload_writer.buffered(),
        );
        try decode(
            &destination,
            &payload_reader,
            &style_remap,
            &hyperlink_remap,
        );
        try destination.verifyIntegrity(testing.allocator);

        try testing.expectEqual(
            @as(u21, 'A'),
            destination.getRowAndCell(0, 0).cell.codepoint(),
        );
        try testing.expectEqual(
            TerminalCell.Wide.narrow,
            destination.getRowAndCell(0, 0).cell.wide,
        );
        if (columns > 1) {
            const second = destination.getRowAndCell(1, 0).cell;
            try testing.expectEqual(@as(u21, 'B'), second.codepoint());
            try testing.expectEqual(TerminalCell.Wide.narrow, second.wide);
        }
    }

    // A wide marker whose spacer tail was elided by a short cell count is
    // also normalized, and the trailing cells stay default.
    var page = try TerminalPage.init(.{ .cols = 4, .rows = 1 });
    defer page.deinit();
    var style_remap = try StyleRemap.init(testing.allocator);
    defer style_remap.deinit(testing.allocator);
    var hyperlink_remap = try HyperlinkRemap.init(testing.allocator);
    defer hyperlink_remap.deinit(testing.allocator);

    var payload: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&payload);
    try writer.writeByte(@bitCast(Row{}));
    try io.writeInt(&writer, u16, 1);
    try io.writeInt(&writer, u64, @bitCast(Cell{
        .width = 1, // wide
        .content = 'W',
    }));
    try io.writeInt(&writer, u32, 0);

    var reader: std.Io.Reader = .fixed(writer.buffered());
    try decode(&page, &reader, &style_remap, &hyperlink_remap);
    try page.verifyIntegrity(testing.allocator);
    try testing.expectEqual(
        TerminalCell.Wide.narrow,
        page.getRowAndCell(0, 0).cell.wide,
    );
    try testing.expect(page.getRowAndCell(1, 0).cell.isZero());
}

test "grid normalizes reserved cell values" {
    const testing = std.testing;
    var page = try TerminalPage.init(.{ .cols = 3, .rows = 1 });
    defer page.deinit();
    var style_remap = try StyleRemap.init(testing.allocator);
    defer style_remap.deinit(testing.allocator);
    var hyperlink_remap = try HyperlinkRemap.init(testing.allocator);
    defer hyperlink_remap.deinit(testing.allocator);

    var payload: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&payload);

    // Reserved row flag bits are ignored while the unknown semantic-prompt
    // value degrades to none and wrap survives.
    try writer.writeByte(0xFD);
    try io.writeInt(&writer, u16, 3);

    // A surrogate codepoint with reserved semantic content 3.
    try io.writeInt(&writer, u64, @bitCast(Cell{
        .content = 0xD800,
        .semantic_content = 3,
    }));

    // Reserved palette content bits do not obscure the palette index.
    try io.writeInt(&writer, u64, @bitCast(Cell{
        .kind = 2,
        .content = 0xFFFF07,
    }));

    // An unknown style reference degrades to the default style, and an
    // unknown hyperlink reference leaves the cell unlinked.
    try io.writeInt(&writer, u64, @bitCast(Cell{
        .content = 'x',
        .style_id = 5,
        .hyperlink = true,
        .hyperlink_id = 9,
    }));
    try io.writeInt(&writer, u32, 0);

    var reader: std.Io.Reader = .fixed(writer.buffered());
    try decode(&page, &reader, &style_remap, &hyperlink_remap);
    try page.verifyIntegrity(testing.allocator);

    const first = page.getRowAndCell(0, 0);
    try testing.expect(first.row.wrap);
    try testing.expectEqual(
        TerminalRow.SemanticPrompt.none,
        first.row.semantic_prompt,
    );
    try testing.expectEqual(@as(u21, 0xFFFD), first.cell.codepoint());
    try testing.expectEqual(
        TerminalCell.SemanticContent.output,
        first.cell.semantic_content,
    );

    const second = page.getRowAndCell(1, 0).cell;
    try testing.expectEqual(
        TerminalCell.ContentTag.bg_color_palette,
        second.content_tag,
    );
    try testing.expectEqual(@as(u8, 7), second.content.color_palette.data);

    const third = page.getRowAndCell(2, 0).cell;
    try testing.expectEqual(@as(u21, 'x'), third.codepoint());
    try testing.expectEqual(@as(TerminalStyleId, 0), third.style_id);
    try testing.expect(!third.hyperlink);
    try testing.expectEqual(null, page.lookupHyperlink(third));
}

test "grid drops undeliverable grapheme entries" {
    const testing = std.testing;
    var page = try TerminalPage.init(.{
        .cols = 4,
        .rows = 1,
        .grapheme_bytes = 64,
    });
    defer page.deinit();
    var style_remap = try StyleRemap.init(testing.allocator);
    defer style_remap.deinit(testing.allocator);
    var hyperlink_remap = try HyperlinkRemap.init(testing.allocator);
    defer hyperlink_remap.deinit(testing.allocator);

    var payload: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&payload);
    try writer.writeByte(@bitCast(Row{}));
    try io.writeInt(&writer, u16, 4);
    // A kind 1 cell that receives a valid entry.
    try io.writeInt(&writer, u64, @bitCast(Cell{ .kind = 1, .content = 'x' }));
    // A kind 1 cell without an entry decodes as a plain codepoint.
    try io.writeInt(&writer, u64, @bitCast(Cell{ .kind = 1, .content = 'y' }));
    // A background cell cannot carry a suffix.
    try io.writeInt(&writer, u64, @bitCast(Cell{ .kind = 2, .content = 7 }));
    // An empty codepoint cannot carry a suffix.
    try io.writeInt(&writer, u64, @bitCast(Cell{}));

    try io.writeInt(&writer, u32, 5);
    // Valid entry with one invalid scalar dropped from within it.
    try io.writeInt(&writer, u16, 0);
    try io.writeInt(&writer, u16, 0);
    try io.writeInt(&writer, u16, 3);
    try io.writeInt(&writer, u32, 0x0301);
    try io.writeInt(&writer, u32, 0xD800);
    try io.writeInt(&writer, u32, 0x0302);
    // Duplicate entry for the same cell is consumed and dropped.
    try io.writeInt(&writer, u16, 0);
    try io.writeInt(&writer, u16, 0);
    try io.writeInt(&writer, u16, 1);
    try io.writeInt(&writer, u32, 0x0303);
    // Entry for the background cell is consumed and dropped.
    try io.writeInt(&writer, u16, 0);
    try io.writeInt(&writer, u16, 2);
    try io.writeInt(&writer, u16, 1);
    try io.writeInt(&writer, u32, 0x0301);
    // Entry for the empty cell is consumed and dropped.
    try io.writeInt(&writer, u16, 0);
    try io.writeInt(&writer, u16, 3);
    try io.writeInt(&writer, u16, 1);
    try io.writeInt(&writer, u32, 0x0301);
    // Entry outside the grid is consumed and dropped.
    try io.writeInt(&writer, u16, 7);
    try io.writeInt(&writer, u16, 0);
    try io.writeInt(&writer, u16, 1);
    try io.writeInt(&writer, u32, 0x0301);

    var reader: std.Io.Reader = .fixed(writer.buffered());
    try decode(&page, &reader, &style_remap, &hyperlink_remap);
    try page.verifyIntegrity(testing.allocator);

    const first = page.getRowAndCell(0, 0);
    try testing.expectEqualSlices(
        u21,
        &.{ 0x0301, 0x0302 },
        page.lookupGrapheme(first.cell).?,
    );
    const second = page.getRowAndCell(1, 0).cell;
    try testing.expectEqual(@as(u21, 'y'), second.codepoint());
    try testing.expect(!second.hasGrapheme());
    try testing.expect(!page.getRowAndCell(2, 0).cell.hasGrapheme());
    try testing.expect(!page.getRowAndCell(3, 0).cell.hasGrapheme());
}
