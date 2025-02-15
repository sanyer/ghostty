const std = @import("std");
const builtin = @import("builtin");
const Action = @import("action.zig").Action;
const args = @import("args.zig");
const Config = @import("../config/Config.zig");

pub const Options = struct {
    pub fn deinit(self: Options) void {
        _ = self;
    }

    /// Enables "-h" and "--help" to work.
    pub fn help(self: Options) !void {
        _ = self;
        return Action.help_error;
    }
};

/// The `list-mac-app-icons` command is used to list all available macOS app icons
/// that can be used with the `macos-icon` configuration option in Ghostty.
pub fn run(alloc: std.mem.Allocator) !u8 {
    if (comptime !builtin.target.isDarwin()) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("This command is only supported on macOS\n");
        return 1;
    }
    const kitty = @import("../terminal/kitty/graphics_command.zig");
    const image = @import("../terminal/kitty/graphics_image.zig");

    // Check if we can use kitty graphics protocol
    const stdout_file = std.io.getStdOut();
    const stdout_handle = stdout_file.handle;
    const is_tty = std.os.isatty(stdout_handle);
    if (!is_tty) {
        // If not a terminal, continue with text-only output
        return run_text_only(alloc);
    }

    // Try to detect if kitty graphics protocol is supported
    // We could try sending a query command and checking response
    var cmd = kitty.Command{
        .control = .query,
        .quiet = .failures,
    };

    // If query fails, fall back to text-only
    const resp = try cmd.write(alloc, stdout_file.writer());
    if (resp) |r| {
        if (!r.ok()) {
            return run_text_only(alloc);
        }
    } else {
        return run_text_only(alloc);
    }

    // If we get here, kitty graphics protocol is supported
    const stdout = stdout_file.writer();

    inline for (@typeInfo(Config.MacAppIcon).Enum.fields) |field| {
        const path = try std.fmt.allocPrint(
            alloc,
            "macos/Assets.xcassets/Alternate Icons/{s}.imageset/macOS-AppIcon-1024px.png",
            .{field.name}
        );
        defer alloc.free(path);

        // Load and display the image
        var img = try image.Image.initPath(alloc, path);
        defer img.deinit();

        // Create a transmission command
        var trans_cmd = kitty.Command{
            .control = .transmit_and_display,
            .transmission = .{
                .format = .png,
                .data = img.data.items,
            },
            .display = .{
                .placement = .{ .x = 0, .y = 0 },
            },
            .quiet = .failures,
        };

        // Write the image
        _ = try trans_cmd.write(alloc, stdout);

        // Print the name
        try stdout.print("{s}\n", .{field.name});
    }

    return 0;
}

fn run_text_only(alloc: std.mem.Allocator) !u8 {

    var opts: Options = .{};
    defer opts.deinit();

    {
        var iter = try args.argsIterator(alloc);
        defer iter.deinit();
        try args.parse(Options, alloc, &opts, &iter);
    }

    const stdout = std.io.getStdOut().writer();

    inline for (@typeInfo(Config.MacAppIcon).Enum.fields) |field| {
        try stdout.print("{s}\n", .{field.name});
    }

    return 0;
}
