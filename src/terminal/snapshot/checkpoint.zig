//! READY and FINISH snapshot checkpoint records.
//!
//! Each checkpoint payload is one BLAKE3-256 digest of every snapshot byte
//! before that checkpoint's record header. This binds record order and detects
//! omitted or duplicated records in ways that independent record CRCs cannot.
//!
//! READY covers the envelope, TERMINAL, and all SCREEN/PAGE sequences. FINISH
//! covers that same prefix plus the complete READY record and all HISTORY/PAGE
//! sequences. Neither digest includes its own record. FINISH must be followed
//! immediately by end-of-file; READY may be followed by history.
//!
//! The digest does not replace record framing. Its 32-byte payload is still
//! protected by the record's CRC32C.
//!
//! ## Binary Format
//!
//! READY and FINISH use the same fixed payload:
//!
//! ```text
//!  0 +----------------------------+
//!    | BLAKE3-256 prefix digest   |
//!    | 32 bytes                   |
//! 32 +----------------------------+
//! ```

const std = @import("std");
const test_fixture = @import("fixture.zig");
const record = @import("record.zig");

const Blake3 = std.crypto.hash.Blake3;

/// The prefix digest exchanged by checkpoint codecs and the snapshot driver.
pub const Digest = [Blake3.digest_length]u8;

comptime {
    std.debug.assert(@sizeOf(Digest) == 32);
}

/// Selects one of the two checkpoint positions in a snapshot.
pub const Kind = enum {
    ready,
    finish,

    fn tag(self: Kind) record.Tag {
        return switch (self) {
            .ready => .ready,
            .finish => .finish,
        };
    }
};

pub const EncodeError = std.Io.Writer.Error ||
    record.Writer.FinishError;

/// Append one checkpoint covering every byte already in `destination`.
///
/// If writing fails, the incomplete checkpoint is removed while all covered
/// prefix bytes remain unchanged.
pub fn encode(
    kind: Kind,
    destination: *std.Io.Writer.Allocating,
) EncodeError!void {
    var digest: Digest = undefined;
    Blake3.hash(destination.written(), &digest, .{});

    var record_writer = try record.Writer.init(destination, kind.tag());
    errdefer record_writer.cancel();
    try record_writer.payloadWriter().writeAll(&digest);
    try record_writer.finish();
}

pub const DecodeError = record.Reader.InitError ||
    record.Reader.FinishError ||
    error{
        /// The next record is valid but is not the expected checkpoint.
        UnexpectedRecordTag,

        /// The checkpoint does not describe the preceding snapshot bytes.
        InvalidDigest,

        /// FINISH was followed by additional bytes.
        TrailingData,
    };

/// Decode and validate one checkpoint against its preceding-byte digest.
///
/// `expected` must be finalized before any byte of this record is included in
/// the caller's running digest. FINISH additionally requires end-of-file.
pub fn decode(
    kind: Kind,
    expected: Digest,
    source: *std.Io.Reader,
) DecodeError!void {
    var record_reader: record.Reader = undefined;
    try record_reader.init(source);
    if (record_reader.header.tag != kind.tag()) {
        return error.UnexpectedRecordTag;
    }

    var actual: Digest = undefined;
    try record_reader.payloadReader().readSliceAll(&actual);
    try record_reader.finish();
    if (!std.mem.eql(u8, &expected, &actual)) return error.InvalidDigest;

    if (kind == .finish) {
        _ = source.peekByte() catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        return error.TrailingData;
    }
}

const test_ready_fixture = test_fixture.parse(
    @embedFile("testdata/checkpoint-ready-v1.hex"),
);

