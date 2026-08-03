//! Fastprint has fast printing routines that are significantly
//! faster than going through std.fmt.

const std = @import("std");

/// Print a decimal type T. The buffer is expected to be large enough so if
/// necessary use comptime with a buffer-too-large to determine your
/// max size needed. Returns the length written.
pub fn printDecimal(comptime T: type, buf: []u8, v: u8) usize {
    // Note this only supports types as we need them.
    switch (T) {
        u8 => {
            if (v >= 100) {
                buf[0] = '0' + v / 100;
                buf[1..3].* = std.fmt.digits2(v % 100);
                return 3;
            }
            if (v >= 10) {
                buf[0..2].* = std.fmt.digits2(v);
                return 2;
            }
            buf[0] = '0' + v;
            return 1;
        },

        // This can probably be generalized...
        u21 => {
            // Maximum u21 is 2097151: at most 7 digits.
            var tmp: [7]u8 = undefined;
            var val: u32 = v;
            var i: usize = tmp.len;
            while (true) {
                i -= 1;
                tmp[i] = '0' + @as(u8, @intCast(val % 10));
                val /= 10;
                if (val == 0) break;
            }
            const n = tmp.len - i;
            @memcpy(buf[0..n], tmp[i..]);
            return n;
        },

        else => comptime unreachable,
    }
}
