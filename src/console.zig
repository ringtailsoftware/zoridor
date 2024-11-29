const std = @import("std");
var cw = ConsoleWriter{};
const buildopts = @import("buildopts");

extern fn console_write(data: [*]const u8, len: usize) void;

fn console_write_native(data: [*]const u8, len: usize) void {
    const stdout = std.io.getStdOut().writer();
    _ = stdout.print("{s}", .{data[0..len]}) catch 0;
}

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
        if (buildopts.web) {
            console_write(data.ptr, data.len);
        } else {
            console_write_native(data.ptr, data.len);
        }
        return data.len;
    }

    pub fn writer(self: *ConsoleWriter) Writer {
        return .{ .context = self };
    }
};

pub fn getWriter() *ConsoleWriter {
    return &cw;
}