test "READY golden encoding and BLAKE3-256 registry" {
    const prefix = "abc";

    var snapshot: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer snapshot.deinit();
    try snapshot.writer.writeAll(prefix);
    try encode(.ready, &snapshot);

    try test_fixture.expectEqual(
        .bytes,
        "src/terminal/snapshot/testdata/checkpoint-ready-v1.hex",
        "snapshot_fixture-checkpoint-ready-v1.hex",
        &test_ready_fixture,
        snapshot.written(),
    );

    // The checked-in payload independently locks the BLAKE3-256 registry.
    var actual: Digest = undefined;
    Blake3.hash(prefix, &actual, .{});
    const payload_offset = prefix.len + record.Header.len;
    try std.testing.expectEqualSlices(
        u8,
        test_ready_fixture[payload_offset..][0..actual.len],
        &actual,
    );

    // Finalizing a streaming hasher neither consumes nor resets it.
    var hasher = Blake3.init(.{});
    hasher.update("a");
    var prefix_digest: Digest = undefined;
    Blake3.hash("a", &prefix_digest, .{});
    hasher.final(&actual);
    try std.testing.expectEqual(prefix_digest, actual);

    hasher.update("bc");
    hasher.final(&actual);
    try std.testing.expectEqualSlices(
        u8,
        test_ready_fixture[payload_offset..][0..actual.len],
        &actual,
    );

    // Decode the checked-in record rather than the generated candidate.
    var source: std.Io.Reader = .fixed(test_ready_fixture[prefix.len..]);
    try decode(.ready, actual, &source);
}

test "READY and FINISH checkpoint coverage" {
    const testing = std.testing;

    var snapshot: std.Io.Writer.Allocating = .init(testing.allocator);
    defer snapshot.deinit();
    try snapshot.writer.writeAll("prefix");

    // READY covers only the bytes that precede its own record.
    const ready_offset = snapshot.written().len;
    var ready_digest: Digest = undefined;
    Blake3.hash(snapshot.written(), &ready_digest, .{});
    try encode(.ready, &snapshot);

    // History follows READY and is included by FINISH.
    try snapshot.writer.writeAll("history");
    const finish_offset = snapshot.written().len;
    var finish_digest: Digest = undefined;
    Blake3.hash(snapshot.written(), &finish_digest, .{});
    try encode(.finish, &snapshot);

    var ready_source: std.Io.Reader = .fixed(
        snapshot.written()[ready_offset..],
    );
    try decode(.ready, ready_digest, &ready_source);

    var finish_source: std.Io.Reader = .fixed(
        snapshot.written()[finish_offset..],
    );
    try decode(.finish, finish_digest, &finish_source);
}

test "checkpoint rejects wrong tags, digests, and FINISH trailing data" {
    const testing = std.testing;

    var snapshot: std.Io.Writer.Allocating = .init(testing.allocator);
    defer snapshot.deinit();
    try snapshot.writer.writeAll("prefix");
    const checkpoint_offset = snapshot.written().len;
    var digest: Digest = undefined;
    Blake3.hash(snapshot.written(), &digest, .{});
    try encode(.ready, &snapshot);

    var wrong_tag: std.Io.Reader = .fixed(
        snapshot.written()[checkpoint_offset..],
    );
    try testing.expectError(
        error.UnexpectedRecordTag,
        decode(.finish, digest, &wrong_tag),
    );

    var invalid_digest = digest;
    invalid_digest[0] ^= 1;
    var invalid_digest_source: std.Io.Reader = .fixed(
        snapshot.written()[checkpoint_offset..],
    );
    try testing.expectError(
        error.InvalidDigest,
        decode(.ready, invalid_digest, &invalid_digest_source),
    );

    var finished: std.Io.Writer.Allocating = .init(testing.allocator);
    defer finished.deinit();
    try finished.writer.writeAll("prefix");
    const finish_offset = finished.written().len;
    try encode(.finish, &finished);
    try finished.writer.writeByte(0);

    var trailing_source: std.Io.Reader = .fixed(
        finished.written()[finish_offset..],
    );
    try testing.expectError(
        error.TrailingData,
        decode(.finish, digest, &trailing_source),
    );
}
