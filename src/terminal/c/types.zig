//! Comptime-generated ABI metadata for the public libghostty-vt C types.
//!
//! The manifest is embedded in the library and returned by
//! `ghostty_type_json`. It is intended for FFI consumers that cannot use the
//! C headers directly, most notably WebAssembly hosts. Its format is defined
//! by `types.schema.json`.
const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("terminal_options");
const lib = @import("../lib.zig");

const color = @import("../color.zig");
const clipboard = @import("../clipboard.zig");
const device_status = @import("../device_status.zig");
const focus_pkg = @import("../focus.zig");
const formatter_pkg = @import("../formatter.zig");
const modes_pkg = @import("../modes.zig");
const mouse_pkg = @import("../mouse.zig");
const point = @import("../point.zig");
const Selection = @import("../Selection.zig");
const sgr = @import("../sgr.zig");

const input_config = @import("../../input/config.zig");
const input_key = @import("../../input/key.zig");
const input_mouse = @import("../../input/mouse.zig");

const build_info = @import("build_info.zig");
const cell = @import("cell.zig");
const color_c = @import("color.zig");
const formatter = @import("formatter.zig");
const grid_ref = @import("grid_ref.zig");
const io = @import("io.zig");
const key_encode = @import("key_encode.zig");
const kitty_graphics = @import("kitty_graphics.zig");
const mouse_encode = @import("mouse_encode.zig");
const mouse_event = @import("mouse_event.zig");
const osc = @import("osc.zig");
const render = @import("render.zig");
const result = @import("result.zig");
const row = @import("row.zig");
const selection = @import("selection.zig");
const selection_gesture = @import("selection_gesture.zig");
const size_report = @import("size_report.zig");
const snapshot = @import("snapshot.zig");
const style = @import("style.zig");
const sys = @import("sys.zig");
const terminal = @import("terminal.zig");

/// C: GhosttySurfacePosition
pub const SurfacePosition = extern struct {
    x: f64,
    y: f64,
};

/// C: GhosttyCodepoints
pub const Codepoints = extern struct {
    ptr: ?[*]const u32 = null,
    len: usize = 0,
};

const TypeDecl = struct {
    name: []const u8,
    T: type,
    kind: Kind,
    prefix: []const u8 = "",
    sentinel_suffix: []const u8 = "MAX_VALUE",
    alias_type: []const u8 = "",
    tagged_union: ?TaggedUnion = null,
    union_field_names_T: ?type = null,

    const Kind = enum {
        @"struct",
        @"union",
        @"enum",
        alias,
        @"opaque",
    };

    const TaggedUnion = struct {
        tag_field: []const u8,
        value_field: []const u8,
        arm_source: ArmSource,

        const ArmSource = enum {
            fields,
            generated,
        };
    };

    fn initStruct(comptime name: []const u8, comptime T: type) TypeDecl {
        return .{ .name = name, .T = T, .kind = .@"struct" };
    }

    fn initTaggedStruct(
        comptime name: []const u8,
        comptime T: type,
        comptime tag_field: []const u8,
        comptime value_field: []const u8,
        comptime arm_source: TaggedUnion.ArmSource,
    ) TypeDecl {
        return .{
            .name = name,
            .T = T,
            .kind = .@"struct",
            .tagged_union = .{
                .tag_field = tag_field,
                .value_field = value_field,
                .arm_source = arm_source,
            },
        };
    }

    fn initUnion(
        comptime name: []const u8,
        comptime T: type,
        comptime field_names_T: ?type,
    ) TypeDecl {
        return .{
            .name = name,
            .T = T,
            .kind = .@"union",
            .union_field_names_T = field_names_T,
        };
    }

    fn initEnum(
        comptime name: []const u8,
        comptime T: type,
        comptime prefix: []const u8,
    ) TypeDecl {
        return .{ .name = name, .T = T, .kind = .@"enum", .prefix = prefix };
    }

    fn initEnumSentinel(
        comptime name: []const u8,
        comptime T: type,
        comptime prefix: []const u8,
        comptime sentinel_suffix: []const u8,
    ) TypeDecl {
        return .{
            .name = name,
            .T = T,
            .kind = .@"enum",
            .prefix = prefix,
            .sentinel_suffix = sentinel_suffix,
        };
    }

    fn initAlias(
        comptime name: []const u8,
        comptime T: type,
        comptime alias_type: []const u8,
    ) TypeDecl {
        return .{ .name = name, .T = T, .kind = .alias, .alias_type = alias_type };
    }

    fn initOpaque(comptime name: []const u8) TypeDecl {
        return .{ .name = name, .T = *anyopaque, .kind = .@"opaque" };
    }
};

