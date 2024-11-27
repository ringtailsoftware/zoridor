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

var prng: std.Random.Xoshiro256 = undefined;
var rand: std.Random = undefined;
var randInited = false;

pub const PlayerType = enum {
    Human,
    Machine,
};

pub const UiState = enum {
    Idle,
    MovingPawn,
    MovingFence,
    Completed,
};

pub const MachineUi = struct {
    const Self = @This();
    state: UiState,
    nextMove: VerifiedMove,

    pub fn init() Self {
        if (!randInited) {
            randInited = true;
            if (config.RANDOMSEED) |seed| {
                prng = std.rand.DefaultPrng.init(@intCast(seed));
            } else {
                prng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
            }
            rand = prng.random();
        }

        return Self{
            .state = .Idle,
            .nextMove = undefined,
        };
    }

    fn calcPathlen(gs: *const GameState, pi: usize) !usize {
        var pathbuf: PosPath = undefined;
        if (gs.findShortestPath(pi, gs.getPawnPos(pi), &pathbuf)) |path| {
            return path.len;
        } else {
            std.debug.print("pi = {any}\r\n", .{pi});
            std.debug.print("graph = {any}\r\n", .{gs.graph});
            std.debug.print("pawns = {any}\r\n", .{gs.pawns});
            std.debug.print("fences = {any}\r\n", .{gs.fences});
            std.debug.print("numFences = {any}\r\n", .{gs.numFences});
            return error.InvalidMoveErr;
        }
    }

    fn scoreMove(self: *Self, _gs: *const GameState, pi: usize, move: Move) !usize {
        // Calculate an estimated score for potential move, minimax only looking at one move ahead
        // Calculates lengths of my and opponents shortest paths to goal
        // Wins points if this move shortens mine and lengthens theirs
        // Slight scoring bonus for heading towards goal, to tie break equally scored moves
        // Slight scoring bonus for lengthening opponents shortest path to goal
        _ = self;
        var gs = _gs.*; // clone gamestate

        const myPathlenPre = try calcPathlen(&gs, pi);
        const oppPathlenPre = try calcPathlen(&gs, (pi + 1) % config.NUM_PAWNS);
        const myScorePre: isize = @as(isize, @intCast(oppPathlenPre)) - @as(isize, @intCast(myPathlenPre)); // +ve if I'm closer

        const goalDistPre: isize = @as(isize, @intCast(gs.pawns[pi].pos.y)) - @as(isize, @intCast(gs.pawns[pi].goaly));

        const vm = VerifiedMove{ .move = move, .legal = true }; // we know it's safe

        try gs.applyMove(pi, vm); // move in clone

        const myPathlenPost = try calcPathlen(&gs, pi);
        const oppPathlenPost = try calcPathlen(&gs, (pi + 1) % config.NUM_PAWNS);
        const myScorePost: isize = @as(isize, @intCast(oppPathlenPost)) - @as(isize, @intCast(myPathlenPost)); // +ve if I'm closer

        const scoreDel: isize = myScorePost - myScorePre;

        // add a small bonus if reduces my distance to goal
        const goalDistPost: isize = @as(isize, @intCast(gs.pawns[pi].pos.y)) - @as(isize, @intCast(gs.pawns[pi].goaly));
        const goalDistDel = @as(isize, @intCast(@abs(goalDistPre))) - @as(isize, @intCast(@abs(goalDistPost)));

        // small bonus if increases their pathlen
        var r: isize = 0;
        if (myScorePre < 0) { // if I'm losing
            if (oppPathlenPost > oppPathlenPre) { // and this move lengthens their path
                r = 100; // give it a bonus
            }
        }

        if (config.RANDOMNESS > 0) {
            // perturb score by randomness factor
            r += @intCast(rand.int(u32) % config.RANDOMNESS);
        }

        // +100000 is to ensure no result is negative
        return @as(usize, @intCast((scoreDel * 100) + 100000 + (goalDistDel * 10) + r));
    }

    pub fn handleEvent(self: *Self, event: events.Event, gs: *const GameState, pi: usize) !void {
        _ = event;

        switch (self.state) {
            .Idle, .Completed => {},
            .MovingPawn, .MovingFence => { // generating a move
                var moves: [config.MAXMOVES]Move = undefined;
                var scores: [config.MAXMOVES]usize = undefined;
                var bestScore: usize = 0;
                var bestScoreIndex: usize = 0;

                // generate all legal moves
                const numMoves = try gs.getAllLegalMoves(pi, &moves);
                // score them all
                for (0..numMoves) |i| {
                    scores[i] = try self.scoreMove(gs, pi, moves[i]);
                    //std.debug.print("SCORE = {d} MOVE = {any}\r\n", .{scores[i], moves[i]});
                    if (scores[i] > bestScore) {
                        bestScoreIndex = i;
                        bestScore = scores[i];
                    }
                }
                //std.debug.print("SCORE = {d} BESTMOVE = {any}\r\n", .{bestScore, moves[bestScoreIndex]});
                // play highest scoring move
                self.nextMove = try gs.verifyMove(pi, moves[bestScoreIndex]);
                if (!self.nextMove.legal) {
                    return error.InvalidMoveErr;
                }
                self.state = .Completed;
            },
        }
    }

    pub fn selectMoveInteractive(self: *Self, gs: *const GameState, pi: usize) !void {
        _ = gs;
        _ = pi;
        self.state = .MovingPawn; // anything other than .Completed for "working" state
    }

    pub fn getCompletedMove(self: *Self) ?VerifiedMove {
        switch (self.state) {
            .Completed => return self.nextMove,
            else => return null,
        }
    }
};

