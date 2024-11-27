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

pub const UiAgentMachine = struct {
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

    pub fn handleEvent(self: *Self, event: events.Event, gs: *const GameState, pi: usize) !bool {
        _ = event;

        switch (self.state) {
            .Idle, .Completed => {},
            .Processing => { // generating a move
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


