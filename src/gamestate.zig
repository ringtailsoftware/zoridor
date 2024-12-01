const std = @import("std");
const config = @import("config.zig");
const BitGraph = @import("graph.zig").BitGraph;

pub const Pos = BitGraph.CoordPos;

pub const Move = union(enum) {
    const Self = @This();
    pawn: Pos,
    fence: PosDir,

    pub fn toString(self: Self, buf: []u8) ![]u8 {
        switch (self) {
            .pawn => |pawnmove| {
                return std.fmt.bufPrint(buf, "{c}{c}", .{
                    'a' + @as(u8, @intCast(pawnmove.x)),
                    '1' + @as(u8, @intCast(pawnmove.y)),
                });
            },
            .fence => |fencemove| {
                var d: u8 = 'v';
                if (fencemove.dir == .horz) {
                    d = 'h';
                }
                return std.fmt.bufPrint(buf, "{c}{c}{c}", .{
                    'a' + @as(u8, @intCast(fencemove.pos.x)),
                    '1' + @as(u8, @intCast(fencemove.pos.y)),
                    d,
                });
            },
        }
    }
};

pub const VerifiedMove = struct {
    move: Move,
    legal: bool,
};

pub const Dir = enum(u1) {
    vert = 0,
    horz = 1,

    pub fn flip(dir: Dir) Dir {
        switch (dir) {
            .vert => return .horz,
            .horz => return .vert,
        }
    }
};

pub const PosDir = struct {
    pos: Pos,
    dir: Dir,
};

pub const Pawn = struct {
    pos: Pos,
    goaly: usize, // end game line
    numFencesRemaining: usize,
};

pub const PosPath = [BitGraph.MAXPATH]Pos;

