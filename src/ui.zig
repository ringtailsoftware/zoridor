const std = @import("std");

const Display = @import("display.zig").Display;

const io = std.io;

const mibu = @import("mibu");
const events = mibu.events;
const term = mibu.term;
const color = mibu.color;

const time = @import("time.zig");
const config = @import("config.zig");

const GameState = @import("gamestate.zig").GameState;
const PosDir = @import("gamestate.zig").PosDir;
const PosPath = @import("gamestate.zig").PosPath;
const Pos = @import("gamestate.zig").Pos;
const Dir = @import("gamestate.zig").Dir;
const Move = @import("gamestate.zig").Move;
const VerifiedMove = @import("gamestate.zig").VerifiedMove;

const UiAgentMachine = @import("uiagentmachine.zig").UiAgentMachine;
const UiAgentHuman = @import("uiagenthuman.zig").UiAgentHuman;

// Interface for playing agents
pub const UiAgent = union(enum) {
    human: UiAgentHuman,
    machine: UiAgentMachine,

    // start searching for a move to make
    pub fn selectMoveInteractive(self: *UiAgent, gs: *const GameState, pi: usize) !void {
        switch(self.*) {
            inline else => |*case| return case.selectMoveInteractive(gs, pi),
        }
    }

    // handle any UI events
    pub fn handleEvent(self: *UiAgent, event: events.Event, gs: *const GameState, pi: usize) !void {
        switch(self.*) {
            inline else => |*case| return case.handleEvent(event, gs, pi),
        }
    }

    // paint anything to display
    pub fn paint(self: *UiAgent, display: *Display) !void {
        switch(self.*) {
            inline else => |*case| return case.paint(display),
        }
    }

    // return chosen move, if one has been found. Will be polled
    pub fn getCompletedMove(self: *UiAgent) ?VerifiedMove {
        switch(self.*) {
            inline else => |*case| return case.getCompletedMove(),
        }
    }
};

pub const PlayerType = enum {
    Human,
    Machine,
};

pub fn drawGame(display: *Display, gs: *GameState, gspi: usize) !void {
    try drawStats(display, gs, gspi);
    drawBoard(display);
    for (gs.pawns, 0..) |p, pi| {
        drawPawn(display, p.pos.x, p.pos.y, config.pawnColour[pi]);
    }
    for (gs.getFences()) |f| {
        drawFence(display, f.pos.x, f.pos.y, config.fenceColour, f.dir);
    }
}

fn paintString(display: *Display, bg: color.Color, fg: color.Color, bold: bool, xpos: usize, ypos: usize, sl: []u8) !void {
    var strx = xpos;
    for (sl) |elem| {
        try display.setPixel(strx, ypos, .{ .fg = fg, .bg = bg, .c = elem, .bold = bold });
        strx += 1;
    }
}

fn drawStats(display: *Display, gs: *const GameState, pi: usize) !void {
    var buf: [32]u8 = undefined;

    var statsXoff: usize = 0;
    var statsYoff: usize = 0;

    if (config.mini) {
        statsXoff = 41;
        statsYoff = 3;
    } else {
        statsXoff = 59;
        statsYoff = 2;
    }

    switch (config.players[0]) {
        .Human => try paintString(display, .black, .white, pi == 0, statsXoff, statsYoff, try std.fmt.bufPrint(&buf, "Player 1: Human", .{})),
        .Machine => try paintString(display, .black, .white, pi == 0, statsXoff, statsYoff, try std.fmt.bufPrint(&buf, "Player 1: Machine", .{})),
    }
    try paintString(display, .black, .white, pi == 0, statsXoff, statsYoff + 1, try std.fmt.bufPrint(&buf, "Wins: {d}", .{config.wins[0]}));
    try paintString(display, .black, .white, pi == 0, statsXoff, statsYoff + 2, try std.fmt.bufPrint(&buf, "Fences: {d}", .{gs.pawns[0].numFencesRemaining}));

    switch (config.players[1]) {
        .Human => try paintString(display, .black, .white, pi == 1, statsXoff, statsYoff + 4, try std.fmt.bufPrint(&buf, "Player 2: Human", .{})),
        .Machine => try paintString(display, .black, .white, pi == 1, statsXoff, statsYoff + 4, try std.fmt.bufPrint(&buf, "Player 2: Machine", .{})),
    }
    try paintString(display, .black, .white, pi == 1, statsXoff, statsYoff + 5, try std.fmt.bufPrint(&buf, "Wins: {d}", .{config.wins[1]}));
    try paintString(display, .black, .white, pi == 1, statsXoff, statsYoff + 6, try std.fmt.bufPrint(&buf, "Fences: {d}", .{gs.pawns[1].numFencesRemaining}));

    if (gs.hasWon(0)) {
        try paintString(display, .black, .white, true, statsXoff, statsYoff + 15, try std.fmt.bufPrint(&buf, "Player1 won", .{}));
        try paintString(display, .black, .white, true, statsXoff, statsYoff + 16, try std.fmt.bufPrint(&buf, "Player2 lost", .{}));
    }
    if (gs.hasWon(1)) {
        try paintString(display, .black, .white, true, statsXoff, statsYoff + 15, try std.fmt.bufPrint(&buf, "Player1 lost", .{}));
        try paintString(display, .black, .white, true, statsXoff, statsYoff + 16, try std.fmt.bufPrint(&buf, "Player2 won", .{}));
    }

    if (config.players[0] == .Human or config.players[1] == .Human) {
        try paintString(display, .black, .white, true, statsXoff, statsYoff + 8, try std.fmt.bufPrint(&buf, "q - quit", .{}));
        try paintString(display, .black, .white, true, statsXoff, statsYoff + 9, try std.fmt.bufPrint(&buf, "cursors - set pos", .{}));
        try paintString(display, .black, .white, true, statsXoff, statsYoff + 10, try std.fmt.bufPrint(&buf, "enter - confirm", .{}));
        try paintString(display, .black, .white, true, statsXoff, statsYoff + 11, try std.fmt.bufPrint(&buf, "tab - fence/pawn", .{}));
        try paintString(display, .black, .white, true, statsXoff, statsYoff + 12, try std.fmt.bufPrint(&buf, "space - rotate fence", .{}));
    }

    if (config.lastTurnStr) |s| {
        try paintString(display, .black, .white, true, statsXoff, statsYoff + 14, try std.fmt.bufPrint(&buf, "{s}", .{s}));
    }
}

