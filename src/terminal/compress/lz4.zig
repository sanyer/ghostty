//! An allocation-free implementation of the raw LZ4 block format.
//!
//! LZ4 has two relevant layers: the block format describes the compressed
//! bytes, while the frame format adds headers, sizes, checksums, and support
//! for a stream of blocks. Terminal pages already have their own ownership
//! and metadata, so this implements only blocks. In particular, an encoded
//! block does not contain its decompressed size. The caller must store that
//! separately and provide an exactly sized buffer when decoding.
//!
//! A block is a series of sequences. Each non-final sequence has this shape:
//!
//!     token | literal length extensions | literals | offset | match length extensions
//!
//! The token's high nibble contains the literal length and its low nibble
//! contains the match length minus four. A nibble value of 15 means that the
//! length continues in extension bytes at the corresponding point in the
//! sequence. Each extension byte adds to the length; a value of 255 means
//! another byte follows. The literal bytes are copied directly. The two-byte
//! little-endian offset then points backwards in the already decompressed
//! output to the match bytes.
//!
//! The last sequence is special: it contains literals only and ends directly
//! after them. The reference format also requires the last five input bytes to
//! be literals and the final match to begin at least twelve bytes before the
//! end of the input. The compressor observes these restrictions so its output
//! can be consumed by optimized LZ4 decoders which copy in larger units.
//!
//! Compression uses the standard fast LZ4 strategy: hash each four-byte input
//! sequence, remember only its most recent position, and test that one position
//! as a match candidate. This favors compression speed and a small, fixed
//! workspace over finding the best possible match. The implementation is
//! scalar Zig and allocates nothing; all input, output, and scratch memory is
//! supplied by the caller.
//!
//! Format reference:
//! https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md
const std = @import("std");

/// Maximum input accepted by the reference LZ4 block API. Keeping the same
/// limit means `compressBound` fits in the integer sizes used by LZ4 callers
/// and gives us the same compatibility boundary as other implementations.
pub const max_input_size: usize = 0x7E000000;

/// Every LZ4 match represents at least four bytes. The token stores the number
/// of bytes beyond this minimum rather than the full match length.
const min_match = 4;

/// Number of bytes at the end of a conforming block which must remain literals.
const last_literals = 5;

/// A match may not begin in the final 12 bytes. This leaves enough room for the
/// minimum match and the required five trailing literals.
const match_find_limit = 12;

/// We retain one input position for each 12-bit hash. LZ4 refers to this as
/// memory usage 14 because the 4096 entries are four bytes each (16 KiB).
const hash_log = 12;

/// Multiplicative hash used by the reference LZ4 fast compressor. The high
/// `hash_log` bits provide the table index.
const hash_multiplier: u32 = 2_654_435_761;

/// Scratch memory used while compressing one block. Each entry stores an input
/// position plus one; zero therefore means that the hash has not been seen.
/// The table is reset by every call to `compress` and can be reused afterwards.
pub const HashTable = [1 << hash_log]u32;

/// Errors which can occur while encoding a block.
pub const CompressError = error{
    /// The input exceeds the maximum size supported by the block compressor.
    InputTooLarge,

    /// The provided output buffer cannot hold the encoded block.
    OutputTooSmall,
};

/// Errors which can occur while decoding a block.
pub const DecompressError = error{
    /// The encoded block ended in the middle of a sequence.
    TruncatedInput,

    /// A match offset was zero or pointed before the produced output.
    InvalidOffset,

    /// A sequence would write beyond the provided output buffer.
    OutputTooSmall,

    /// The block ended before filling the exact-size output buffer.
    OutputSizeMismatch,
};

/// Return the maximum number of bytes needed to encode `input_len` bytes.
///
/// Incompressible input is represented as one literal run. Every 255 literal
/// bytes can require one extension byte. The additional 16-byte margin covers
/// the token and the format's fixed overhead. Callers can allocate this amount
/// once and reuse it for any block no larger than `input_len`.
pub fn compressBound(input_len: usize) CompressError!usize {
    if (input_len > max_input_size) return error.InputTooLarge;
    return input_len + input_len / 255 + 16;
}

