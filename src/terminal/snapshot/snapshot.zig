//! Complete terminal snapshot encoding and restoration.

const std = @import("std");
const build_options = @import("terminal_options");
const Allocator = std.mem.Allocator;
const checkpoint = @import("checkpoint.zig");
const envelope = @import("envelope.zig");
const test_fixture = @import("fixture.zig");
const history = @import("history.zig");
const record = @import("record.zig");
const screen = @import("screen.zig");
const terminal = @import("terminal.zig");
const Terminal = @import("../Terminal.zig");
const terminal_kitty = @import("../kitty.zig");
const TerminalPageList = @import("../PageList.zig");
const TerminalScreen = @import("../Screen.zig");
const TerminalScreenKey = @import("../ScreenSet.zig").Key;

const test_complete_fixture = test_fixture.parse(
    @embedFile("testdata/complete-v1.hex"),
);

/// Errors possible while encoding one complete terminal snapshot.
pub const EncodeError = terminal.EncodeError ||
    screen.EncodeError ||
    history.EncodeError ||
    checkpoint.EncodeError ||
    error{
        /// A snapshot envelope must begin at byte zero.
        DestinationNotEmpty,
    };

/// Encode one complete terminal snapshot.
///
/// `destination` must be empty because checkpoint digests cover every byte
/// from the snapshot envelope onward. The operation is transactional: any
/// failure restores the destination to empty.
pub fn encode(
    t: *const Terminal,
    destination: *std.Io.Writer.Allocating,
) EncodeError!void {
    // We require empty for checkpoint digests
    if (destination.written().len != 0) return error.DestinationNotEmpty;
    errdefer destination.shrinkRetainingCapacity(0);

    // 1. Envelope
    try envelope.encode(&destination.writer);

    // 2. Terminal
    try terminal.encode(t, destination);

    // 3. Primary and alt screen
    try screen.encode(
        t.screens.get(.primary).?,
        .primary,
        destination,
    );
    if (t.screens.get(.alternate)) |alternate| try screen.encode(
        alternate,
        .alternate,
        destination,
    );

    // 4. Ready checkpoint. In the future we'll put our continuation
    // state before this so pty bytes can also flow.
    try checkpoint.encode(.ready, destination);

    // 5. History
    try history.encode(
        t.screens.get(.primary).?,
        .primary,
        destination,
    );
    if (t.screens.get(.alternate)) |alternate| try history.encode(
        alternate,
        .alternate,
        destination,
    );

    // 6. Finish
    try checkpoint.encode(.finish, destination);
}

/// Errors possible while restoring one complete terminal snapshot.
pub const DecodeError = envelope.DecodeError ||
    terminal.DecodeError ||
    screen.DecodeError ||
    history.DecodeError ||
    checkpoint.DecodeError ||
    error{
        /// A SCREEN names a key not declared by TERMINAL.
        UnexpectedScreenKey,

        /// More than one SCREEN names the same key.
        DuplicateScreen,
    };

/// Restore one complete snapshot into a native terminal.
///
/// The reader must contain exactly one snapshot through FINISH. Restoration is
/// transactional: the returned terminal is either complete and ready or
/// not (error return).
pub fn decode(
    source: *std.Io.Reader,
    io_: std.Io,
    alloc: Allocator,
) DecodeError!Terminal {
    // Keep this reader unbuffered so the hasher never reads past a checkpoint
    // boundary. Record readers provide their own bounded buffers.
    const Blake3 = std.crypto.hash.Blake3;
    var hashing = source.hashed(Blake3.init(.{}), &.{});
    const reader = &hashing.reader;

    // Read the envelope, which is currently just a verification step.
    try envelope.decode(reader);

    // TERMINAL establishes terminal-wide state and allocates empty screen
    // slots with their final routing. SCREEN values replace those slots in
    // place so ScreenSet pointers, including the active pointer, stay valid.
    var result = try terminal.decode(reader, io_, alloc);
    errdefer result.deinit(alloc);

    // TERMINAL initializes exactly the number of screen slots it declared.
    // Decode that many SCREEN sequences and route each one by its encoded key.
    const screen_count = result.screens.all.count();
    const options: TerminalScreen.Options = options: {
        const primary = result.screens.get(.primary).?;
        const explicit_bytes = primary.pages.limits.bytes.explicit;
        const explicit_lines = primary.pages.limits.lines.explicit;
        break :options .{
            .cols = result.cols,
            .rows = result.rows,
            .max_scrollback_bytes = if (explicit_bytes == std.math.maxInt(usize))
                null
            else
                explicit_bytes,
            .max_scrollback_lines = if (explicit_lines == std.math.maxInt(usize))
                null
            else
                explicit_lines,
        };
    };

    for (0..screen_count) |_| {
        var decoded = try screen.decode(
            reader,
            io_,
            alloc,
            options,
        );
        errdefer decoded.deinit();

        const slot = result.screens.get(decoded.key) orelse
            return error.UnexpectedScreenKey;

        // The fresh ScreenSet starts every declared slot at generation zero.
        // Replacing a slot advances its generation, so a nonzero value means
        // an earlier SCREEN in this snapshot already supplied the same key.
        if (result.screens.generation(decoded.key) != 0) return error.DuplicateScreen;

        slot.deinit();
        slot.* = decoded.screen;
        decoded.screen = undefined;

        // We put an artificial generation in just so we can detect duplicates.
        result.screens.generations.put(
            decoded.key,
            result.screens.generation(decoded.key) +% 1,
        );
    }

    // READY covers the exact envelope-through-SCREEN prefix. Finalizing does
    // not consume the hasher, so the same stream continues toward FINISH.
    var digest: checkpoint.Digest = undefined;
    hashing.hasher.final(&digest);
    try checkpoint.decode(.ready, digest, reader);

    // HISTORY mutates only the restored terminal owned by this function.
    // Although an individual history decoder may publish recent pages as they
    // validate, any later full-snapshot failure deinitializes the whole result.
    const keys = [_]TerminalScreenKey{ .primary, .alternate };
    for (keys) |key| {
        const restored = result.screens.get(key) orelse continue;
        try history.decode(reader, alloc, key, restored);
    }

    // FINISH authenticates READY and all history. Decode it directly from the
    // underlying reader so the digest does not include FINISH itself.
    hashing.hasher.final(&digest);
    try checkpoint.decode(.finish, digest, source);

    if (comptime build_options.slow_runtime_safety) {
        for (keys) |key| {
            const restored = result.screens.get(key) orelse continue;
            restored.pages.assertIntegrity();
            restored.assertIntegrity();
        }
    }
    return result;
}

