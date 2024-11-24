// Raw character display, per character

const std = @import("std");
const io = std.io;

const mibu = @import("mibu");
const events = mibu.events;
const term = mibu.term;
const utils = mibu.utils;
const color = mibu.color;
const cursor = mibu.cursor;
const style = mibu.style;

const DISPLAYW = 80;
const DISPLAYH = 29;

pub const Display = struct {
    pub const DisplayPixel = struct {
        fg: color.Color,
        bg: color.Color,
        bold: bool,
        c: u8,
    };

    const Self = @This();
    const CLSPixel: DisplayPixel = .{ .fg = .white, .bg = .blue, .c = ' ', .bold = false };
    raw_term: term.RawTerm,
    bufs: [2][DISPLAYW * DISPLAYH]DisplayPixel, // double buffer
    liveBufIndex: u1,
    offsBufIndex: u1,
    forceUpdate: bool,

    pub fn init() !Self {
        const stdin = io.getStdIn();
        const rt = try term.enableRawMode(stdin.handle);
        const writer = io.getStdOut().writer();

        try cursor.hide(writer);

        return Self{
            .raw_term = rt,
            .bufs = undefined,
            .liveBufIndex = 0,
            .offsBufIndex = 1,
            .forceUpdate = true,
        };
    }

    pub fn destroy(self: *Self) void {
        const writer = io.getStdOut().writer();
        cursor.show(writer) catch {};
        cursor.goTo(writer, 0, DISPLAYH) catch {};
        self.raw_term.disableRawMode() catch {};
    }

    pub fn getEvent(self: *Self, timeout:i32) !events.Event {
        _ = self;
        const stdin = io.getStdIn();
        const next = try events.nextWithTimeout(stdin, timeout);
        return next;
    }

    pub fn setPixel(self: *Self, x: usize, y: usize, p: DisplayPixel) !void {
        self.bufs[self.liveBufIndex][y * DISPLAYW + x] = p;
    }

    pub fn cls(self: *Self) void {
        self.forceUpdate = true;
        for (0..DISPLAYH) |y| {
            for (0..DISPLAYW) |x| {
                self.bufs[self.liveBufIndex][y * DISPLAYW + x] = CLSPixel;
            }
        }
    }

    pub fn paint(self: *Self) !void {
        // just draw changes to avoid sending excess data to terminal
        const writer = io.getStdOut().writer();

        try writer.print("{s}", .{utils.comptimeCsi("?2026h", .{})});

        for (0..DISPLAYH) |y| {
            for (0..DISPLAYW) |x| {
                const p = self.bufs[self.liveBufIndex][y * DISPLAYW + x];
                const oldp = self.bufs[self.offsBufIndex][y * DISPLAYW + x];
                if (self.forceUpdate or !std.meta.eql(p, oldp)) {
                    try cursor.goTo(writer, x, y);
                    try color.bg256(writer, p.bg);
                    try color.fg256(writer, p.fg);
                    if (p.bold) {
                        try style.bold(writer);
                    } else {
                        try style.noBold(writer);
                    }
                    try writer.print("{c}", .{p.c});
                    self.bufs[self.offsBufIndex][y * DISPLAYW + x] = p;
                }
            }
        }

        try writer.print("{s}", .{utils.comptimeCsi("?2026l", .{})});

        self.forceUpdate = false;

        // flip
        if (self.liveBufIndex == 0) {
            self.liveBufIndex = 1;
            self.offsBufIndex = 0;
        } else {
            self.liveBufIndex = 0;
            self.offsBufIndex = 1;
        }
    }
};
