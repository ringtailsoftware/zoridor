const std = @import("std");

const Display = @import("display.zig").Display;

const clock = @import("clock.zig");
const config = @import("config.zig");

const GameState = @import("gamestate.zig").GameState;
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
};
var wstate:WebState = undefined;

// exposed to JS
fn getNextMoveInternal() !void {
    wstate.pi = (wstate.pi + 1) % config.NUM_PAWNS;

    // FIXME assumes move is available immediately, js should poll for it and call process repeatedly
    try config.players[wstate.pi].selectMoveInteractive(&wstate.gs, wstate.pi);
    try config.players[wstate.pi].process(&wstate.gs, wstate.pi);
    if (config.players[wstate.pi].getCompletedMove()) |vmove| {
        try wstate.gs.applyMove(wstate.pi, vmove);
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

    // move opponent
    _ = getNextMoveInternal() catch 0;
}

export fn movePawn(x:usize, y:usize) void {
    const move = Move{ .pawn = .{ .x = @intCast(x), .y = @intCast(y) } };
    const vm = try wstate.gs.verifyMove(wstate.pi, move);
    try wstate.gs.applyMove(wstate.pi, vm);

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

export fn restart(pi:usize) void {
    _ = gamesetup(pi) catch 0;
}

fn gamesetup(pi:usize) !void {
    wstate = .{
        .pi = pi,
        .gs = GameState.init(),
    };
    config.players[0] = try UiAgent.make("machine");    // should be "null"
    config.players[1] = try UiAgent.make("machine");
    if (pi != 0) {
        _ = getNextMoveInternal() catch 0;
    }
}

export fn init() void {
    _ = console.print("Hello world\n", .{}) catch 0;
    _ = gamesetup(0) catch 0;
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
