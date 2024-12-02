const std = @import("std");

const Display = @import("display.zig").Display;

const clock = @import("clock.zig");
const config = @import("config.zig");

const GameState = @import("gamestate.zig").GameState;
const GameRecord = @import("record.zig").GameRecord;
const Move = @import("gamestate.zig").Move;

const UiAgent = @import("ui.zig").UiAgent;
const UiAgentHuman = @import("uiagenthuman.zig").UiAgentHuman;
const UiAgentMachine = @import("uiagentmachine.zig").UiAgentMachine;
const drawGame = @import("ui.zig").drawGame;
const emitMoves = @import("ui.zig").emitMoves;

const buildopts = @import("buildopts");

const console = @import("console.zig").getWriter().writer();

const WebState = struct {
    pi: usize,
    gs: GameState,
    record: GameRecord,
    recordB64Buf: ?[]const u8,  // base64 of all moves performed so far
    startB64Buf: [1024]u8,  // buffer to setup initial game state
    start: ?[]u8,
};
var wstate:WebState = undefined;
var inited = false;

fn updateRecord(move:Move) !void {
    try wstate.record.append(move);
    // generate base64 for game
    if (wstate.recordB64Buf) |buf| {
        std.heap.page_allocator.free(buf);
        wstate.recordB64Buf = null;
    }
    wstate.recordB64Buf = try wstate.record.toStringBase64Alloc(std.heap.page_allocator);
}

// exposed to JS
fn getNextMoveInternal() !void {
    wstate.pi = (wstate.pi + 1) % config.NUM_PAWNS;

    // FIXME assumes move is available immediately, js should poll for it and call process repeatedly
    try config.players[wstate.pi].selectMoveInteractive(&wstate.gs, wstate.pi);
    try config.players[wstate.pi].process(&wstate.gs, wstate.pi);
    if (config.players[wstate.pi].getCompletedMove()) |vmove| {
        try wstate.gs.applyMove(wstate.pi, vmove);
        try updateRecord(vmove.move);
        // next player
        wstate.pi = (wstate.pi + 1) % config.NUM_PAWNS;
    }
}

export fn isFenceMoveLegal(x:usize, y:usize, dir:u8) bool {
    const move = Move{ .fence = .{ .pos = .{ .x = @intCast(x), .y = @intCast(y) }, .dir = if (dir=='v') .vert else .horz } };
    const vm = try wstate.gs.verifyMove(wstate.pi, move);
    return vm.legal;
}

export fn isPawnMoveLegal(x:usize, y:usize) bool {
    const move = Move{ .pawn = .{ .x = @intCast(x), .y = @intCast(y) } };
    const vm = try wstate.gs.verifyMove(wstate.pi, move);
    return vm.legal;
}

export fn moveFence(x:usize, y:usize, dir:u8) void {
    const move = Move{ .fence = .{ .pos = .{ .x = @intCast(x), .y = @intCast(y) }, .dir = if (dir=='v') .vert else .horz } };
    const vm = try wstate.gs.verifyMove(wstate.pi, move);
    try wstate.gs.applyMove(wstate.pi, vm);
    _ = updateRecord(vm.move) catch 0;

    // move opponent
    _ = getNextMoveInternal() catch 0;
}

export fn movePawn(x:usize, y:usize) void {
    const move = Move{ .pawn = .{ .x = @intCast(x), .y = @intCast(y) } };
    const vm = try wstate.gs.verifyMove(wstate.pi, move);
    try wstate.gs.applyMove(wstate.pi, vm);
    _ = updateRecord(vm.move) catch 0;

    // move opponent
    _ = getNextMoveInternal() catch 0;
}

export fn getPlayerIndex() usize {
    return wstate.pi;
}

export fn hasWon(pi:usize) bool {
    return wstate.gs.hasWon(pi);
}

export fn getNumFences() usize {
    return wstate.gs.numFences;
}
export fn getFencePosX(i:usize) usize {
    return wstate.gs.fences[i].pos.x;
}
export fn getFencePosY(i:usize) usize {
    return wstate.gs.fences[i].pos.y;
}
export fn getFencePosDir(i:usize) usize {
    return switch(wstate.gs.fences[i].dir) {
        .vert => 'v',
        .horz => 'h',
    };
}

export fn getPawnPosX(pi:usize) usize {
    return wstate.gs.getPawnPos(pi).x;
}
export fn getPawnPosY(pi:usize) usize {
    return wstate.gs.getPawnPos(pi).y;
}

export fn getFencesRemaining(pi:usize) usize {
    return wstate.gs.pawns[pi].numFencesRemaining;
}

export fn restart(pi:usize, setupB64Len:u32) bool {
    const b64input = wstate.startB64Buf[0..setupB64Len];
    //_ = console.print("RESTART setupB64Len={d} s={s}\n", .{setupB64Len, b64input}) catch 0;
    return gamesetup(pi, b64input) catch false;
}

export fn allocUint8(length: u32) [*]const u8 {
    const slice = std.heap.page_allocator.alloc(u8, length) catch
        @panic("failed to allocate memory");
    return slice.ptr;
}

export fn getGameStartRecordLen() usize {
    return wstate.startB64Buf.len;
}

export fn getGameStartRecordPtr() [*]const u8 {
    return (&wstate.startB64Buf).ptr;
}

export fn getGameRecordPtr() [*]const u8 {
    if (wstate.recordB64Buf) |b| {
        return b.ptr;
    } else {
        return @ptrFromInt(0xDEADBEEF);  // len will be 0, so ignored
    }
}
export fn getGameRecordLen() usize {
    if (wstate.recordB64Buf) |b| {
        return b.len;
    } else {
        return 0;
    }
}

fn gamesetup(piStart:usize, b64O:?[]const u8) !bool {
    if (inited) {
        wstate.record.deinit();
        if (wstate.recordB64Buf != null) {
            std.heap.page_allocator.free(wstate.recordB64Buf.?);
        }
    }

    var pi = piStart;
    var gs = GameState.init();
    var recordB64Buf:?[]const u8 = null;
    var record:GameRecord = undefined;
    if (b64O) |b64| {
        // user supplied starting state
        record = try GameRecord.initFromBase64(std.heap.page_allocator, b64);
        gs = try record.toGameState(true);
        recordB64Buf = try record.toStringBase64Alloc(std.heap.page_allocator);
        pi += record.getAllMoves().len % 2;
    } else {
        record = try GameRecord.init(std.heap.page_allocator);
    }

    wstate = .{
        .pi = pi,
        .gs = gs,
        .record = record,
        .recordB64Buf = recordB64Buf,
        .startB64Buf = undefined,
        .start = null,
    };
    inited = true;
    config.players[0] = try UiAgent.make("machine");    // should be "null"
    config.players[1] = try UiAgent.make("machine");
    if (pi != 0) {
        _ = getNextMoveInternal() catch 0;
    }
    return true;
}

export fn init() void {
    _ = console.print("Hello world\n", .{}) catch 0;
    _ = gamesetup(0, null) catch 0;
}

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = message_level;
    _ = scope;
    _ = console.print(format ++ "\n", args) catch 0;
}

pub const std_options = .{
    .logFn = logFn,
    .log_level = .info,
};

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = ret_addr;
    _ = trace;
    @setCold(true);
    _ = console.print("PANIC: {s}", .{msg}) catch 0;
    while (true) {}
}

pub fn main() !void {
    // default to human vs machine
    config.players[0] = try UiAgent.make("human");
    config.players[1] = try UiAgent.make("machine");

    clock.initTime();
}
