const std = @import("std");
var cw = ConsoleWriter{};
const buildopts = @import("buildopts");

const w4 = @import("wasm4.zig");

extern fn console_write(data: [*]const u8, len: usize) void;

// Implement a std.io.Writer backed by console_write()
const ConsoleWriter = struct {
    const Writer = std.io.Writer(
        *ConsoleWriter,
        error{},
        write,
    );

    fn write(
        self: *ConsoleWriter,
        data: []const u8,
    ) error{}!usize {
        _ = self;
        w4.trace(data);
        return data.len;
    }

    pub fn writer(self: *ConsoleWriter) Writer {
        return .{ .context = self };
    }
};

pub fn getWriter() *ConsoleWriter {
    return &cw;
}
