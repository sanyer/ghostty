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

        else => comptime unreachable,
    }
}