/// Compress `input` into a raw LZ4 block in `output`.
///
/// Returns the initialized length of `output`. The input and output buffers
/// must not overlap. `table` is scratch space and does not need to be
/// initialized by the caller; it is reset before use.
pub fn compress(
    input: []const u8,
    output: []u8,
    table: *HashTable,
) CompressError!usize {
    if (input.len > max_input_size) return error.InputTooLarge;

    // Zero is reserved as "no previous position". Actual positions are stored
    // plus one so that a match at input offset zero remains representable.
    @memset(table, 0);

    // `ip` is the current input position, `anchor` is the first literal not yet
    // emitted, and `op` is the next output position. A successful match emits
    // input[anchor..ip] as literals followed by the match, then moves both input
    // positions to the end of that match.
    var op: usize = 0;
    var anchor: usize = 0;
    var ip: usize = 0;

    // LZ4's format leaves the final five input bytes as literals and starts
    // the final match at least twelve bytes before the end. This is not
    // required by our safe decoder, but makes blocks compatible with fast
    // decoders that rely on the standard format restrictions.
    const search_end = if (input.len >= match_find_limit)
        input.len - match_find_limit
    else
        0;

    while (input.len >= match_find_limit and ip <= search_end) {
        // Hash the next four bytes and replace the table entry immediately.
        // Hash collisions are expected, so equality is checked below before
        // accepting the saved position as a match.
        const sequence = readU32(input, ip);
        const hash = hashSequence(sequence);
        const previous_plus_one = table[hash];
        table[hash] = @intCast(ip + 1);

        if (previous_plus_one == 0) {
            ip += 1;
            continue;
        }

        var match_pos: usize = previous_plus_one - 1;

        // Offsets are encoded as u16 and zero is invalid. Since match_pos is
        // always earlier than ip here, checking the distance also rules out a
        // value that cannot be represented in the block.
        if (ip - match_pos > std.math.maxInt(u16) or
            readU32(input, match_pos) != sequence)
        {
            ip += 1;
            continue;
        }

        // Pull the match backwards into the current literal run. This is a
        // cheap improvement that is particularly helpful around aligned cell
        // records without requiring a hash chain.
        while (ip > anchor and match_pos > 0 and
            input[ip - 1] == input[match_pos - 1])
        {
            ip -= 1;
            match_pos -= 1;
        }

        // We already compared the first four bytes. Continue byte-by-byte up
        // to the point where the required last five literals begin.
        var match_end = ip + min_match;
        var candidate_end = match_pos + min_match;
        const match_end_limit = input.len - last_literals;
        while (match_end < match_end_limit and
            input[match_end] == input[candidate_end])
        {
            match_end += 1;
            candidate_end += 1;
        }

        try emitSequence(
            output,
            &op,
            input[anchor..ip],
            @intCast(ip - match_pos),
            match_end - ip,
        );

        // The main loop jumps over the matched bytes rather than hashing every
        // position within them. Seed one position near the end so an adjacent
        // repeated record can still refer back into this match. The next loop
        // iteration will then seed `match_end` normally.
        if (match_end >= 2 and match_end - 2 + min_match <= input.len) {
            const seed = match_end - 2;
            table[hashSequence(readU32(input, seed))] = @intCast(seed + 1);
        }

        ip = match_end;
        anchor = ip;
    }

    // Whatever remains after the last match is the terminal literal-only
    // sequence. For short inputs this is also the only sequence in the block.
    try emitLastLiterals(output, &op, input[anchor..]);
    return op;
}

