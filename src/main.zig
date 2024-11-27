const std = @import("std");

const Display = @import("display.zig").Display;

const time = @import("time.zig");
const config = @import("config.zig");

const GameState = @import("gamestate.zig").GameState;
const Move = @import("gamestate.zig").Move;

const PlayerType = @import("ui.zig").PlayerType;
const UiAgent = @import("ui.zig").UiAgent;
const UiAgentHuman = @import("uiagenthuman.zig").UiAgentHuman;
const UiAgentMachine = @import("uiagentmachine.zig").UiAgentMachine;
const drawGame = @import("ui.zig").drawGame;
const emitMoves = @import("ui.zig").emitMoves;

pub fn main() !void {
    var exitReq = false;

    try config.parseCommandLine();

    while (!exitReq) {
        var turnN: usize = 0;
        var gameOver = false;
        time.initTime();

        var agents:[config.NUM_PAWNS]UiAgent = undefined;
        for (config.players, 0..) |p, i| {
            switch(p) {
                .Human => agents[i] = UiAgent{.human = UiAgentHuman.init()},
                .Machine => agents[i] = UiAgent{.machine = UiAgentMachine.init()},
            }
        }

        var lastMoves: [config.NUM_PAWNS]Move = undefined;

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

        var gs = GameState.init();

        var pi: usize = 0; // whose turn is it

        try agents[pi].selectMoveInteractive(&gs, pi);

        while (!gameOver) {
            var timeout: i32 = 100;
            if (config.players[0] == .Machine and config.players[1] == .Machine) {
                timeout = 0;
            }
            const next = try display.getEvent(timeout);

            try agents[pi].handleEvent(next, &gs, pi);

            if (agents[pi].getCompletedMove()) |move| {
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

                try agents[pi].selectMoveInteractive(&gs, pi);
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
            try agents[pi].paint(&display);

            try display.paint();
        }
        if (!config.playForever) {
            exitReq = true;
        }
    }
}
