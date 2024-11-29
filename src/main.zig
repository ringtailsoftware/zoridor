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

// FIXME to be provided by JS
export fn getTimeUs() u32 {
    return 0;
}

// exposed to JS
export fn startGame() void {
}
export fn isMoveLegal(x:u32, y:u32) bool {
    _ = console.print("ISLEGAL? {d},{d}\n", .{x,y}) catch 0;
    return true;
}

fn getNextMoveInternal() !void {
    try config.players[wstate.pi].selectMoveInteractive(&wstate.gs, wstate.pi);
    try config.players[wstate.pi].process(&wstate.gs, wstate.pi);
    if (config.players[wstate.pi].getCompletedMove()) |vmove| {
        try wstate.gs.applyMove(wstate.pi, vmove);
        var b1: [16]u8 = undefined;
        const s1 = try vmove.move.toString(&b1);
        _ = console.print("Move {s}\n", .{s1}) catch 0;
        wstate.pi = (wstate.pi + 1) % config.NUM_PAWNS;
    }
}

export fn getNextMove() void {
    _ = console.print("GNM\n", .{}) catch 0;
    _ = getNextMoveInternal() catch 0;
}

fn gamesetup() !void {
    wstate = .{
        .pi = 0,
        .gs = GameState.init(),
    };
    config.players[0] = try UiAgent.make("machine");
    config.players[1] = try UiAgent.make("machine");
}

export fn init() void {
    _ = console.print("Hello world\n", .{}) catch 0;
    _ = gamesetup() catch 0;
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
    var exitReq = false;

    // default to human vs machine
    config.players[0] = try UiAgent.make("human");
    config.players[1] = try UiAgent.make("machine");

    if (!buildopts.web) {
        try config.parseCommandLine();
    }

    clock.initTime();

    if (buildopts.web) {
        return;
    } else {
        // loop for terminal
        while (!exitReq) {
            var display = try Display.init();
            defer display.destroy();

            const sz = try Display.getSize();
            if (config.mini) {
                if (sz.width < 80 or sz.height < 24) {
                    std.debug.print("Display too small, must be 80x24 or larger\r\n", .{});
                    return;
                }
            } else {
                if (sz.width < 80 or sz.height < 29) {
                    std.debug.print("Display too small, must be 80x29 or larger\r\n", .{});
                    return;
                }
            }

            display.cls();
            try display.paint();

            var timeout: i32 = 0;   // default to not pausing, let machine agents run fast
            var turnN: usize = 0;
            var gameOver = false;
            var lastMoves: [config.NUM_PAWNS]Move = undefined;
            var gs = GameState.init();
            var pi: usize = 0; // whose turn is it

            try config.players[pi].selectMoveInteractive(&gs, pi);

            while (!gameOver) {
                const next = try display.getEvent(timeout);

                try config.players[pi].process(&gs, pi);

                if (try config.players[pi].handleEvent(next, &gs, pi)) {
                    timeout = 100;  // increase timeout if events being used for interaction
                }

                if (config.players[pi].getCompletedMove()) |move| {
                    // apply the move
                    try gs.applyMove(pi, move);
                    lastMoves[pi] = move.move;
                    if (pi == config.NUM_PAWNS - 1) { // final player to take turn
                        try emitMoves(turnN, lastMoves);
                        turnN += 1;
                    }

                    if (gs.hasWon(pi)) {
                        config.wins[pi] += 1;
                        gameOver = true;
                    }

                    // select next player to make a move
                    pi = (pi + 1) % config.NUM_PAWNS;

                    try config.players[pi].selectMoveInteractive(&gs, pi);
                }

                switch (next) {
                    .key => |k| switch (k) {
                        .char => |c| switch (c) {
                            'q' => {
                                exitReq = true;
                                break;
                            },
                            else => {},
                        },
                        else => {},
                    },
                    else => {},
                }

                display.cls();
                try drawGame(&display, &gs, pi);
                try config.players[pi].paint(&display);

                try display.paint();
            }
            if (!config.playForever) {
                exitReq = true;
            }
        }
    }
}