/// Decompress a raw LZ4 block into an exact-size output buffer.
///
/// Returns `output.len` on success. Both consuming all input and filling all
/// output are required. Raw LZ4 blocks do not carry their decoded size, so this
/// exact-size contract validates the size metadata maintained by the caller.
/// The input and output buffers must not overlap.
pub fn decompress(input: []const u8, output: []u8) DecompressError!usize {
    // `ip` and `op` always identify the next unread input byte and the next
    // unwritten output byte respectively.
    var ip: usize = 0;
    var op: usize = 0;

    while (true) {
        // A normal block ends after the literal bytes of its final sequence.
        // This also accepts the empty block produced by our compressor, which
        // consists of a zero token and no literals.
        if (ip == input.len) {
            if (op != output.len) return error.OutputSizeMismatch;
            return op;
        }

        const token = input[ip];
        ip += 1;

        // The high nibble and any extension bytes describe the literal run.
        // Bounds are checked before slicing so malformed blocks never cause a
        // partial read or write.
        const literal_len = try decodeLength(input, &ip, token >> 4);
        if (literal_len > input.len - ip) return error.TruncatedInput;
        if (literal_len > output.len - op) return error.OutputTooSmall;

        @memcpy(output[op..][0..literal_len], input[ip..][0..literal_len]);
        ip += literal_len;
        op += literal_len;

        // Ending immediately after the literals marks the final sequence. Any
        // non-final sequence must continue with an offset and match length.
        if (ip == input.len) {
            if (op != output.len) return error.OutputSizeMismatch;
            return op;
        }

        if (input.len - ip < 2) return error.TruncatedInput;
        const offset = std.mem.readInt(u16, input[ip..][0..2], .little);
        ip += 2;
        if (offset == 0 or offset > op) return error.InvalidOffset;

        // The token stores the match length minus the four-byte minimum. As
        // with literals, a low nibble of 15 is extended by following bytes.
        const encoded_match_len = try decodeLength(input, &ip, token & 0x0F);
        const match_len = std.math.add(
            usize,
            encoded_match_len,
            min_match,
        ) catch return error.OutputTooSmall;
        if (match_len > output.len - op) return error.OutputTooSmall;

        // Match copies are allowed to overlap. For an offset smaller than the
        // match length, bytes written early in this loop become the source for
        // later bytes. This is how a short pattern such as one space can expand
        // into an arbitrarily long run.
        const match_pos = op - offset;
        for (0..match_len) |i| output[op + i] = output[match_pos + i];
        op += match_len;
    }
}

/// Emit one non-final sequence.
///
/// A sequence starts with a token, followed by optional literal length bytes,
/// the literals themselves, the two-byte offset, and optional match length
/// bytes. This function computes the complete size first so `OutputTooSmall`
/// is reported without partially writing a sequence.
fn emitSequence(
    output: []u8,
    op: *usize,
    literals: []const u8,
    offset: u16,
    match_len: usize,
) CompressError!void {
    std.debug.assert(match_len >= min_match);
    std.debug.assert(offset > 0);

    const encoded_match_len = match_len - min_match;

    // One byte is always needed for the token and two for the offset. Each
    // length may additionally need extension bytes after its token nibble.
    const required = 1 +
        encodedLengthBytes(literals.len) + literals.len +
        2 + encodedLengthBytes(encoded_match_len);
    if (required > output.len - op.*) return error.OutputTooSmall;

    const token_pos = op.*;
    op.* += 1;

    // Lengths below 15 fit directly in their nibble. Larger values put 15 in
    // the nibble and encode the remainder immediately after the token.
    output[token_pos] = (@as(u8, @intCast(@min(literals.len, 15))) << 4) |
        @as(u8, @intCast(@min(encoded_match_len, 15)));

    // Literal length extensions precede the literals they describe.
    if (literals.len >= 15) writeLength(output, op, literals.len - 15);
    @memcpy(output[op.*..][0..literals.len], literals);
    op.* += literals.len;

    // Match length extensions follow the offset because this is where the
    // decoder expects them in an LZ4 sequence.
    std.mem.writeInt(u16, output[op.*..][0..2], offset, .little);
    op.* += 2;
    if (encoded_match_len >= 15)
        writeLength(output, op, encoded_match_len - 15);
}

/// Emit the literal-only sequence which terminates every block.
///
/// There is no offset or match length after these bytes. As with
/// `emitSequence`, capacity is checked before modifying the output.
fn emitLastLiterals(
    output: []u8,
    op: *usize,
    literals: []const u8,
) CompressError!void {
    const required = 1 + encodedLengthBytes(literals.len) + literals.len;
    if (required > output.len - op.*) return error.OutputTooSmall;

    output[op.*] = @as(u8, @intCast(@min(literals.len, 15))) << 4;
    op.* += 1;
    if (literals.len >= 15) writeLength(output, op, literals.len - 15);
    @memcpy(output[op.*..][0..literals.len], literals);
    op.* += literals.len;
}

