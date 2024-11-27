const time = @import("time.zig");
const config = @import("config.zig");
const GameState = @import("gamestate.zig").GameState;
const PosDir = @import("gamestate.zig").PosDir;
const PosPath = @import("gamestate.zig").PosPath;
const Pos = @import("gamestate.zig").Pos;
const Dir = @import("gamestate.zig").Dir;
const Move = @import("gamestate.zig").Move;
const VerifiedMove = @import("gamestate.zig").VerifiedMove;
const mibu = @import("mibu");
const events = mibu.events;
const term = mibu.term;
const color = mibu.color;
const std = @import("std");
const Display = @import("display.zig").Display;

const UiState = enum {
    Idle,
    MovingPawn,
    MovingFence,
    Completed,
};

pub const UiAgentHuman = struct {
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

    pub fn handleEvent(self: *Self, event: events.Event, gs: *const GameState, pi: usize) !bool {
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
        return true;
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