/// Public C types. Names and enum prefixes are intentionally explicit because
/// Zig identifiers are not the C API contract.
const type_decls = [_]TypeDecl{
    .initStruct("GhosttyAllocator", lib.alloc.Allocator),
    .initStruct("GhosttyAllocatorVtable", lib.alloc.VTable),
    .initStruct("GhosttyBuffer", lib.Buffer),
    .initStruct("GhosttyCellsView", cell.CellsView),
    .initStruct("GhosttyClipboardContent", terminal.ClipboardContent),
    .initStruct("GhosttyClipboardWrite", terminal.ClipboardWrite),
    .initStruct("GhosttyCodepoints", Codepoints),
    .initStruct("GhosttyColorPaletteMask", color_c.PaletteMask),
    .initStruct("GhosttyColorRgb", color.RGB.C),
    .initStruct("GhosttyColorX11Entry", color_c.X11Entry),
    .initStruct("GhosttyDeviceAttributes", terminal.DeviceAttributes),
    .initStruct("GhosttyDeviceAttributesPrimary", terminal.DeviceAttributes.Primary),
    .initStruct("GhosttyDeviceAttributesSecondary", terminal.DeviceAttributes.Secondary),
    .initStruct("GhosttyDeviceAttributesTertiary", terminal.DeviceAttributes.Tertiary),
    .initStruct("GhosttyFormatterScreenExtra", formatter.ScreenOptions.Extra),
    .initStruct("GhosttyFormatterTerminalExtra", formatter.TerminalOptions.Extra),
    .initStruct("GhosttyFormatterTerminalOptions", formatter.TerminalOptions),
    .initStruct("GhosttyGridRef", grid_ref.CGridRef),
    .initStruct("GhosttyKittyGraphicsPlacementRenderInfo", kitty_graphics.PlacementRenderInfo),
    .initStruct("GhosttyMouseEncoderSize", mouse_encode.Size),
    .initStruct("GhosttyMousePosition", mouse_event.Position),
    .initTaggedStruct("GhosttyPoint", point.Point.C, "tag", "value", .generated),
    .initStruct("GhosttyPointCoordinate", point.Coordinate),
    .initUnion("GhosttyPointValue", point.Point.CValue, point.Point.C),
    .initStruct("GhosttyReader", io.Reader),
    .initStruct("GhosttyRenderStateColors", render.Colors),
    .initStruct("GhosttyRenderStateCursor", render.Cursor),
    .initStruct("GhosttyRenderStateRowSelection", render.RowSelection),
    .initStruct("GhosttySelection", selection.CSelection),
    .initStruct("GhosttySelectionGestureBehaviors", selection_gesture.Behaviors),
    .initStruct("GhosttySelectionGestureGeometry", selection_gesture.Geometry),
    .initTaggedStruct("GhosttySgrAttribute", sgr.Attribute.C, "tag", "value", .generated),
    .initStruct("GhosttySgrUnknown", sgr.Attribute.Unknown.C),
    .initUnion("GhosttySgrAttributeValue", sgr.Attribute.CValue, sgr.Attribute.C),
    .initStruct("GhosttySizeReportSize", size_report.Size),
    .initStruct("GhosttyString", lib.String),
    .initStruct("GhosttySurfacePosition", SurfacePosition),
    .initStruct("GhosttyStyle", style.Style),
    .initTaggedStruct("GhosttyStyleColor", style.Color, "tag", "value", .fields),
    .initUnion("GhosttyStyleColorValue", style.ColorValue, null),
    .initStruct("GhosttySysImage", sys.Image),
    .initStruct("GhosttyTerminalDesktopNotification", terminal.DesktopNotification),
    .initStruct("GhosttyTerminalModeConfig", terminal.ModeConfig),
    .initStruct("GhosttyTerminalProgressReport", terminal.ProgressReport),
    .initStruct("GhosttyTerminalScrollbar", terminal.TerminalScrollbar),
    .initTaggedStruct("GhosttyTerminalScrollViewport", terminal.ScrollViewport, "tag", "value", .generated),
    .initUnion(
        "GhosttyTerminalScrollViewportValue",
        terminal.ZigTerminal.ScrollViewport.CValue,
        terminal.ZigTerminal.ScrollViewport.C,
    ),
    .initStruct("GhosttyTerminalSelectLineOptions", selection.SelectLineOptions),
    .initStruct("GhosttyTerminalSelectWordBetweenOptions", selection.SelectWordBetweenOptions),
    .initStruct("GhosttyTerminalSelectWordOptions", selection.SelectWordOptions),
    .initStruct("GhosttyTerminalSelectionFormatOptions", selection.FormatOptions),
    .initTaggedStruct("GhosttyTerminalUnknownSequence", terminal.UnknownSequence.C, "tag", "value", .generated),
    .initStruct("GhosttyTerminalUnknownStringSequence", terminal.UnknownStringSequence),
    .initUnion(
        "GhosttyTerminalUnknownSequenceValue",
        terminal.UnknownSequence.CValue,
        terminal.UnknownSequence.C,
    ),
    .initStruct("GhosttyWriter", io.Writer),

    .initEnumSentinel("GhosttyResult", result.Result, "GHOSTTY_", "RESULT_MAX_VALUE"),
    .initEnum("GhosttyBuildInfo", build_info.BuildInfo, "GHOSTTY_BUILD_INFO_"),
    .initEnumSentinel("GhosttyOptimizeMode", build_info.OptimizeMode, "GHOSTTY_OPTIMIZE_", "MODE_MAX_VALUE"),
    .initEnumSentinel("GhosttyCellContentTag", cell.ContentTag, "GHOSTTY_CELL_CONTENT_", "TAG_MAX_VALUE"),
    .initEnum("GhosttyCellData", cell.CellData, "GHOSTTY_CELL_DATA_"),
    .initEnum("GhosttyCellSemanticContent", cell.SemanticContent, "GHOSTTY_CELL_SEMANTIC_"),
    .initEnum("GhosttyCellWide", cell.Wide, "GHOSTTY_CELL_WIDE_"),
    .initEnum("GhosttyClipboardLocation", clipboard.Location, "GHOSTTY_CLIPBOARD_LOCATION_"),
    .initEnum("GhosttyClipboardWriteResult", clipboard.WriteResult, "GHOSTTY_CLIPBOARD_WRITE_RESULT_"),
    .initEnum("GhosttyColorScheme", device_status.ColorScheme, "GHOSTTY_COLOR_SCHEME_"),
    .initEnum("GhosttyFocusEvent", focus_pkg.Event, "GHOSTTY_FOCUS_"),
    .initEnum("GhosttyFormatterFormat", formatter_pkg.Format, "GHOSTTY_FORMATTER_FORMAT_"),
    .initEnum("GhosttyKey", input_key.Key, "GHOSTTY_KEY_"),
    .initEnum("GhosttyKeyAction", input_key.Action, "GHOSTTY_KEY_ACTION_"),
    .initEnum("GhosttyKeyEncoderOption", key_encode.Option, "GHOSTTY_KEY_ENCODER_OPT_"),
    .initEnum("GhosttyKittyGraphicsData", kitty_graphics.Data, "GHOSTTY_KITTY_GRAPHICS_DATA_"),
    .initEnum("GhosttyKittyGraphicsImageData", kitty_graphics.ImageData, "GHOSTTY_KITTY_IMAGE_DATA_"),
    .initEnum("GhosttyKittyGraphicsPlacementData", kitty_graphics.PlacementData, "GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_"),
    .initEnum("GhosttyKittyGraphicsPlacementIteratorOption", kitty_graphics.PlacementIteratorOption, "GHOSTTY_KITTY_GRAPHICS_PLACEMENT_ITERATOR_OPTION_"),
    .initEnum("GhosttyKittyImageCompression", kitty_graphics.ImageCompression, "GHOSTTY_KITTY_IMAGE_COMPRESSION_"),
    .initEnum("GhosttyKittyImageFormat", kitty_graphics.ImageFormat, "GHOSTTY_KITTY_IMAGE_FORMAT_"),
    .initEnum("GhosttyKittyPlacementLayer", kitty_graphics.PlacementLayer, "GHOSTTY_KITTY_PLACEMENT_LAYER_"),
    .initEnum("GhosttyModeReportState", modes_pkg.Report.State, "GHOSTTY_MODE_REPORT_"),
    .initEnum("GhosttyMouseAction", input_mouse.Action, "GHOSTTY_MOUSE_ACTION_"),
    .initEnum("GhosttyMouseButton", input_mouse.Button, "GHOSTTY_MOUSE_BUTTON_"),
    .initEnum("GhosttyMouseEncoderOption", mouse_encode.Option, "GHOSTTY_MOUSE_ENCODER_OPT_"),
    .initEnum("GhosttyMouseFormat", mouse_pkg.Format, "GHOSTTY_MOUSE_FORMAT_"),
    .initEnum("GhosttyMouseTrackingMode", mouse_pkg.Event, "GHOSTTY_MOUSE_TRACKING_"),
    .initEnum("GhosttyOptionAsAlt", input_config.OptionAsAlt, "GHOSTTY_OPTION_AS_ALT_"),
    .initEnum("GhosttyOscCommandData", osc.CommandData, "GHOSTTY_OSC_DATA_"),
    .initEnumSentinel(
        "GhosttyOscCommandType",
        osc.CommandType,
        "GHOSTTY_OSC_COMMAND_",
        "TYPE_MAX_VALUE",
    ),
    .initEnum("GhosttyPointTag", point.Tag, "GHOSTTY_POINT_TAG_"),
    .initEnum("GhosttyRenderStateCursorVisualStyle", render.CursorVisualStyle, "GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_"),
    .initEnum("GhosttyRenderStateData", render.Data, "GHOSTTY_RENDER_STATE_DATA_"),
    .initEnum("GhosttyRenderStateDirty", render.Dirty, "GHOSTTY_RENDER_STATE_DIRTY_"),
    .initEnum("GhosttyRenderStateOption", render.SetOption, "GHOSTTY_RENDER_STATE_OPTION_"),
    .initEnum("GhosttyRenderStateRowCellsData", render.RowCellsData, "GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_"),
    .initEnum("GhosttyRenderStateRowData", render.RowData, "GHOSTTY_RENDER_STATE_ROW_DATA_"),
    .initEnum("GhosttyRenderStateRowOption", render.RowOption, "GHOSTTY_RENDER_STATE_ROW_OPTION_"),
    .initEnum("GhosttyRowData", row.RowData, "GHOSTTY_ROW_DATA_"),
    .initEnum("GhosttyRowSemanticPrompt", row.SemanticPrompt, "GHOSTTY_ROW_SEMANTIC_"),
    .initEnum("GhosttySelectionAdjust", Selection.Adjustment, "GHOSTTY_SELECTION_ADJUST_"),
    .initEnum("GhosttySelectionGestureAutoscroll", selection_gesture.Autoscroll, "GHOSTTY_SELECTION_GESTURE_AUTOSCROLL_"),
    .initEnum("GhosttySelectionGestureBehavior", selection_gesture.Behavior, "GHOSTTY_SELECTION_GESTURE_BEHAVIOR_"),
    .initEnum("GhosttySelectionGestureData", selection_gesture.Data, "GHOSTTY_SELECTION_GESTURE_DATA_"),
    .initEnum("GhosttySelectionGestureEventOption", selection_gesture.EventOption, "GHOSTTY_SELECTION_GESTURE_EVENT_OPT_"),
    .initEnum("GhosttySelectionGestureEventType", selection_gesture.EventType, "GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_"),
    .initEnum("GhosttySelectionOrder", Selection.Order, "GHOSTTY_SELECTION_ORDER_"),
    .initEnum("GhosttySgrAttributeTag", sgr.Attribute.Tag, "GHOSTTY_SGR_ATTR_"),
    .initEnum("GhosttySgrUnderline", sgr.Attribute.Underline, "GHOSTTY_SGR_UNDERLINE_"),
    .initEnumSentinel("GhosttySizeReportStyle", size_report.Style, "GHOSTTY_SIZE_REPORT_", "STYLE_MAX_VALUE"),
    .initEnum("GhosttySnapshotDecoderData", snapshot.DecoderData, "GHOSTTY_SNAPSHOT_DECODER_DATA_"),
    .initEnum("GhosttySnapshotDecoderOption", snapshot.DecoderOption, "GHOSTTY_SNAPSHOT_DECODER_OPT_"),
    .initEnumSentinel("GhosttyStyleColorTag", style.ColorTag, "GHOSTTY_STYLE_COLOR_", "TAG_MAX_VALUE"),
    .initEnum("GhosttySysLogLevel", sys.LogLevel, "GHOSTTY_SYS_LOG_LEVEL_"),
    .initEnum("GhosttySysOption", sys.Option, "GHOSTTY_SYS_OPT_"),
    .initEnum("GhosttyTerminalCompressionMode", terminal.CompressionMode, "GHOSTTY_TERMINAL_COMPRESSION_MODE_"),
    .initEnum("GhosttyTerminalCompressionResult", terminal.CompressionResult, "GHOSTTY_TERMINAL_COMPRESSION_RESULT_"),
    .initEnum("GhosttyTerminalCursorStyle", terminal.TerminalCursorStyle, "GHOSTTY_TERMINAL_CURSOR_STYLE_"),
    .initEnum("GhosttyTerminalData", terminal.TerminalData, "GHOSTTY_TERMINAL_DATA_"),
    .initEnum("GhosttyTerminalOption", terminal.Option, "GHOSTTY_TERMINAL_OPT_"),
    .initEnum("GhosttyTerminalProgressState", terminal.ProgressState, "GHOSTTY_TERMINAL_PROGRESS_STATE_"),
    .initEnum("GhosttyTerminalScreen", terminal.TerminalScreen, "GHOSTTY_TERMINAL_SCREEN_"),
    .initEnum("GhosttyTerminalScrollViewportTag", terminal.ZigTerminal.ScrollViewport.Tag, "GHOSTTY_SCROLL_VIEWPORT_"),
    .initEnum("GhosttyTerminalUnknownSequenceTag", terminal.UnknownSequence.Tag, "GHOSTTY_TERMINAL_UNKNOWN_SEQUENCE_"),

    .initAlias("GhosttyCell", u64, "u64"),
    .initAlias("GhosttyColorPaletteIndex", u8, "u8"),
    .initAlias("GhosttyKittyKeyFlags", u8, "u8"),
    .initAlias("GhosttyMode", u16, "u16"),
    .initAlias("GhosttyMods", u16, "u16"),
    .initAlias("GhosttyRow", u64, "u64"),
    .initAlias("GhosttyStyleId", u16, "u16"),

    .initOpaque("GhosttyFormatter"),
    .initOpaque("GhosttyKeyEncoder"),
    .initOpaque("GhosttyKeyEvent"),
    .initOpaque("GhosttyKittyGraphics"),
    .initOpaque("GhosttyKittyGraphicsImage"),
    .initOpaque("GhosttyKittyGraphicsPlacementIterator"),
    .initOpaque("GhosttyMouseEncoder"),
    .initOpaque("GhosttyMouseEvent"),
    .initOpaque("GhosttyOscCommand"),
    .initOpaque("GhosttyOscParser"),
    .initOpaque("GhosttyRenderState"),
    .initOpaque("GhosttyRenderStateRowCells"),
    .initOpaque("GhosttyRenderStateRowIterator"),
    .initOpaque("GhosttySelectionGesture"),
    .initOpaque("GhosttySelectionGestureEvent"),
    .initOpaque("GhosttySgrParser"),
    .initOpaque("GhosttySnapshotDecoder"),
    .initOpaque("GhosttyTerminal"),
    .initOpaque("GhosttyTrackedGridRef"),
};