/// Return the number of extension bytes needed when a length is represented by
/// a token nibble plus zero or more bytes. An extended length always ends with
/// a byte below 255, so an exact multiple of 255 requires a final zero byte.
fn encodedLengthBytes(encoded_len: usize) usize {
    if (encoded_len < 15) return 0;
    return (encoded_len - 15) / 255 + 1;
}

/// Write the portion of a length which did not fit in the token nibble.
///
/// Each 255 byte means "add 255 and continue". The final byte is always less
/// than 255 and may be zero.
fn writeLength(output: []u8, op: *usize, length_: usize) void {
    var length = length_;
    while (length >= 255) {
        output[op.*] = 255;
        op.* += 1;
        length -= 255;
    }
    output[op.*] = @intCast(length);
    op.* += 1;
}

/// Decode a length from its token nibble and any following extension bytes.
/// `ip` is advanced past every consumed extension byte.
fn decodeLength(
    input: []const u8,
    ip: *usize,
    nibble: u8,
) DecompressError!usize {
    var length: usize = nibble;
    if (nibble != 15) return length;

    while (true) {
        if (ip.* >= input.len) return error.TruncatedInput;
        const value = input[ip.*];
        ip.* += 1;
        length = std.math.add(usize, length, value) catch
            return error.TruncatedInput;
        if (value != 255) return length;
    }
}

/// Read the four-byte sequence used for match finding. Callers only use this
/// where at least four input bytes remain.
inline fn readU32(input: []const u8, pos: usize) u32 {
    return std.mem.readInt(u32, input[pos..][0..4], .little);
}

/// Map a four-byte input sequence to its scratch-table slot.
inline fn hashSequence(sequence: u32) usize {
    return @intCast((sequence *% hash_multiplier) >> (32 - hash_log));
}

/// Shared round-trip assertion used by the corpus-style tests below.
fn expectRoundTrip(input: []const u8) !void {
    const testing = std.testing;
    const bound = try compressBound(input.len);
    const encoded = try testing.allocator.alloc(u8, bound);
    defer testing.allocator.free(encoded);
    const decoded = try testing.allocator.alloc(u8, input.len);
    defer testing.allocator.free(decoded);

    var table: HashTable = undefined;
    const encoded_len = try compress(input, encoded, &table);
    try testing.expectEqual(input.len, try decompress(
        encoded[0..encoded_len],
        decoded,
    ));
    try testing.expectEqualSlices(u8, input, decoded);
}

test "compressBound" {
    const testing = std.testing;
    try testing.expectEqual(@as(usize, 16), try compressBound(0));
    try testing.expectEqual(@as(usize, 272), try compressBound(255));
    try testing.expectError(error.InputTooLarge, compressBound(max_input_size + 1));
}

test "literal-only compatibility vectors" {
    const testing = std.testing;

    var empty: [0]u8 = .{};
    try testing.expectEqual(@as(usize, 0), try decompress(&.{0}, &empty));

    var hello: [5]u8 = undefined;
    try testing.expectEqual(@as(usize, 5), try decompress(
        &.{ 0x50, 'h', 'e', 'l', 'l', 'o' },
        &hello,
    ));
    try testing.expectEqualStrings("hello", &hello);

    var fifteen: [15]u8 = undefined;
    var encoded: [17]u8 = undefined;
    encoded[0] = 0xF0;
    encoded[1] = 0;
    @memset(encoded[2..], 'x');
    _ = try decompress(&encoded, &fifteen);
    try testing.expect(std.mem.allEqual(u8, &fifteen, 'x'));
}

test "overlapping match compatibility vector" {
    const testing = std.testing;
    // One literal 'a', followed by a four-byte match at distance one.
    var output: [5]u8 = undefined;
    try testing.expectEqual(@as(usize, 5), try decompress(
        &.{ 0x10, 'a', 0x01, 0x00 },
        &output,
    ));
    try testing.expectEqualStrings("aaaaa", &output);
}

test "extended overlapping match compatibility vector" {
    const testing = std.testing;
    // One literal followed by a 274-byte match. The match extension is
    // encoded as 255 + 0 after the low token nibble's initial 15 bytes.
    var output: [275]u8 = undefined;
    try testing.expectEqual(@as(usize, output.len), try decompress(
        &.{ 0x1F, 'a', 0x01, 0x00, 0xFF, 0x00 },
        &output,
    ));
    try testing.expect(std.mem.allEqual(u8, &output, 'a'));
}