pub const HumanUi = struct {
    const Self = @This();
    state: UiState,
    nextMove: VerifiedMove,

    pub fn init() Self {
        return Self{
            .state = .Idle,
            .nextMove = undefined,
        };
    }

    fn selectMoveInteractivePawn(self: *Self, gs: *const GameState, pi: usize) !void {
        self.state = .MovingPawn;
        const move = Move{ .pawn = gs.pawns[pi].pos };
        self.nextMove = try gs.verifyMove(pi, move);
    }

    fn selectMoveInteractiveFence(self: *Self, gs: *const GameState, pi: usize) !void {
        self.state = .MovingFence;
        const move = Move{
            .fence = .{ // start fence placement in centre of grid
                .pos = .{
                    .x = config.GRIDSIZE / 2,
                    .y = config.GRIDSIZE / 2,
                },
                .dir = .horz,
            },
        };
        self.nextMove = try gs.verifyMove(pi, move);
    }

    pub fn selectMoveInteractive(self: *Self, gs: *const GameState, pi: usize) !void {
        // default to pawn first
        try self.selectMoveInteractivePawn(gs, pi);
    }

    pub fn getCompletedMove(self: *Self) ?VerifiedMove {
        switch (self.state) {
            .Completed => return self.nextMove,
            else => return null,
        }
    }

    pub fn handleEvent(self: *Self, event: events.Event, gs: *const GameState, pi: usize) !void {
        switch (self.state) {
            .Completed => {},
            .MovingFence => {
                switch (event) {
                    .key => |k| switch (k) {
                        .down => {
                            if (self.nextMove.move.fence.pos.y + 1 < config.GRIDSIZE - 1) {
                                self.nextMove.move.fence.pos.y += 1;
                                self.nextMove = try gs.verifyMove(pi, self.nextMove.move);
                            }
                        },
                        .up => {
                            if (self.nextMove.move.fence.pos.y > 0) {
                                self.nextMove.move.fence.pos.y -= 1;
                                self.nextMove = try gs.verifyMove(pi, self.nextMove.move);
                            }
                        },
                        .left => {
                            if (self.nextMove.move.fence.pos.x > 0) {
                                self.nextMove.move.fence.pos.x -= 1;
                                self.nextMove = try gs.verifyMove(pi, self.nextMove.move);
                            }
                        },
                        .right => {
                            if (self.nextMove.move.fence.pos.x + 1 < config.GRIDSIZE - 1) {
                                self.nextMove.move.fence.pos.x += 1;
                                self.nextMove = try gs.verifyMove(pi, self.nextMove.move);
                            }
                        },
                        .enter => {
                            if (self.nextMove.legal) {
                                self.state = .Completed;
                            }
                        },
                        .ctrl => |c| switch (c) {
                            'i' => { // tab
                                try self.selectMoveInteractivePawn(gs, pi);
                            },
                            else => {},
                        },
                        .char => |c| switch (c) {
                            ' ' => {
                                self.nextMove.move.fence.dir = self.nextMove.move.fence.dir.flip();
                            },
                            else => {},
                        },
                        else => {},
                    },
                    else => {},
                }
            },
            .MovingPawn => {
                // lowest x,y for movement allowed to avoid going offscreen
                var minx: usize = 0;
                if (gs.pawns[pi].pos.x > 1) {
                    minx = gs.pawns[pi].pos.x - config.PAWN_EXPLORE_DIST;
                }
                var miny: usize = 0;
                if (gs.pawns[pi].pos.y > 1) {
                    miny = gs.pawns[pi].pos.y - config.PAWN_EXPLORE_DIST;
                }

                switch (event) {
                    .key => |k| switch (k) {
                        .left => {
                            if (self.nextMove.move.pawn.x > 0) {
                                if (self.nextMove.move.pawn.x - 1 >= minx) {
                                    self.nextMove.move.pawn.x -= 1;
                                    self.nextMove = try gs.verifyMove(pi, self.nextMove.move);
                                }
                            }
                        },
                        .right => {
                            if (self.nextMove.move.pawn.x < config.GRIDSIZE - 1) {
                                if (self.nextMove.move.pawn.x + 1 <= gs.pawns[pi].pos.x + config.PAWN_EXPLORE_DIST) {
                                    self.nextMove.move.pawn.x += 1;
                                    self.nextMove = try gs.verifyMove(pi, self.nextMove.move);
                                }
                            }
                        },
                        .up => {
                            if (self.nextMove.move.pawn.y > 0) {
                                if (self.nextMove.move.pawn.y - 1 >= miny) {
                                    self.nextMove.move.pawn.y -= 1;
                                    self.nextMove = try gs.verifyMove(pi, self.nextMove.move);
                                }
                            }
                        },
                        .down => {
                            if (self.nextMove.move.pawn.y < config.GRIDSIZE - 1) {
                                if (self.nextMove.move.pawn.y + 1 <= gs.pawns[pi].pos.y + config.PAWN_EXPLORE_DIST) {
                                    self.nextMove.move.pawn.y += 1;
                                    self.nextMove = try gs.verifyMove(pi, self.nextMove.move);
                                }
                            }
                        },
                        .enter => {
                            if (self.nextMove.legal) {
                                self.state = .Completed;
                            }
                        },
                        .ctrl => |c| switch (c) {
                            'i' => { // tab
                                if (gs.pawns[pi].numFencesRemaining > 0) {
                                    try self.selectMoveInteractiveFence(gs, pi);
                                }
                            },
                            else => {},
                        },
                        else => {},
                    },
                    else => {},
                }
            },
            .Idle => {},
        }
    }

    pub fn paint(self: *Self, display: *Display) !void {
        switch (self.state) {
            .Completed => {},
            .MovingPawn => {
                if (self.nextMove.legal) {
                    drawPawnHighlight(display, self.nextMove.move.pawn.x, self.nextMove.move.pawn.y, .green);
                } else {
                    drawPawnHighlight(display, self.nextMove.move.pawn.x, self.nextMove.move.pawn.y, .red);
                }
            },
            .MovingFence => {
                if ((time.millis() / 100) % 5 > 0) { // flash highlight
                    if (self.nextMove.legal) {
                        drawFenceHighlight(display, self.nextMove.move.fence.pos.x, self.nextMove.move.fence.pos.y, .white, self.nextMove.move.fence.dir);
                    } else {
                        drawFenceHighlight(display, self.nextMove.move.fence.pos.x, self.nextMove.move.fence.pos.y, .red, self.nextMove.move.fence.dir);
                    }
                }
            },
            .Idle => {},
        }
    }
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

fn drawPawnHighlight(display: *Display, x: usize, y: usize, c: color.Color) void {
    if (config.mini) {
        try display.setPixel(config.UI_XOFF + 4 * x + config.label_extra_w - 1, config.UI_YOFF + 2 * y, .{ .fg = .white, .bg = c, .c = '[', .bold = false });
        try display.setPixel(config.UI_XOFF + 4 * x + config.label_extra_w + 2, config.UI_YOFF + 2 * y, .{ .fg = .white, .bg = c, .c = ']', .bold = false });
    } else {
        try display.setPixel(config.UI_XOFF + 6 * x - 1, config.UI_YOFF + 3 * y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(config.UI_XOFF + 6 * x + 4, config.UI_YOFF + 3 * y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(config.UI_XOFF + 6 * x - 1, config.UI_YOFF + 3 * y + 1, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(config.UI_XOFF + 6 * x + 4, config.UI_YOFF + 3 * y + 1, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
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

fn drawFenceHighlight(display: *Display, x: usize, y: usize, c: color.Color, dir: Dir) void {
    if (config.mini) {
        // x,y is most NW square adjacent to fence
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
