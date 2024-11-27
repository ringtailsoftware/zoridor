const config = @import("config.zig");
const GameState = @import("gamestate.zig").GameState;
const Move = @import("gamestate.zig").Move;
const VerifiedMove = @import("gamestate.zig").VerifiedMove;
const mibu = @import("mibu");
const events = mibu.events;
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

    pub fn getAnyLegalMove(self: *const Self, gs: *const GameState, pi: usize) !VerifiedMove{
        _ = self;
        while(true) {
            const move = switch(rand.int(usize) % 3) {
                0 => Move{ .pawn = .{ .x = @intCast(rand.int(usize)%9), .y = @intCast(rand.int(usize)%9) } },
                1 => Move{ .fence = .{ .pos = .{ .x = @intCast(rand.int(usize)%8), .y = @intCast(rand.int(usize)%8) }, .dir = .vert } },
                2 => Move{ .fence = .{ .pos = .{ .x = @intCast(rand.int(usize)%8), .y = @intCast(rand.int(usize)%8) }, .dir = .horz } },
                else => unreachable,
            };
            const vm = try gs.verifyMove(pi, move);
            if (vm.legal) {
                return vm;
            }
        }
    }

    pub fn handleEvent(self: *Self, event: events.Event, gs: *const GameState, pi: usize) !bool {
        _ = event;

        switch (self.state) {
            .Idle, .Completed => {},
            .Processing => { // generating a move
                self.nextMove = try self.getAnyLegalMove(gs, pi);
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