test "complete snapshot round trip with history and alternate screen" {
    const testing = std.testing;

    var t = try Terminal.init(testing.io, testing.allocator, .{
        .cols = 2,
        .rows = 3,
        .max_scrollback_bytes = null,
        .max_scrollback_lines = null,
    });
    defer t.deinit(testing.allocator);

    // Exercise terminal-wide state.
    t.width_px = 800;
    t.height_px = 600;
    t.colors.palette.set(7, .{ .r = 1, .g = 2, .b = 3 });
    t.modes.values.bracketed_paste = true;
    try t.setPwd("file:///tmp/snapshot");
    try t.setTitle("complete snapshot");

    const primary = t.screens.get(.primary).?;

    // Use small exact capacities so this compound golden remains practical to
    // review while still containing two complete history pages and one active
    // page. Replacing the Screen in place preserves ScreenSet routing.
    var replacement: TerminalScreen = replacement: {
        var builder = try TerminalPageList.Builder.init(
            testing.allocator,
            .{
                .cols = t.cols,
                .rows = t.rows,
                .max_size = null,
                .max_lines = null,
            },
        );
        defer builder.deinit();

        const oldest = try builder.allocatePage(.{ .cols = 2, .rows = 2 });
        oldest.size.rows = 2;
        oldest.getRowAndCell(0, 0).cell.* = .init('A');

        const recent = try builder.allocatePage(.{ .cols = 2, .rows = 2 });
        recent.size.rows = 2;
        recent.getRowAndCell(0, 0).cell.* = .init('B');

        const active = try builder.allocatePage(.{ .cols = 2, .rows = 3 });
        active.size.rows = 3;
        active.getRowAndCell(0, 0).cell.* = .init('C');
        active.getRowAndCell(0, 1).cell.* = .init('D');
        active.getRowAndCell(0, 2).cell.* = .init('E');

        var pages = try builder.finish();
        errdefer pages.deinit();

        const cursor_pin = try pages.trackPin(
            pages.pin(.{ .active = .{} }).?,
        );
        const cursor_rac = cursor_pin.rowAndCell();
        break :replacement .{
            .io = testing.io,
            .alloc = testing.allocator,
            .pages = pages,
            .cursor = .{
                .page_pin = cursor_pin,
                .page_row = cursor_rac.row,
                .page_cell = cursor_rac.cell,
            },
        };
    };
    primary.deinit();
    primary.* = replacement;
    replacement = undefined;

    try testing.expect(primary.pages.scrollbar().total > t.rows);

    // Compression is an internal source representation and must remain
    // unchanged while the complete history is inspected for encoding.
    _ = primary.pages.compress(.full);
    const source_memory = primary.pages.memoryStats();

    // The optional alternate screen participates in both phases and remains
    // the active screen after restoration.
    _ = try t.switchScreen(.alternate);
    try t.printString("alternate");

    var encoded: std.Io.Writer.Allocating = .init(testing.allocator);
    defer encoded.deinit();
    try encode(&t, &encoded);
    try testing.expectEqualDeep(source_memory, primary.pages.memoryStats());
    try test_fixture.expectEqual(
        .snapshot,
        "src/terminal/snapshot/testdata/complete-v1.hex",
        "snapshot_fixture-complete-v1.hex",
        &test_complete_fixture,
        encoded.written(),
    );

    // Restore the checked-in reference rather than the just-generated bytes.
    var encoded_source: std.Io.Reader = .fixed(&test_complete_fixture);
    var source_buffer: [1]u8 = undefined;
    var limited = encoded_source.limited(.unlimited, &source_buffer);
    var restored = try decode(
        &limited.interface,
        testing.io,
        testing.allocator,
    );
    defer restored.deinit(testing.allocator);

    try testing.expectEqual(TerminalScreenKey.alternate, restored.screens.active_key);
    try testing.expectEqual(
        restored.screens.get(.alternate).?,
        restored.screens.active,
    );
    try testing.expectEqualStrings(
        "file:///tmp/snapshot",
        restored.getPwd().?,
    );
    try testing.expectEqualStrings(
        "complete snapshot",
        restored.getTitle().?,
    );
    try testing.expectEqual(
        primary.pages.scrollbar().total,
        restored.screens.get(.primary).?.pages.scrollbar().total,
    );

    // Re-encoding is a compact semantic equality check over all TERMINAL,
    // SCREEN, PAGE, and HISTORY fields and both checkpoint boundaries.
    var reencoded: std.Io.Writer.Allocating = .init(testing.allocator);
    defer reencoded.deinit();
    try encode(&restored, &reencoded);
    try testing.expectEqualStrings(
        &test_complete_fixture,
        reencoded.written(),
    );

    // SCREEN keys make their order independent. Keep HISTORY canonical here;
    // only the active-state screen sequences are intentionally reversed.
    var reversed: std.Io.Writer.Allocating = .init(testing.allocator);
    defer reversed.deinit();
    try envelope.encode(&reversed.writer);
    try terminal.encode(&t, &reversed);
    try screen.encode(t.screens.get(.alternate).?, .alternate, &reversed);
    try screen.encode(primary, .primary, &reversed);
    try checkpoint.encode(.ready, &reversed);
    try history.encode(primary, .primary, &reversed);
    try history.encode(
        t.screens.get(.alternate).?,
        .alternate,
        &reversed,
    );
    try checkpoint.encode(.finish, &reversed);

    var reversed_source: std.Io.Reader = .fixed(reversed.written());
    var reversed_restored = try decode(
        &reversed_source,
        testing.io,
        testing.allocator,
    );
    defer reversed_restored.deinit(testing.allocator);
    try testing.expectEqual(
        TerminalScreenKey.alternate,
        reversed_restored.screens.active_key,
    );
}