comptime {
    @setEvalBranchQuota(100_000);
    for (type_decls, 0..) |decl, i| {
        for (type_decls[0..i]) |previous| {
            if (std.mem.eql(u8, decl.name, previous.name))
                @compileError("duplicate public ABI type: " ++ decl.name);
        }
    }
}

pub const json: [:0]const u8 = json: {
    @setEvalBranchQuota(1_000_000);
    var counter: std.Io.Writer.Discarding = .init(&.{});
    Json.writeAll(&counter.writer) catch unreachable;

    var buf: [counter.count:0]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    Json.writeAll(&writer) catch unreachable;
    const final = buf;
    break :json final[0..writer.end :0];
};

pub fn get_json() callconv(lib.calling_conv) [*:0]const u8 {
    return json.ptr;
}

const Json = struct {
    fn writeAll(writer: *std.Io.Writer) std.Io.Writer.Error!void {
        var jws: std.json.Stringify = .{ .writer = writer };
        try jws.beginObject();
        try jws.objectField("schema");
        try jws.write(1);

        try jws.objectField("abi");
        try jws.beginObject();
        try jws.objectField("target");
        try jws.write(@tagName(builtin.target.cpu.arch));
        try jws.objectField("os");
        try jws.write(@tagName(builtin.target.os.tag));
        try jws.objectField("environment");
        try jws.write(@tagName(builtin.target.abi));
        try jws.objectField("pointer_size");
        try jws.write(@sizeOf(*anyopaque));
        try jws.objectField("usize_size");
        try jws.write(@sizeOf(usize));
        try jws.objectField("endian");
        try jws.write(@tagName(builtin.target.cpu.arch.endian()));
        try jws.endObject();

        try jws.objectField("library_version");
        try jws.write(build_options.version_string);
        try jws.objectField("commit");
        if (build_options.version_build) |commit| try jws.write(commit) else try jws.write(null);
        try jws.objectField("dirty");
        try jws.write(null);

        try jws.objectField("types");
        try jws.beginObject();
        inline for (type_decls) |decl| {
            try jws.objectField(decl.name);
            try writeType(decl, &jws);
        }
        try jws.endObject();
        try jws.endObject();
    }

    fn writeType(comptime decl: TypeDecl, jws: *std.json.Stringify) std.Io.Writer.Error!void {
        try jws.beginObject();
        try jws.objectField("kind");
        try jws.write(@tagName(decl.kind));

        switch (decl.kind) {
            .@"struct", .@"union" => {
                try writeSizeAlign(decl.T, jws);
                try jws.objectField("fields");
                try jws.beginObject();
                if (decl.union_field_names_T != null) {
                    try writeMappedUnionFields(decl, jws);
                } else {
                    const fields = switch (decl.kind) {
                        .@"struct" => @typeInfo(decl.T).@"struct".fields,
                        .@"union" => @typeInfo(decl.T).@"union".fields,
                        else => unreachable,
                    };
                    inline for (fields) |field| {
                        try writeField(
                            decl,
                            field.name,
                            field.type,
                            if (decl.kind == .@"union") 0 else @offsetOf(decl.T, field.name),
                            jws,
                        );
                    }
                }
                try jws.endObject();
            },
            .@"enum" => {
                try writeSizeAlign(c_int, jws);
                try jws.objectField("underlying");
                try jws.write("i32");
                try jws.objectField("prefix");
                try jws.write(decl.prefix);
                try jws.objectField("values");
                try jws.beginObject();
                inline for (@typeInfo(decl.T).@"enum".fields) |field| {
                    try writeEnumObjectField(decl.name, field.name, jws);
                    try jws.write(field.value);
                }
                try jws.objectField(decl.sentinel_suffix);
                try jws.write(std.math.maxInt(c_int));
                try jws.endObject();
            },
            .alias => {
                try writeSizeAlign(decl.T, jws);
                try jws.objectField("type");
                try jws.write(decl.alias_type);
            },
            .@"opaque" => try writeSizeAlign(*anyopaque, jws),
        }
        try jws.endObject();
    }

    fn writeField(
        comptime decl: TypeDecl,
        comptime name: []const u8,
        comptime T: type,
        comptime offset: usize,
        jws: *std.json.Stringify,
    ) std.Io.Writer.Error!void {
        try jws.objectField(name);
        try jws.beginObject();
        try jws.objectField("offset");
        try jws.write(offset);
        try jws.objectField("size");
        try jws.write(@sizeOf(T));
        try writeFieldType(decl.name, name, T, jws);
        if (decl.tagged_union) |tagged| {
            if (std.mem.eql(u8, name, tagged.value_field)) {
                try jws.objectField("tag");
                try jws.write(tagged.tag_field);
                try writeTaggedArms(decl, tagged, jws);
            }
        }
        try jws.endObject();
    }

    fn writeMappedUnionFields(
        comptime decl: TypeDecl,
        jws: *std.json.Stringify,
    ) std.Io.Writer.Error!void {
        const FieldNames = decl.union_field_names_T.?;
        const Tag = @FieldType(FieldNames, "tag");
        const tag_fields = @typeInfo(Tag).@"enum".fields;

        inline for (tag_fields, 0..) |field, i| {
            const name = comptime FieldNames.cFieldRename(@field(Tag, field.name)) orelse continue;
            if (comptime mappedUnionFieldIsDuplicate(decl, i, name)) continue;
            try writeField(decl, name, @FieldType(decl.T, field.name), 0, jws);
        }

        if (@hasField(decl.T, "_padding"))
            try writeField(decl, "_padding", @FieldType(decl.T, "_padding"), 0, jws);
    }

    fn mappedUnionFieldIsDuplicate(
        comptime decl: TypeDecl,
        comptime index: usize,
        comptime name: []const u8,
    ) bool {
        const FieldNames = decl.union_field_names_T.?;
        const Tag = @FieldType(FieldNames, "tag");
        const tag_fields = @typeInfo(Tag).@"enum".fields;
        const T = @FieldType(decl.T, tag_fields[index].name);

        inline for (tag_fields[0..index]) |previous| {
            const previous_name = FieldNames.cFieldRename(@field(Tag, previous.name)) orelse continue;
            if (std.mem.eql(u8, previous_name, name)) {
                if (@FieldType(decl.T, previous.name) != T)
                    @compileError("tagged union metadata maps different field types to " ++ name);
                return true;
            }
        }

        return false;
    }

    fn writeSizeAlign(comptime T: type, jws: *std.json.Stringify) std.Io.Writer.Error!void {
        try jws.objectField("size");
        try jws.write(@sizeOf(T));
        try jws.objectField("align");
        try jws.write(@alignOf(T));
    }

    fn writeFieldType(
        comptime owner: []const u8,
        comptime field_name: []const u8,
        comptime T: type,
        jws: *std.json.Stringify,
    ) std.Io.Writer.Error!void {
        if (comptime std.mem.eql(u8, owner, "GhosttyCellsView") and
            std.mem.eql(u8, field_name, "ptr"))
        {
            try writePointerTypeNamed(T, true, "GhosttyCell", jws);
            return;
        }
        if (comptime std.mem.eql(u8, owner, "GhosttyGridRef") and
            std.mem.eql(u8, field_name, "node"))
        {
            try writePointerTypeNamed(T, true, "opaque", jws);
            return;
        }

        if (comptime fieldTypeOverride(owner, field_name)) |name| {
            try jws.objectField("type");
            try jws.write(name);
            return;
        }

        switch (@typeInfo(T)) {
            .array => |info| {
                try jws.objectField("type");
                try jws.write("array");
                try jws.objectField("elem");
                try jws.write(publicTypeName(info.child));
                try jws.objectField("count");
                try jws.write(info.len);
            },
            .optional => |info| try writePointerType(info.child, true, jws),
            .pointer => try writePointerType(T, false, jws),
            else => {
                try jws.objectField("type");
                try jws.write(publicTypeName(T));
            },
        }
    }

    fn writePointerType(
        comptime T: type,
        comptime nullable: bool,
        jws: *std.json.Stringify,
    ) std.Io.Writer.Error!void {
        const info = @typeInfo(T).pointer;
        try jws.objectField("type");
        try jws.write("pointer");
        try jws.objectField("elem");
        try jws.write(publicTypeName(info.child));
        try jws.objectField("const");
        try jws.write(info.is_const);
        if (nullable) {
            try jws.objectField("nullable");
            try jws.write(true);
        }
    }

    fn writePointerTypeNamed(
        comptime T: type,
        comptime nullable: bool,
        comptime elem: []const u8,
        jws: *std.json.Stringify,
    ) std.Io.Writer.Error!void {
        const pointer_type = switch (@typeInfo(T)) {
            .optional => |info| info.child,
            .pointer => T,
            else => unreachable,
        };
        const info = @typeInfo(pointer_type).pointer;
        try jws.objectField("type");
        try jws.write("pointer");
        try jws.objectField("elem");
        try jws.write(elem);
        try jws.objectField("const");
        try jws.write(info.is_const);
        if (nullable) {
            try jws.objectField("nullable");
            try jws.write(true);
        }
    }

    fn fieldTypeOverride(comptime owner: []const u8, comptime field_name: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, field_name, "value")) {
            if (std.mem.eql(u8, owner, "GhosttyPoint")) return "GhosttyPointValue";
            if (std.mem.eql(u8, owner, "GhosttySgrAttribute")) return "GhosttySgrAttributeValue";
            if (std.mem.eql(u8, owner, "GhosttyStyleColor")) return "GhosttyStyleColorValue";
            if (std.mem.eql(u8, owner, "GhosttyTerminalScrollViewport")) return "GhosttyTerminalScrollViewportValue";
            if (std.mem.eql(u8, owner, "GhosttyTerminalUnknownSequence")) return "GhosttyTerminalUnknownSequenceValue";
        }
        if (std.mem.eql(u8, owner, "GhosttyStyleColorValue") and std.mem.eql(u8, field_name, "palette"))
            return "GhosttyColorPaletteIndex";
        if (std.mem.eql(u8, owner, "GhosttySgrAttributeValue")) {
            if (std.mem.eql(u8, field_name, "underline")) return "GhosttySgrUnderline";
            if (std.mem.endsWith(u8, field_name, "_8") or std.mem.endsWith(u8, field_name, "_256"))
                return "GhosttyColorPaletteIndex";
        }
        if (std.mem.eql(u8, owner, "GhosttyTerminalModeConfig") and std.mem.eql(u8, field_name, "mode"))
            return "GhosttyMode";
        return null;
    }

    fn writeTaggedArms(
        comptime decl: TypeDecl,
        comptime tagged: TypeDecl.TaggedUnion,
        jws: *std.json.Stringify,
    ) std.Io.Writer.Error!void {
        const Tag = @FieldType(decl.T, tagged.tag_field);
        try jws.objectField("arms");
        try jws.beginObject();
        inline for (@typeInfo(Tag).@"enum".fields) |field| {
            try writeEnumObjectField(publicTypeName(Tag), field.name, jws);
            if (comptime taggedArm(decl, field.name)) |arm| try jws.write(arm) else try jws.write(null);
        }
        try jws.endObject();
    }

    fn taggedArm(comptime decl: TypeDecl, comptime tag_name: []const u8) ?[]const u8 {
        const tagged = decl.tagged_union.?;
        const Tag = @FieldType(decl.T, tagged.tag_field);
        if (tagged.arm_source == .generated)
            return decl.T.cFieldRename(@field(Tag, tag_name));

        const Value = @FieldType(decl.T, tagged.value_field);
        if (!@hasField(Value, tag_name)) return null;
        return if (@sizeOf(@FieldType(Value, tag_name)) == 0) null else tag_name;
    }

    fn publicTypeName(comptime T: type) []const u8 {
        inline for (type_decls) |decl| switch (decl.kind) {
            .@"struct", .@"union", .@"enum" => if (T == decl.T) return decl.name,
            .alias, .@"opaque" => {},
        };
        return switch (@typeInfo(T)) {
            .bool => "bool",
            .float => |info| switch (info.bits) {
                32 => "f32",
                64 => "f64",
                else => "opaque",
            },
            .int => |info| intName(info.signedness, info.bits),
            .comptime_int => "comptime_int",
            .void => "void",
            .@"opaque" => "opaque",
            .@"fn" => "function",
            .@"enum" => "enum",
            .@"struct" => "struct",
            .@"union" => "union",
            else => "opaque",
        };
    }

    fn intName(comptime signedness: std.builtin.Signedness, comptime bits: u16) []const u8 {
        return switch (signedness) {
            .signed => switch (bits) {
                8 => "i8",
                16 => "i16",
                32 => "i32",
                64 => "i64",
                else => "opaque",
            },
            .unsigned => switch (bits) {
                8 => "u8",
                16 => "u16",
                32 => "u32",
                64 => "u64",
                else => "opaque",
            },
        };
    }

    fn writeUpperObjectField(comptime name: []const u8, jws: *std.json.Stringify) std.Io.Writer.Error!void {
        var upper: [name.len]u8 = undefined;
        for (name, 0..) |c, i| upper[i] = std.ascii.toUpper(c);
        try jws.objectField(&upper);
    }

    fn writeEnumObjectField(
        comptime enum_name: []const u8,
        comptime zig_name: []const u8,
        jws: *std.json.Stringify,
    ) std.Io.Writer.Error!void {
        if (std.mem.eql(u8, enum_name, "GhosttyKey") and std.mem.startsWith(u8, zig_name, "key_"))
            return writeUpperObjectField(zig_name["key_".len..], jws);
        if (std.mem.eql(u8, enum_name, "GhosttySgrAttributeTag")) {
            if (std.mem.eql(u8, zig_name, "256_underline_color")) return jws.objectField("UNDERLINE_COLOR_256");
            if (std.mem.eql(u8, zig_name, "8_bg")) return jws.objectField("BG_8");
            if (std.mem.eql(u8, zig_name, "8_fg")) return jws.objectField("FG_8");
            if (std.mem.eql(u8, zig_name, "8_bright_bg")) return jws.objectField("BRIGHT_BG_8");
            if (std.mem.eql(u8, zig_name, "8_bright_fg")) return jws.objectField("BRIGHT_FG_8");
            if (std.mem.eql(u8, zig_name, "256_bg")) return jws.objectField("BG_256");
            if (std.mem.eql(u8, zig_name, "256_fg")) return jws.objectField("FG_256");
        }
        if (std.mem.eql(u8, enum_name, "GhosttyTerminalOption") and std.mem.eql(u8, zig_name, "size_cb"))
            return jws.objectField("SIZE");
        return writeUpperObjectField(zig_name, jws);
    }

    fn isBuiltinType(name: []const u8) bool {
        const builtins = [_][]const u8{
            "array", "bool",   "f32",     "f64", "function", "i8",  "i16", "i32",
            "i64",   "opaque", "pointer", "u8",  "u16",      "u32", "u64", "void",
        };
        for (builtins) |builtin_name| {
            if (std.mem.eql(u8, name, builtin_name)) return true;
        }
        return false;
    }
};