test "maximum match offset compatibility vector" {
    const testing = std.testing;
    const literal_len = std.math.maxInt(u16);
    const extension_len = (literal_len - 15) / 255 + 1;
    const encoded = try testing.allocator.alloc(
        u8,
        1 + extension_len + literal_len + 2,
    );
    defer testing.allocator.free(encoded);
    const output = try testing.allocator.alloc(u8, literal_len + min_match);
    defer testing.allocator.free(output);

    var op: usize = 0;
    encoded[op] = 0xF0;
    op += 1;
    writeLength(encoded, &op, literal_len - 15);
    for (encoded[op..][0..literal_len], 0..) |*byte, i|
        byte.* = @truncate(i);
    op += literal_len;
    std.mem.writeInt(u16, encoded[op..][0..2], std.math.maxInt(u16), .little);
    op += 2;

    try testing.expectEqual(encoded.len, op);
    try testing.expectEqual(output.len, try decompress(encoded, output));
    try testing.expectEqualSlices(u8, encoded[1 + extension_len ..][0..4], output[literal_len..]);
}

test "round trips boundary-sized inputs" {
    const testing = std.testing;
    const lengths = [_]usize{
        0,   1,      3,      4,      5,   12,  15,  16,  19,
        20,  254,    255,    256,    269, 270, 271, 510, 511,
        512, 65_535, 65_536, 65_537,
    };

    for (lengths) |len| {
        const buf = try testing.allocator.alloc(u8, len);
        defer testing.allocator.free(buf);
        for (buf, 0..) |*byte, i| byte.* = @truncate(i *% 31);
        try expectRoundTrip(buf);
    }
}

test "round trips compressible page-sized inputs" {
    const testing = std.testing;
    const page_len = 400 * 1024;

    const zeros = try testing.allocator.alloc(u8, page_len);
    defer testing.allocator.free(zeros);
    @memset(zeros, 0);
    try expectRoundTrip(zeros);

    const structured = try testing.allocator.alloc(u8, page_len);
    defer testing.allocator.free(structured);
    @memset(structured, 0);
    for (0..page_len / 8) |i| {
        structured[i * 8] = @truncate(' ' + i % 95);
        structured[i * 8 + 4] = @truncate((i / 80) % 16);
    }
    try expectRoundTrip(structured);
}

test "round trips deterministic random inputs" {
    const testing = std.testing;
    var prng = std.Random.DefaultPrng.init(0x4C5A_3401);
    const random = prng.random();

    for (0..256) |_| {
        const len = random.uintLessThan(usize, 32 * 1024);
        const input = try testing.allocator.alloc(u8, len);
        defer testing.allocator.free(input);
        random.bytes(input);
        try expectRoundTrip(input);
    }
}

test "compress reports short output" {
    const testing = std.testing;
    const input = "a terminal page needs enough output space";
    var table: HashTable = undefined;
    var output: [4]u8 = undefined;
    try testing.expectError(
        error.OutputTooSmall,
        compress(input, &output, &table),
    );
}

test "decompress rejects malformed blocks" {
    const testing = std.testing;
    var output: [32]u8 = undefined;

    try testing.expectError(error.TruncatedInput, decompress(&.{0xF0}, &output));
    try testing.expectError(error.TruncatedInput, decompress(&.{ 0x10, 'a', 1 }, output[0..5]));
    try testing.expectError(error.InvalidOffset, decompress(&.{ 0x10, 'a', 0, 0 }, output[0..5]));
    try testing.expectError(error.InvalidOffset, decompress(&.{ 0x10, 'a', 2, 0 }, output[0..5]));
    try testing.expectError(error.OutputTooSmall, decompress(
        &.{ 0x10, 'a', 1, 0 },
        output[0..4],
    ));
    try testing.expectError(error.OutputSizeMismatch, decompress(&.{0}, output[0..1]));
}

test "fuzz decompressor safety" {
    return std.testing.fuzz({}, fuzzDecompress, .{});
}

fn fuzzDecompress(_: void, input: []const u8) !void {
    var output: [4096]u8 = undefined;
    _ = decompress(input, &output) catch {};
}