test "complete snapshot preserves Kitty virtual placeholders" {
    if (comptime !build_options.kitty_graphics) return error.SkipZigTest;

    const testing = std.testing;
    var t = try Terminal.init(testing.io, testing.allocator, .{
        .cols = 2,
        .rows = 1,
    });
    defer t.deinit(testing.allocator);

    // Register a real virtual placement, then write its grid representation:
    // U+10EEEE followed by row and column diacritics. The image and placement
    // registry is intentionally omitted, but the grid content must remain
    // decodable.
    try t.screens.active.kitty_images.addImage(
        testing.io,
        testing.allocator,
        .{ .id = 1 },
    );
    try t.screens.active.kitty_images.addPlacement(
        testing.io,
        testing.allocator,
        1,
        0,
        .{
            .location = .{ .virtual = {} },
            .columns = 1,
            .rows = 1,
        },
    );
    try t.setAttribute(.{ .@"256_fg" = 1 });
    try t.printString("\u{10EEEE}\u{0305}\u{0305}");
    const source_cell = t.screens.active.pages.getCell(.{
        .screen = .{},
    }).?;
    try testing.expectEqual(
        terminal_kitty.graphics.unicode.placeholder,
        source_cell.cell.codepoint(),
    );
    try testing.expect(source_cell.row.kitty_virtual_placeholder);

    var encoded: std.Io.Writer.Allocating = .init(testing.allocator);
    defer encoded.deinit();
    try encode(&t, &encoded);

    var encoded_source: std.Io.Reader = .fixed(encoded.written());
    var restored = try decode(
        &encoded_source,
        testing.io,
        testing.allocator,
    );
    defer restored.deinit(testing.allocator);

    const restored_cell = restored.screens.active.pages.getCell(.{
        .screen = .{},
    }).?;
    try testing.expectEqual(
        terminal_kitty.graphics.unicode.placeholder,
        restored_cell.cell.codepoint(),
    );
    try testing.expect(restored_cell.cell.hasGrapheme());
    try testing.expect(restored_cell.row.kitty_virtual_placeholder);
    try testing.expectEqual(
        @as(usize, 0),
        restored.screens.active.kitty_images.images.count(),
    );
    try testing.expectEqual(
        @as(usize, 0),
        restored.screens.active.kitty_images.placements.count(),
    );
}