test "manifest parses and is versioned" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    try std.testing.expectEqual(@as(i64, 1), root.get("schema").?.integer);
    try std.testing.expect(root.contains("abi"));
    try std.testing.expect(root.contains("library_version"));
    const manifest_types = root.get("types").?.object;
    try std.testing.expectEqual(type_decls.len, manifest_types.count());
    inline for (type_decls) |decl| try std.testing.expect(manifest_types.contains(decl.name));

    const cursor_fields = manifest_types.get("GhosttyRenderStateCursor").?.object
        .get("fields").?.object;
    try std.testing.expect(cursor_fields.contains("size"));
    try std.testing.expect(cursor_fields.contains("viewport_has_value"));
    try std.testing.expect(cursor_fields.contains("viewport_x"));
    try std.testing.expect(cursor_fields.contains("viewport_y"));
    try std.testing.expect(cursor_fields.contains("wide_tail"));
    try std.testing.expect(cursor_fields.contains("visible"));
    try std.testing.expect(cursor_fields.contains("blinking"));
    try std.testing.expect(cursor_fields.contains("password_input"));
    try std.testing.expect(cursor_fields.contains("visual_style"));
}

test "manifest describes enums, arrays, and tagged unions" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    const manifest_types = parsed.value.object.get("types").?.object;

    const data = manifest_types.get("GhosttyRenderStateData").?.object;
    try std.testing.expectEqualStrings("enum", data.get("kind").?.string);
    try std.testing.expectEqual(@as(i64, @intFromEnum(render.Data.dirty)), data.get("values").?.object.get("DIRTY").?.integer);

    const colors = manifest_types.get("GhosttyRenderStateColors").?.object;
    const palette = colors.get("fields").?.object.get("palette").?.object;
    try std.testing.expectEqualStrings("array", palette.get("type").?.string);
    try std.testing.expectEqualStrings("GhosttyColorRgb", palette.get("elem").?.string);
    try std.testing.expectEqual(@as(i64, 256), palette.get("count").?.integer);

    const style_color = manifest_types.get("GhosttyStyleColor").?.object;
    const value = style_color.get("fields").?.object.get("value").?.object;
    try std.testing.expectEqualStrings("GhosttyStyleColorValue", value.get("type").?.string);
    try std.testing.expectEqualStrings("tag", value.get("tag").?.string);
    try std.testing.expectEqualStrings("palette", value.get("arms").?.object.get("PALETTE").?.string);
    try std.testing.expect(value.get("arms").?.object.get("NONE").? == .null);
}

