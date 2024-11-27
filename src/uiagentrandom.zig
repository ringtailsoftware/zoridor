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

var prng: std.Random.Xoshiro256 = undefined;
var rand: std.Random = undefined;
var randInited = false;

const UiState = enum {
    Idle,
    Processing,
    Completed,
};

pub const UiAgentRandom = struct {
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

    pub fn paint(self: *Self, display: *Display) !void {
        _ = self;
        _ = display;
    }

    pub fn handleEvent(self: *Self, event: events.Event, gs: *const GameState, pi: usize) !bool {
        _ = event;

        switch (self.state) {
            .Idle, .Completed => {},
            .Processing => { // generating a move
                var moves: [config.MAXMOVES]Move = undefined;
                // generate all legal moves
                const numMoves = try gs.getAllLegalMoves(pi, &moves);
                // play random move
                self.nextMove = try gs.verifyMove(pi, moves[rand.int(usize) % numMoves]);
                if (!self.nextMove.legal) {
                    return error.InvalidMoveErr;
                }
                self.state = .Completed;
            },
        }
        return false;
    }

    pub fn selectMoveInteractive(self: *Self, gs: *const GameState, pi: usize) !void {
        _ = gs;
        _ = pi;
        self.state = .Processing;
    }

    pub fn getCompletedMove(self: *Self) ?VerifiedMove {
        switch (self.state) {
            .Completed => return self.nextMove,
            else => return null,
        }
    }
};


