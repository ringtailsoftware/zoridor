const std = @import("std");

const Display = @import("display.zig").Display;

const time = @import("time.zig");
const config = @import("config.zig");

const GameState = @import("gamestate.zig").GameState;
const Move = @import("gamestate.zig").Move;

const UiAgent = @import("ui.zig").UiAgent;
const UiAgentHuman = @import("uiagenthuman.zig").UiAgentHuman;
const UiAgentMachine = @import("uiagentmachine.zig").UiAgentMachine;
const drawGame = @import("ui.zig").drawGame;
const emitMoves = @import("ui.zig").emitMoves;

const buildopts = @import("buildopts");

// FIXME to be provided by JS
export fn getTimeUs() u32 {
    return 0;
}

// exposed to JS
export fn startGame() void {
}
export fn isMoveLegal() bool {
    return true;
}

pub fn main() !void {
    var exitReq = false;

    // default to human vs machine
    config.players[0] = try UiAgent.make("human");
    config.players[1] = try UiAgent.make("machine");

    if (!buildopts.web) {
        try config.parseCommandLine();
    }

    time.initTime();


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