pub const GameState = struct {
    const Self = @This();

    graph: BitGraph,
    pawns: [config.NUM_PAWNS]Pawn,
    fences: [config.NUM_FENCES]PosDir,
    numFences: usize,

    pub fn init() Self {
        var g = BitGraph.init();
        g.addGridEdges();

        return Self{
            .graph = g,
            .pawns = .{
                // pawn starting positions
                .{ .goaly = 8, .pos = .{ .x = 4, .y = 0 }, .numFencesRemaining = config.NUM_FENCES / 2 },
                .{ .goaly = 0, .pos = .{ .x = 4, .y = 8 }, .numFencesRemaining = config.NUM_FENCES / 2 },
            },
            .numFences = 0,
            .fences = undefined,
        };
    }

    fn isLegalMove(self: *const Self, pi: usize, move: Move) !bool {
        switch (move) {
            .pawn => |pawnmove| {
                return self.canMovePawn(pi, pawnmove);
            },
            .fence => |fencemove| {
                return (self.pawns[pi].numFencesRemaining > 0) and self.canPlaceFence(fencemove);
            },
        }
    }

    pub fn getFences(self: *const Self) []const PosDir {
        return self.fences[0..self.numFences];
    }

    pub fn hasGameEnded(self: *const Self) bool {
        for (0..config.NUM_PAWNS) |i| {
            if (self.hasWon(i)) {
                return true;
            }
        }
        return false;
    }

    pub fn hasWon(self: *const Self, pi: usize) bool {
        return self.pawns[pi].pos.y == self.pawns[pi].goaly;
    }

    pub fn verifyMove(self: *const Self, pi: usize, move: Move) !VerifiedMove {
        return .{
            .move = move,
            .legal = try self.isLegalMove(pi, move),
        };
    }

    pub fn applyMove(self: *Self, pi: usize, vmove: VerifiedMove) !void {
        switch (vmove.move) {
            .pawn => |pawnmove| {
                self.movePawn(pi, pawnmove);
            },
            .fence => |fencemove| {
                self.placeFence(pi, fencemove);
            },
        }
    }

    pub fn getPawnPos(self: *const Self, pi: usize) Pos {
        return self.pawns[pi].pos;
    }

    pub fn getPawnGoal(self: *const Self, pi: usize) BitGraph.NodeIdRange {
        return .{
            .min = BitGraph.coordPosToNodeId(.{ .x = 0, .y = @intCast(self.pawns[pi].goaly) }),
            .max = BitGraph.coordPosToNodeId(.{ .x = 8, .y = @intCast(self.pawns[pi].goaly) }),
        };
    }

    fn rerouteAroundPawns(self: *const Self, pi: usize) BitGraph {
        var graph = self.graph;

        for (0..self.pawns.len) |i| {
            if (i != pi) { // ignore self
                // found an opponent pawn
                // if opp pawn is on our goal line, don't remove it - as it's legal to end game by jumping onto it
                if (self.pawns[i].pos.y != self.pawns[pi].goaly) {
                    // clone graph
                    // where opp pawn is, connect all of their outgoing edges to their incoming, so the node ceases to exist
                    // this will enable jumping over it
                    graph = BitGraph.clone(&graph);
                    const ni = BitGraph.coordPosToNodeId(.{ .x = @intCast(self.pawns[i].pos.x), .y = @intCast(self.pawns[i].pos.y) });
                    graph.delNode(ni);
                }
            }
        }
        return graph;
    }

    pub fn getAllLegalMoves(self: *const Self, pi: usize, moves: *[config.MAXMOVES]Move, maxMoves:usize) !usize {
        // maxMoves = 0, generates all legal moves
        // Any other maxMoves value limits it
        var numMoves: usize = 0;

        // find all possible pawn moves -2 -> +2 around current pos
        var px = @as(isize, @intCast(self.pawns[pi].pos.x)) - 2;
        while (px <= self.pawns[pi].pos.x + 2) : (px += 1) {
            var py = @as(isize, @intCast(self.pawns[pi].pos.y)) - 2;
            while (py <= self.pawns[pi].pos.y + 2) : (py += 1) {
                if (px >= 0 and px < 9 and py >= 0 and py < 9) { // on grid
                    const move = Move{ .pawn = .{ .x = @intCast(px), .y = @intCast(py) } };
                    const vm = try self.verifyMove(pi, move);
                    if (vm.legal) {
                        moves[numMoves] = move;
                        numMoves += 1;
                        if (maxMoves != 0 and numMoves >= maxMoves) {
                            return numMoves;
                        }
                    }
                }
            }
        }

        // find all possible fence moves
        if (self.pawns[pi].numFencesRemaining > 0) {
            for (0..9 - 1) |fx| {
                for (0..9 - 1) |fy| {
                    const movev = Move{ .fence = .{ .pos = .{ .x = @intCast(fx), .y = @intCast(fy) }, .dir = .vert } };
                    const moveh = Move{ .fence = .{ .pos = .{ .x = @intCast(fx), .y = @intCast(fy) }, .dir = .horz } };
                    const vmv = try self.verifyMove(pi, movev);
                    const vmh = try self.verifyMove(pi, moveh);
                    if (vmv.legal) {
                        moves[numMoves] = movev;
                        numMoves += 1;
                        if (maxMoves != 0 and numMoves >= maxMoves) {
                            return numMoves;
                        }
                    }
                    if (vmh.legal) {
                        moves[numMoves] = moveh;
                        numMoves += 1;
                        if (maxMoves != 0 and numMoves >= maxMoves) {
                            return numMoves;
                        }
                    }
                }
            }
        }

        return numMoves;
    }

    pub fn canMovePawn(self: *const Self, pi: usize, targetPos: Pos) bool {
        std.debug.assert(targetPos.x < 9 and targetPos.y < 9);
        if (targetPos.x == self.pawns[pi].pos.x and targetPos.y == self.pawns[pi].pos.y) { // lands on self, no movement
            return false;
        }

        var graph = self.graph;

        for (0..self.pawns.len) |i| {
            if (i != pi) { // ignore self
                if (targetPos.x == self.pawns[i].pos.x and targetPos.y == self.pawns[i].pos.y) {
                    // move will land on a pawn, not allowed, unless it's a winning move
                    if (targetPos.y != self.pawns[pi].goaly) {
                        return false;
                    }
                } else {
                    graph = self.rerouteAroundPawns(pi);
                }
            }
        }

        const a = BitGraph.CoordPos{ .x = @intCast(self.pawns[pi].pos.x), .y = @intCast(self.pawns[pi].pos.y) };
        const b = BitGraph.CoordPos{ .x = @intCast(targetPos.x), .y = @intCast(targetPos.y) };

        return graph.hasCoordEdgeUni(a, b);
    }

    pub fn movePawn(self: *Self, pi: usize, targetPos: Pos) void {
        std.debug.assert(self.canMovePawn(pi, targetPos));
        self.pawns[pi].pos = targetPos;
    }

    pub fn canPlaceFence(self: *const Self, pd: PosDir) bool {
        // To place a fence:
        // - it must cut two existing edges in graph
        // a-b
        // | |
        // c-d

        const a = BitGraph.CoordPos{ .x = @intCast(pd.pos.x), .y = @intCast(pd.pos.y) };
        const b = BitGraph.CoordPos{ .x = @intCast(pd.pos.x + 1), .y = @intCast(pd.pos.y) };
        const c = BitGraph.CoordPos{ .x = @intCast(pd.pos.x), .y = @intCast(pd.pos.y + 1) };
        const d = BitGraph.CoordPos{ .x = @intCast(pd.pos.x + 1), .y = @intCast(pd.pos.y + 1) };

        // (if uni edge exists, then it's also bi-directionally connected)

        switch (pd.dir) {
            .vert => {
                if (!(self.graph.hasCoordEdgeUni(a, b) and self.graph.hasCoordEdgeUni(c, d))) {
                    return false;
                }
            },
            .horz => {
                if (!(self.graph.hasCoordEdgeUni(a, c) and self.graph.hasCoordEdgeUni(b, d))) {
                    return false;
                }
            },
        }

        // - must not hit any existing fences
        for (self.fences[0..self.numFences]) |f| {
            if (f.pos.x == pd.pos.x and f.pos.y == pd.pos.y) {
                return false;
            }

            // check if fence extents overlap when aligned
            if (f.dir == pd.dir) {
                switch (f.dir) {
                    .vert => {
                        if (f.pos.x == pd.pos.x and @abs(@as(isize, @intCast(f.pos.y)) - @as(isize, @intCast(pd.pos.y))) < 2) {
                            return false;
                        }
                    },
                    .horz => {
                        if (f.pos.y == pd.pos.y and @abs(@as(isize, @intCast(f.pos.x)) - @as(isize, @intCast(pd.pos.x))) < 2) {
                            return false;
                        }
                    },
                }
            }
        }

        // - it must not stop any pawn from having a path to goal
        for (self.pawns, 0..) |pawn, pi| {
            const start = BitGraph.coordPosToNodeId(BitGraph.CoordPos{ .x = @intCast(pawn.pos.x), .y = @intCast(pawn.pos.y) });
            var pathbuf: [BitGraph.MAXPATH]BitGraph.NodeId = undefined;

            var gs = self.*; // clone gamestate
            placeFenceToGraph(&gs.graph, pd); // place fence
            var g = gs.rerouteAroundPawns(pi); // make graph skip over pawn locations
            if (null == g.findShortestPath(start, gs.getPawnGoal(pi), &pathbuf, true)) { // look for any path to goal
                return false;
            }
        }

        return true;
    }

    pub fn findShortestPath(self: *const Self, pi: usize, start: Pos, posPathBuf: *PosPath) ?[]Pos {
        const g = self.rerouteAroundPawns(pi); // make graph skip over pawn locations
        var nodePathBuf: [BitGraph.MAXPATH]BitGraph.NodeId = undefined;
        const nodePathO = g.findShortestPath(BitGraph.coordPosToNodeId(start), self.getPawnGoal(pi), &nodePathBuf, false);

        if (nodePathO) |nodePath| {
            var posPathLen: usize = 0;
            for (nodePath[1..nodePath.len]) |n| { // skip first element, as it's starting node
                posPathBuf[posPathLen] = BitGraph.nodeIdToCoordPos(n);
                posPathLen += 1;
            }
            return posPathBuf[0..posPathLen];
        } else {
            return null;
        }
    }

    pub fn placeFence(self: *Self, pi: usize, pd: PosDir) void {
        std.debug.assert(self.canPlaceFence(pd));
        std.debug.assert(self.numFences < config.NUM_FENCES);
        placeFenceToGraph(&self.graph, pd);
        self.fences[self.numFences] = pd;
        self.numFences += 1;
        self.pawns[pi].numFencesRemaining -= 1;
    }

    fn placeFenceToGraph(graph: *BitGraph, pd: PosDir) void {
        const a = BitGraph.CoordPos{ .x = @intCast(pd.pos.x), .y = @intCast(pd.pos.y) };
        const b = BitGraph.CoordPos{ .x = @intCast(pd.pos.x + 1), .y = @intCast(pd.pos.y) };
        const c = BitGraph.CoordPos{ .x = @intCast(pd.pos.x), .y = @intCast(pd.pos.y + 1) };
        const d = BitGraph.CoordPos{ .x = @intCast(pd.pos.x + 1), .y = @intCast(pd.pos.y + 1) };

        switch (pd.dir) {
            .vert => {
                graph.delCoordEdgeBi(a, b);
                graph.delCoordEdgeBi(c, d);
            },
            .horz => {
                graph.delCoordEdgeBi(a, c);
                graph.delCoordEdgeBi(b, d);
            },
        }
    }

    pub fn print(self: *const Self) void {
        self.graph.print();
    }
};