fn drawBoard(display: *Display) void {
    if (config.mini) {
        // draw squares
        for (0..config.GRIDSIZE) |x| {
            for (0..config.GRIDSIZE) |y| {
                if (x == 0) {
                    // row labels
                    try display.setPixel(config.UI_XOFF + 4 * x, config.UI_YOFF + 2 * y, .{ .fg = .white, .bg = .blue, .c = config.ROW_LABEL_START + @as(u8, @intCast(y)), .bold = true });
                }

                // pawn squares
                try display.setPixel(config.UI_XOFF + 4 * x + config.label_extra_w, config.UI_YOFF + 2 * y, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                try display.setPixel(config.UI_XOFF + 4 * x + 1 + config.label_extra_w, config.UI_YOFF + 2 * y, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });

                if (true) {
                    if (x != config.GRIDSIZE - 1) {
                        try display.setPixel(config.UI_XOFF + 4 * x + 2 + config.label_extra_w, config.UI_YOFF + 2 * y, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                        try display.setPixel(config.UI_XOFF + 4 * x + 3 + config.label_extra_w, config.UI_YOFF + 2 * y, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                    }

                    if (y != config.GRIDSIZE - 1) {
                        try display.setPixel(config.UI_XOFF + 4 * x + config.label_extra_w, config.UI_YOFF + 2 * y + 1, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                        try display.setPixel(config.UI_XOFF + 4 * x + 1 + config.label_extra_w, config.UI_YOFF + 2 * y + 1, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                    }
                }
            }
        }

        // draw fence join spots
        for (0..config.GRIDSIZE - 1) |xg| {
            for (0..config.GRIDSIZE - 1) |yg| {
                try display.setPixel(config.UI_XOFF + 4 * xg + 2 + config.label_extra_w, config.UI_YOFF + 2 * yg + 1, .{ .fg = .white, .bg = .white, .c = ' ', .bold = false });
                try display.setPixel(config.UI_XOFF + 4 * xg + 3 + config.label_extra_w, config.UI_YOFF + 2 * yg + 1, .{ .fg = .white, .bg = .white, .c = ' ', .bold = false });
            }
        }

        // column labels
        for (0..config.GRIDSIZE) |x| {
            try display.setPixel(config.UI_XOFF + 4 * x + config.label_extra_w, config.UI_YOFF + 2 * config.GRIDSIZE, .{ .fg = .white, .bg = .blue, .c = config.COLUMN_LABEL_START + @as(u8, @intCast(x)), .bold = true });
        }
    } else {
        // draw border
        for (0..config.GRIDSIZE * 6 + 2) |x| {
            try display.setPixel(config.UI_XOFF + x - 2, config.UI_YOFF - 1, .{ .fg = .white, .bg = .white, .c = ' ', .bold = false }); // top
            try display.setPixel(config.UI_XOFF + x - 2, (config.UI_YOFF + 3 * config.GRIDSIZE) - 1, .{ .fg = .white, .bg = .white, .c = ' ', .bold = false }); // bottom
        }
        for (0..config.GRIDSIZE * 3) |y| {
            try display.setPixel(config.UI_XOFF - 2, config.UI_YOFF + y, .{ .fg = .white, .bg = .white, .c = ' ', .bold = false }); // left
            try display.setPixel(config.UI_XOFF - 1, config.UI_YOFF + y, .{ .fg = .white, .bg = .white, .c = ' ', .bold = false }); // left

            try display.setPixel(config.UI_XOFF + 6 * config.GRIDSIZE - 2, config.UI_YOFF + y, .{ .fg = .white, .bg = .white, .c = ' ', .bold = false }); // right
            try display.setPixel(config.UI_XOFF + 6 * config.GRIDSIZE - 1, config.UI_YOFF + y, .{ .fg = .white, .bg = .white, .c = ' ', .bold = false }); // right
        }

        // column labels
        for (0..config.GRIDSIZE) |x| {
            try display.setPixel(config.UI_XOFF + 6 * x + 1, config.UI_YOFF + 3 * config.GRIDSIZE - 1, .{ .fg = .black, .bg = .white, .c = config.COLUMN_LABEL_START + @as(u8, @intCast(x)), .bold = true });
        }

        // draw squares
        for (0..config.GRIDSIZE) |x| {
            for (0..config.GRIDSIZE) |y| {
                if (x == 0) {
                    // row labels
                    try display.setPixel(config.UI_XOFF + 6 * x - 2, config.UI_YOFF + 3 * y, .{ .fg = .black, .bg = .white, .c = config.ROW_LABEL_START + @as(u8, @intCast(y)), .bold = true });
                }

                // pawn squares
                try display.setPixel(config.UI_XOFF + 6 * x + 0, config.UI_YOFF + 3 * y, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                try display.setPixel(config.UI_XOFF + 6 * x + 1, config.UI_YOFF + 3 * y, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                try display.setPixel(config.UI_XOFF + 6 * x + 2, config.UI_YOFF + 3 * y, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                try display.setPixel(config.UI_XOFF + 6 * x + 3, config.UI_YOFF + 3 * y, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });

                try display.setPixel(config.UI_XOFF + 6 * x + 0, config.UI_YOFF + 3 * y + 1, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                try display.setPixel(config.UI_XOFF + 6 * x + 1, config.UI_YOFF + 3 * y + 1, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                try display.setPixel(config.UI_XOFF + 6 * x + 2, config.UI_YOFF + 3 * y + 1, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                try display.setPixel(config.UI_XOFF + 6 * x + 3, config.UI_YOFF + 3 * y + 1, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
            }
        }
    }
}

fn drawPawn(display: *Display, x: usize, y: usize, c: color.Color) void {
    if (config.mini) {
        try display.setPixel(config.UI_XOFF + 4 * x + config.label_extra_w, config.UI_YOFF + 2 * y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(config.UI_XOFF + 4 * x + 1 + config.label_extra_w, config.UI_YOFF + 2 * y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
    } else {
        try display.setPixel(config.UI_XOFF + 6 * x + 0, config.UI_YOFF + 3 * y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(config.UI_XOFF + 6 * x + 1, config.UI_YOFF + 3 * y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(config.UI_XOFF + 6 * x + 2, config.UI_YOFF + 3 * y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(config.UI_XOFF + 6 * x + 3, config.UI_YOFF + 3 * y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });

        try display.setPixel(config.UI_XOFF + 6 * x + 0, config.UI_YOFF + 3 * y + 1, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(config.UI_XOFF + 6 * x + 1, config.UI_YOFF + 3 * y + 1, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(config.UI_XOFF + 6 * x + 2, config.UI_YOFF + 3 * y + 1, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(config.UI_XOFF + 6 * x + 3, config.UI_YOFF + 3 * y + 1, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
    }
}

fn drawFence(display: *Display, x: usize, y: usize, c: color.Color, dir: Dir) void {
    // x,y is most NW square adjacent to fence
    if (config.mini) {
        if (dir == .horz) {
            for (0..6) |xi| {
                try display.setPixel(xi + config.UI_XOFF + 4 * x + config.label_extra_w, config.UI_YOFF + 2 * y + 1, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
            }
        } else {
            for (0..3) |yi| {
                try display.setPixel(config.UI_XOFF + 4 * x + 2 + config.label_extra_w, yi + config.UI_YOFF + 2 * y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
                try display.setPixel(config.UI_XOFF + 4 * x + 2 + 1 + config.label_extra_w, yi + config.UI_YOFF + 2 * y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
            }
        }
    } else {
        if (dir == .horz) {
            for (0..10) |xi| {
                try display.setPixel(config.UI_XOFF + 6 * x + xi, config.UI_YOFF + 3 * y + 2, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
            }
        } else {
            for (0..5) |yi| {
                try display.setPixel(config.UI_XOFF + 6 * x + 4, config.UI_YOFF + 3 * y + yi, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
                try display.setPixel(config.UI_XOFF + 6 * x + 5, config.UI_YOFF + 3 * y + yi, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
            }
        }
    }
}


pub fn emitMoves(turnN: usize, moves: [2]Move) !void {
    var b1: [16]u8 = undefined;
    var b2: [16]u8 = undefined;
    const s1 = try moves[0].toString(&b1);
    const s2 = try moves[1].toString(&b2);

    config.lastTurnStr = try std.fmt.bufPrint(&config.lastTurnBuf, "Turn: {d}. {s} {s}", .{ turnN + 1, s1, s2 });
}
