const std = @import("std");

const config = @import("config.zig");
const GameState = @import("gamestate.zig").GameState;
const Dir = @import("gamestate.zig").Dir;
const Move = @import("gamestate.zig").Move;
const VerifiedMove = @import("gamestate.zig").VerifiedMove;
const buildopts = @import("buildopts");
const native_endian = @import("builtin").target.cpu.arch.endian();

// a record of moves made in a game
pub const GameRecord = struct {
    const Self = @This();
    moves: std.ArrayList(Move) = undefined,

    pub fn init(alloc: std.mem.Allocator) !Self {
        return Self {
            .moves = std.ArrayList(Move).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        self.moves.deinit();
    }

    pub fn append(self: *Self, m:Move) !void {
        try self.moves.append(m);
    }

    pub fn getAllMoves(self: *const Self) []const Move {
        return self.moves.items;
    }

    pub fn toGameState(self: *const Self, verify:bool) !GameState {
        var gs = GameState.init();
        for (self.moves.items, 0..) |m, i| {
            const vm = if (verify) try gs.verifyMove(i%2, m)
                else VerifiedMove{.legal = true, .move = m};
            try gs.applyMove(i%2, vm);
        }
        return gs;
    }

// compact binary representation, 1 byte per move
// 1 bit for fence/pawn (0x80)
// if pawn:
//    7 bits of 9x9 nodeid (0-80)
// if fence
//    1 bit of v/h
//    6 bits of 8x8 nodeid (0-64)

    const GameStatePawnExport = packed struct {
        cellId: u7, // 0 -> 80
        isPawn: u1 = 1, // msb
    };

    const GameStateFenceExport = packed struct {
        isHorz: u1, // 0 = .vert, 1 = .horz
        cellId: u6, // 0 -> 64
        isPawn: u1 = 0, // msb
    };

    pub fn toStringBase64Alloc(self: *const Self, alloc: std.mem.Allocator) ![]u8 {
        const b64 = std.base64.standard.Encoder;
        const rawbuf = try alloc.alloc(u8, self.raw_calcSize());
        defer alloc.free(rawbuf);
        const raw = try self.encodeRaw(rawbuf);
        const b64buf = try alloc.alloc(u8, self.b64_calcSize());
        _ = b64.encode(b64buf, raw);
        return b64buf;
    }

    fn b64_calcSize(self: *const Self) usize {
        const b64 = std.base64.standard.Encoder;
        return b64.calcSize(self.raw_calcSize());
    }

    pub fn raw_calcSize(self: *const Self) usize {
        return self.moves.items.len;  // 1 byte per move
    }

    pub fn encodeRaw(self: *const Self, buf: []u8) ![]u8 {
        if (buf.len < self.moves.items.len) {
            return error.BufTooSmallErr;
        }
        for (self.moves.items, 0..) |m, i| {
            switch(m) {
                .pawn => |pawnmove| {
                    const cellId = @as(u8, @intCast(pawnmove.y)) * 9 + @as(u8, @intCast(pawnmove.x));
                    std.debug.assert(cellId < 9*9);
                    const val = GameStatePawnExport {.isPawn = 1, .cellId = @intCast(cellId)};
                    buf[i] = @as(*const u8, @ptrCast(&val)).*;
                },
                .fence => |fencemove| {
                    const cellId = @as(u8, @intCast(fencemove.pos.y)) * 8 + @as(u8, @intCast(fencemove.pos.x));
                    std.debug.assert(cellId < 8*8);
                    const val = GameStateFenceExport {.isPawn = 0, .cellId = @intCast(cellId), .isHorz = if (fencemove.dir == .horz) 1 else 0};
                    buf[i] = @as(*const u8, @ptrCast(&val)).*;
                },
            }
        }
        return buf[0..self.moves.items.len];
    }

    pub fn initFromBase64(alloc: std.mem.Allocator, b64src: []const u8) !Self {
        const b64 = std.base64.standard.Decoder;
        const rawLen = try b64.calcSizeForSlice(b64src);
        const rawbuf = try alloc.alloc(u8, rawLen);
        defer alloc.free(rawbuf);
        try b64.decode(rawbuf, b64src);
        return try initFromRaw(alloc, rawbuf);
    }

    pub fn initFromRaw(alloc: std.mem.Allocator, buf: []const u8) !Self {
        var self = try Self.init(alloc);
        errdefer self.deinit();
        for (buf) |c| {
            if (c & 0x80 == 0x80) { // isPawn
                const pe:GameStatePawnExport = @as(*const GameStatePawnExport, @ptrCast(&c)).*;
                const y = pe.cellId / 9;
                const x = pe.cellId - (y*9);
                const move = Move{ .pawn = .{ .x = @intCast(x), .y = @intCast(y) } };
                try self.append(move);
            } else { // fence
                const fe:GameStateFenceExport = @as(*const GameStateFenceExport, @ptrCast(&c)).*;
                const y = fe.cellId / 8;
                const x = fe.cellId - (y*8);
                const move = Move{ .fence = .{.pos = .{ .x = @intCast(x), .y = @intCast(y) }, .dir = if (fe.isHorz == 1) .horz else .vert }};
                try self.append(move);
            }
        }
        return self;
    }

    pub fn printGlendenningAlloc(self: *const Self, alloc: std.mem.Allocator) ![]u8 {
        // 1. e8 a2
        // 2. a1v e7
        // ...
        var turn:usize = 1;
        var outstr:[]u8 = try std.fmt.allocPrint(alloc, "", .{});
        var old:[]u8 = undefined;
        for (self.moves.items, 0..) |m, i| {
            if (i % 2 == 0) {
                old = outstr;
                outstr = try std.fmt.allocPrint(alloc, "{s}{d}.", .{old, turn});
                alloc.free(old);
            }
            var mbuf:[16]u8 = undefined;
            const s = try m.toString(&mbuf);
            
            old = outstr;
            outstr = try std.fmt.allocPrint(alloc, "{s} {s}", .{old, s});
            alloc.free(old);

            if (i % 2 == 1) {
                old = outstr;
                outstr = try std.fmt.allocPrint(alloc, "{s}\n", .{old});
                alloc.free(old);
                turn += 1;
            }
        }
        return outstr;
    }
};
 