test "complete snapshot encoding is transactional" {
    const testing = std.testing;

    var t = try Terminal.init(testing.io, testing.allocator, .{
        .cols = 2,
        .rows = 1,
    });
    defer t.deinit(testing.allocator);

    // A complete snapshot cannot be appended after unrelated bytes because
    // its envelope and checkpoint coverage both begin at byte zero.
    var nonempty: std.Io.Writer.Allocating = .init(testing.allocator);
    defer nonempty.deinit();
    try nonempty.writer.writeAll("prefix");
    try testing.expectError(
        error.DestinationNotEmpty,
        encode(&t, &nonempty),
    );
    try testing.expectEqualStrings("prefix", nonempty.written());

    // A failure after validation enters a record codec still rolls back every
    // preceding record in this complete snapshot operation.
    t.colors.palette.current[7] = .{ .r = 1, .g = 2, .b = 3 };
    var destination: std.Io.Writer.Allocating = .init(testing.allocator);
    defer destination.deinit();
    try testing.expectError(
        error.InvalidPalette,
        encode(&t, &destination),
    );
    try testing.expectEqual(@as(usize, 0), destination.written().len);
}

test "complete snapshot rejects ordering checkpoints and trailing data" {
    const testing = std.testing;

    var t = try Terminal.init(testing.io, testing.allocator, .{
        .cols = 2,
        .rows = 1,
    });
    defer t.deinit(testing.allocator);
    const primary = t.screens.get(.primary).?;

    // HISTORY is individually valid here, but the full decoder requires the
    // primary SCREEN before READY.
    var reordered: std.Io.Writer.Allocating = .init(testing.allocator);
    defer reordered.deinit();
    try envelope.encode(&reordered.writer);
    try terminal.encode(&t, &reordered);
    try history.encode(primary, .primary, &reordered);
    var reordered_source: std.Io.Reader = .fixed(reordered.written());
    try testing.expectError(
        error.UnexpectedRecordTag,
        decode(&reordered_source, testing.io, testing.allocator),
    );

    // Construct a correctly framed READY with an intentionally unrelated
    // digest so the full driver, rather than record CRC validation, rejects it.
    var invalid_ready: std.Io.Writer.Allocating = .init(testing.allocator);
    defer invalid_ready.deinit();
    try envelope.encode(&invalid_ready.writer);
    try terminal.encode(&t, &invalid_ready);
    try screen.encode(primary, .primary, &invalid_ready);
    var record_writer = try record.Writer.init(&invalid_ready, .ready);
    try record_writer.payloadWriter().splatByteAll(
        0,
        @sizeOf(checkpoint.Digest),
    );
    try record_writer.finish();
    var invalid_ready_source: std.Io.Reader = .fixed(
        invalid_ready.written(),
    );
    try testing.expectError(
        error.InvalidDigest,
        decode(&invalid_ready_source, testing.io, testing.allocator),
    );

    // FINISH is the exact end of a complete snapshot.
    var trailing: std.Io.Writer.Allocating = .init(testing.allocator);
    defer trailing.deinit();
    try encode(&t, &trailing);
    try trailing.writer.writeByte(0);
    var trailing_source: std.Io.Reader = .fixed(trailing.written());
    try testing.expectError(
        error.TrailingData,
        decode(&trailing_source, testing.io, testing.allocator),
    );

    // A SCREEN key must name one of the slots declared by TERMINAL.
    var undeclared: std.Io.Writer.Allocating = .init(testing.allocator);
    defer undeclared.deinit();
    try envelope.encode(&undeclared.writer);
    try terminal.encode(&t, &undeclared);
    try screen.encode(primary, .alternate, &undeclared);
    var undeclared_source: std.Io.Reader = .fixed(undeclared.written());
    try testing.expectError(
        error.UnexpectedScreenKey,
        decode(&undeclared_source, testing.io, testing.allocator),
    );

    // The declared count cannot be satisfied by repeating the same key.
    _ = try t.switchScreen(.alternate);
    var duplicate: std.Io.Writer.Allocating = .init(testing.allocator);
    defer duplicate.deinit();
    try envelope.encode(&duplicate.writer);
    try terminal.encode(&t, &duplicate);
    try screen.encode(primary, .primary, &duplicate);
    try screen.encode(primary, .primary, &duplicate);
    var duplicate_source: std.Io.Reader = .fixed(duplicate.written());
    try testing.expectError(
        error.DuplicateScreen,
        decode(&duplicate_source, testing.io, testing.allocator),
    );
}