test "manifest uses public enum names" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    const manifest_types = parsed.value.object.get("types").?.object;

    const cell_content = manifest_types.get("GhosttyCellContentTag").?.object.get("values").?.object;
    try std.testing.expect(cell_content.contains("TAG_MAX_VALUE"));
    try std.testing.expect(!cell_content.contains("MAX_VALUE"));

    const sgr_values = manifest_types.get("GhosttySgrAttributeTag").?.object.get("values").?.object;
    try std.testing.expectEqual(@as(i64, 9), sgr_values.get("UNDERLINE_COLOR_256").?.integer);
    try std.testing.expectEqual(@as(i64, 23), sgr_values.get("BG_8").?.integer);
    try std.testing.expect(!sgr_values.contains("256_UNDERLINE_COLOR"));

    const sgr_arms = manifest_types.get("GhosttySgrAttribute").?.object
        .get("fields").?.object.get("value").?.object.get("arms").?.object;
    try std.testing.expectEqualStrings("underline_color_256", sgr_arms.get("UNDERLINE_COLOR_256").?.string);
    try std.testing.expectEqualStrings("bg_8", sgr_arms.get("BG_8").?.string);

    const terminal_values = manifest_types.get("GhosttyTerminalOption").?.object.get("values").?.object;
    try std.testing.expectEqual(@as(i64, 6), terminal_values.get("SIZE").?.integer);
    try std.testing.expect(!terminal_values.contains("SIZE_CB"));

    const osc_values = manifest_types.get("GhosttyOscCommandType").?.object.get("values").?.object;
    try std.testing.expectEqual(@as(i64, 22), osc_values.get("KITTY_TEXT_SIZING").?.integer);
    try std.testing.expectEqual(@as(i64, 23), osc_values.get("KITTY_CLIPBOARD_PROTOCOL").?.integer);
    try std.testing.expectEqual(@as(i64, 24), osc_values.get("KITTY_DND_PROTOCOL").?.integer);
    try std.testing.expectEqual(@as(i64, 25), osc_values.get("CONTEXT_SIGNAL").?.integer);
    try std.testing.expect(osc_values.contains("TYPE_MAX_VALUE"));
    try std.testing.expect(!osc_values.contains("MAX_VALUE"));

    const key_values = manifest_types.get("GhosttyKey").?.object.get("values").?.object;
    try std.testing.expect(key_values.contains("A"));
    try std.testing.expect(!key_values.contains("KEY_A"));

    const mode_values = manifest_types.get("GhosttyModeReportState").?.object.get("values").?.object;
    try std.testing.expectEqual(@as(i64, 0), mode_values.get("NOT_RECOGNIZED").?.integer);
    try std.testing.expectEqual(@as(i64, 4), mode_values.get("PERMANENTLY_RESET").?.integer);
}

