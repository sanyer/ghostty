const Utf8 = @This();

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const synthetic = @import("../main.zig");

const log = std.log.scoped(.@"terminal-stream-bench");

pub const Options = struct {};

/// Create a new terminal stream handler for the given arguments.
pub fn create(
    alloc: Allocator,
    _: Options,
) !*Utf8 {
    const ptr = try alloc.create(Utf8);
    errdefer alloc.destroy(ptr);
    return ptr;
}

pub fn destroy(self: *Utf8, alloc: Allocator) void {
    alloc.destroy(self);
}

pub fn run(self: *Utf8, writer: *std.Io.Writer, rand: std.Random) !void {
    _ = self;

    var gen: synthetic.Utf8 = .{
        .rand = rand,
    };

    while (true) {
        gen.next(writer, 1024) catch |err| {
            const Error = error{ WriteFailed, BrokenPipe } || @TypeOf(err);
            switch (@as(Error, err)) {
                error.BrokenPipe => return, // stdout closed
                error.WriteFailed => return, // fixed buffer full
                else => return err,
            }
        };
    }
}

test Utf8 {
    const testing = std.testing;
    const alloc = testing.allocator;

    const impl: *Utf8 = try .create(alloc, .{});
    defer impl.destroy(alloc);

    var prng = std.Random.DefaultPrng.init(1);
    const rand = prng.random();

    var buf: [1024]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try impl.run(&writer, rand);
}