test "manifest named references resolve" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    const manifest_types = parsed.value.object.get("types").?.object;

    var type_iterator = manifest_types.iterator();
    while (type_iterator.next()) |type_entry| {
        const descriptor = type_entry.value_ptr.object;
        const fields_value = descriptor.get("fields") orelse continue;
        var field_iterator = fields_value.object.iterator();
        while (field_iterator.next()) |field_entry| {
            const field = field_entry.value_ptr.object;
            const field_type = field.get("type").?.string;
            if (!Json.isBuiltinType(field_type))
                try std.testing.expect(manifest_types.contains(field_type));

            if (field.get("elem")) |elem_value| {
                const elem = elem_value.string;
                if (!Json.isBuiltinType(elem))
                    try std.testing.expect(manifest_types.contains(elem));
            }

            if (field.get("arms")) |arms_value| {
                const union_descriptor = manifest_types.get(field_type).?.object;
                const union_fields = union_descriptor.get("fields").?.object;
                const tag_field_name = field.get("tag").?.string;
                const tag_type_name = fields_value.object.get(tag_field_name).?.object.get("type").?.string;
                const tag_values = manifest_types.get(tag_type_name).?.object.get("values").?.object;
                var arm_iterator = arms_value.object.iterator();
                while (arm_iterator.next()) |arm_entry| {
                    try std.testing.expect(tag_values.contains(arm_entry.key_ptr.*));
                    if (arm_entry.value_ptr.* == .null) continue;
                    try std.testing.expect(union_fields.contains(arm_entry.value_ptr.string));
                }
            }
        }
    }
}
