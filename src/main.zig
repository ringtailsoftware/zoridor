const std = @import("std");

// command line parsing
const yazap = @import("yazap");

const Display = @import("display.zig").Display;

const io = std.io;

const mibu = @import("mibu");
const events = mibu.events;
const term = mibu.term;
const color = mibu.color;

const time = @import("time.zig");

const xoff = 3;
const yoff = 2;
var mini = false;
const label_extra_w = 3;

const COLUMN_LABEL_START = 'a';
const ROW_LABEL_START = '1';

var RANDOMSEED:?u32 = null;   // null = set from clock
const RANDOMNESS = 10;

const NUM_PAWNS = 2;
const NUM_FENCES_PER_PLAYER = 10;
const GRIDSIZE:usize = 9;

const PAWN_EXPLORE_DIST = 2;    // how many squares away to allow interactive exploring for pawn move

const MAXMOVES = (5*5) + 2*(GRIDSIZE-1)*(GRIDSIZE-1);   // largest possible number of legal moves, pawnmoves + fencemoves
const MAXPATH = GRIDSIZE*GRIDSIZE;  // largest possible path a pawn could take to reach goal (overkill)

const pawnColour = [NUM_PAWNS]color.Color{.yellow, .magenta};
const fenceColour:color.Color = .white;

var playForever = false;
var players:[NUM_PAWNS]PlayerType = .{.Human, .Machine};

// for holding last turn string
var lastTurnBuf:[32]u8 = undefined;
var lastTurnStr:?[]u8 = null;

var wins:[NUM_PAWNS]usize = .{0,0};

var prng: std.Random.Xoshiro256 = undefined;
var rand: std.Random = undefined;
var randInited = false;

pub const Dir = enum {
    vert,
    horz,

    pub fn flip(dir:Dir) Dir {
        switch(dir) {
            .vert => return .horz,
            .horz => return .vert,
        }
    }
};

pub const PlayerType = enum {
    Human,
    Machine,
};

pub const PieceType = enum {
    fence,
    pawn,
};

pub const Pawn = struct {
    pos: Pos, // 0 -> (GRIDSIZE-1), 0 -> (GRIDSIZE-1)
    goaly: usize,   // end game line
    fences: [NUM_FENCES_PER_PLAYER]PosDir, // 0 -> (GRIDSIZE-2), 0 -> (GRIDSIZE-2)
    numFences: usize,
};

pub const UiState = enum {
    Idle,
    MovingPawn,
    MovingFence,
    Completed,
};

pub const Pos = struct {
    x:usize,
    y:usize,
};

pub const PosDir = struct {
    x:usize,
    y:usize,
    dir:Dir
};

pub const Move = union(enum) {
    const Self = @This();
    pawn: Pos,
    fence: PosDir,
    skip: void,

    pub fn toString(self: Self, buf:[]u8) ![]u8{
        switch(self) {
            else => {
                return std.fmt.bufPrint(buf, "", .{});
            },
            .pawn => |pawnmove| {
                return std.fmt.bufPrint(buf, "{c}{c}", .{
                    'a' + @as(u8, @intCast(pawnmove.x)),
                    '1' + @as(u8, @intCast(pawnmove.y)),
                });
            },
            .fence => |fencemove| {
                var d:u8 = 'v';
                if (fencemove.dir == .horz) {
                    d = 'h';
                }
                return std.fmt.bufPrint(buf, "{c}{c}{c}", .{
                    'a' + @as(u8, @intCast(fencemove.x)),
                    '1' + @as(u8, @intCast(fencemove.y)),
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

pub const MachineUi = struct {
    const Self = @This();
    state:UiState,
    nextMove:VerifiedMove,

    pub fn init() Self {
        if (!randInited) {
            randInited = true;
            if (RANDOMSEED) |seed| {
                prng = std.rand.DefaultPrng.init(@intCast(seed));
            } else {
                prng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
            }
            rand = prng.random();
        }

        return Self {
            .state = .Idle,
            .nextMove = undefined,
        };
    }

    pub fn scoreMove(self: *Self, _gs:*const GameState, pi:usize, move:Move) !usize {
        // Calculate an estimated score for potential move, minimax only looking at one move ahead
        // Calculates lengths of my and opponents shortest paths to goal
        // Wins points if this move shortens mine and lengthens theirs
        // Slight scoring bonus for heading towards goal, to tie break equally scored moves
        // Slight scoring bonus for lengthening opponents shortest path to goal

        var path:[MAXPATH]Pos = undefined;
        var gs = _gs.*;  // clone gamestate

        const myPathlenPre = try self.findPath(&gs, gs.pawns[pi].pos, gs.pawns[pi].goaly, &path);
        const oppPathlenPre = try self.findPath(&gs, gs.pawns[(pi+1) % NUM_PAWNS].pos, gs.pawns[(pi+1) % NUM_PAWNS].goaly, &path);
        const myScorePre:isize = @as(isize, @intCast(oppPathlenPre)) - @as(isize, @intCast(myPathlenPre));    // +ve if I'm closer

        const goalDistPre:isize = @as(isize, @intCast(gs.pawns[pi].pos.y)) - @as(isize, @intCast(gs.pawns[pi].goaly));

        const vm = VerifiedMove{.move = move, .legal = true};   // we know it's safe

        try gs.applyMove(pi, vm);   // move in clone

        const myPathlenPost = try self.findPath(&gs, gs.pawns[pi].pos, gs.pawns[pi].goaly, &path);
        const oppPathlenPost = try self.findPath(&gs, gs.pawns[(pi+1) % NUM_PAWNS].pos, gs.pawns[(pi+1) % NUM_PAWNS].goaly, &path);
        const myScorePost:isize = @as(isize, @intCast(oppPathlenPost)) - @as(isize, @intCast(myPathlenPost));    // +ve if I'm closer

        const scoreDel:isize = myScorePost - myScorePre;

        // add a small bonus if reduces my distance to goal
        const goalDistPost:isize = @as(isize, @intCast(gs.pawns[pi].pos.y)) - @as(isize, @intCast(gs.pawns[pi].goaly));
        const goalDistDel = @as(isize, @intCast(@abs(goalDistPre))) - @as(isize, @intCast(@abs(goalDistPost)));

        // small bonus if increases their pathlen
        var r:isize = 0;
        if (oppPathlenPost > oppPathlenPre) {
            r = 100;
        }

        if (RANDOMNESS > 0) {
            // perturb score by randomness factor
            r += rand.int(u32) % RANDOMNESS;
        }

        // +100000 is to ensure no result is negative
        return @as(usize, @intCast((scoreDel*100) + 100000 + goalDistDel + r));
    }

    pub fn findPath(self: *Self, gs:*const GameState, startpos:Pos, goaly:usize, path:*[MAXPATH]Pos) !usize{
        _ = self;

        // find shortest path between startpos and goal line
        // flood fill entire grid, noting path cost to get there if lower than previously known
        // once cost to get to every node is known, work backwards from cheapest path on goal line to give path
        // A* or Dijkstra's would be faster here

        const Node = struct {
            parent:Pos,
            pathCost:?usize,
        };

        var nodes:[GRIDSIZE*GRIDSIZE]Node = undefined;

        for (0..GRIDSIZE*GRIDSIZE) |i| {
            nodes[i] = .{
                .pathCost = null,   // unknown
                .parent = .{.x = 0, .y = 0},
            };
        }

        // stack of positions to expand
        var toExpand:[GRIDSIZE*GRIDSIZE]Pos = undefined;
        var toExpandTopIndex:usize = 0;

        // push starting node position to be expanded
        toExpand[toExpandTopIndex] = startpos;
        toExpandTopIndex += 1;
        nodes[startpos.y * GRIDSIZE + startpos.x].pathCost = 0;

        while(toExpandTopIndex > 0) {
            // pop
            const pos = toExpand[toExpandTopIndex-1];   // new pos to explore
            toExpandTopIndex -= 1;

            const n = nodes[pos.y * GRIDSIZE + pos.x];   // node being expanded

            var xo:isize = -1;
            while(xo <= 1) : (xo += 1) {
                var yo:isize = -1;
                while(yo <= 1) : (yo += 1) {
                    if (!(xo == 0 or yo == 0)) {    // consider orthogonal moves only
                        continue;
                    }
                    var px:isize = @as(isize, @intCast(pos.x)) + xo;
                    var py:isize = @as(isize, @intCast(pos.y)) + yo;

                    // clip to bounds
                    if (px < 0) {
                        px = 0;
                    }
                    if (px > GRIDSIZE-1) {
                        px = GRIDSIZE-1;
                    }
                    if (py < 0) {
                        py = 0;
                    }
                    if (py > GRIDSIZE-1) {
                        py = GRIDSIZE-1;
                    }

                    // m is the new proposed move
                    const m = .{.pawn = .{.x = @as(usize, @intCast(px)), .y = @as(usize, @intCast(py))}};

                    // check doesn't hit fences, ignore pawn collisions
                    if (try gs.isLegalPawnMove1Fence(pos, m)) {
                        var n2 = &nodes[m.pawn.y * GRIDSIZE + m.pawn.x];   // ref to node at end of move

                        var doExplore = false;

                        if (n2.pathCost) |existingCost| {
                            if (n.pathCost.? + 1 < existingCost) {
                                doExplore = true;
                            }
                        } else {    // unvisited node
                            doExplore = true;
                        }

                        if (doExplore) {
                            n2.pathCost = n.pathCost.? + 1;
                            n2.parent = pos;

                            // push
                            toExpand[toExpandTopIndex] = .{.x = m.pawn.x, .y = m.pawn.y};
                            toExpandTopIndex += 1;
                        }
                    }
                }
            }
        }

        // now nodes contains all paths
        // for (0..GRIDSIZE) |y| {
        //    for (0..GRIDSIZE) |x| {
        //        std.debug.print("{any} ", .{nodes[y*GRIDSIZE+x].pathCost});
        //    }
        //    std.debug.print("\r\n", .{});
        // }
        // std.debug.print("\r\n", .{});

        // find cheapest node on the goal line, then work backwards from there to find path
        var bestPathCost:usize = undefined;
        var bestx:?usize = null;
        var first = true;
        for (0..GRIDSIZE) |x| {
            if (nodes[goaly*GRIDSIZE+x].pathCost) |pathCost| {
                if (first or pathCost < bestPathCost) {
                    first = false;
                    bestx = x;
                    bestPathCost = pathCost;
                }
            }
        }

        // Assume that there is a bestx, according to game rules there must be a path to goal

        var x = bestx.?;
        var y = goaly;

        // work backwards from the the target until reaching the root
        const pathLen = nodes[y*GRIDSIZE+x].pathCost.?;
        while(true) {
            const n = nodes[y*GRIDSIZE+x];
            path[n.pathCost.?] = .{.x = x, .y = y};   // need to reverse path, but know the index as it's the cost
            if (n.pathCost == 0) {  // reached root node, starting pos
                break;
            }
            x = n.parent.x;
            y = n.parent.y;
        }

        return pathLen;
    }

    pub fn handleEvent(self: *Self, event:events.Event, gs:*const GameState, pi:usize) !void {
        _ = event;

        switch(self.state) {
            .Idle, .Completed => {
            },
            .MovingPawn, .MovingFence => {  // generating a move
                var moves:[MAXMOVES]Move = undefined;
                var scores:[MAXMOVES]usize = undefined;
                var bestScore:usize = 0;
                var bestScoreIndex:usize = 0;

                // generate all legal moves
                const numMoves = try gs.getAllLegalMoves(pi, &moves);
                // score them all
                for (0..numMoves) |i| {
                    scores[i] = try self.scoreMove(gs, pi, moves[i]);
                    if (scores[i] > bestScore) {
                        bestScoreIndex = i;
                        bestScore = scores[i];
                    }
                }
                // play highest scoring move
                self.nextMove = try gs.verifyMove(pi, moves[bestScoreIndex]);
                if (!self.nextMove.legal) {
                    return error.InvalidMoveErr;
                }
                self.state = .Completed;
            }
        }
    }

    pub fn selectMoveInteractive(self: *Self, gs:*const GameState, pi:usize) !void {
        _ = gs;
        _ = pi;
        self.state = .MovingPawn;   // anything other than .Completed for "working" state
    }

    pub fn getCompletedMove(self: *Self) ?VerifiedMove {
        switch(self.state) {
            .Completed => return self.nextMove,
            else => return null,
        }
    }
};

pub const HumanUi = struct {
    const Self = @This();
    state:UiState,
    nextMove:VerifiedMove,

    pub fn init() Self {
        return Self {
            .state = .Idle,
            .nextMove = undefined,
        };
    }

    fn selectMoveInteractivePawn(self: *Self, gs:*const GameState, pi:usize) !void {
        self.state = .MovingPawn;
        const move = Move{.pawn = gs.pawns[pi].pos};
        self.nextMove = try gs.verifyMove(pi, move);
    }

    fn selectMoveInteractiveFence(self: *Self, gs:*const GameState, pi:usize) !void {
        self.state = .MovingFence;
        const move = Move{
            .fence = .{ // start fence placement in centre of grid
                .x = GRIDSIZE/2,
                .y = GRIDSIZE/2,
                .dir = .horz,
            },
        };
        self.nextMove = try gs.verifyMove(pi, move);
    }

    pub fn selectMoveInteractive(self: *Self, gs:*const GameState, pi:usize) !void {
        // default to pawn first
        try self.selectMoveInteractivePawn(gs, pi);
    }

    pub fn getCompletedMove(self: *Self) ?VerifiedMove {
        switch(self.state) {
            .Completed => return self.nextMove,
            else => return null,
        }
    }

    pub fn handleEvent(self: *Self, event:events.Event, gs:*const GameState, pi:usize) !void {
        switch(self.state) {
            .Completed => {
            },
            .MovingFence => {
                switch (event) {
                    .key => |k| switch (k) {
                        .down => {
                            if (self.nextMove.move.fence.y + 1 < GRIDSIZE-1) {
                                self.nextMove.move.fence.y += 1;
                                self.nextMove = try gs.verifyMove(pi, self.nextMove.move);
                            }
                        },
                        .up => {
                            if (self.nextMove.move.fence.y > 0) {
                                self.nextMove.move.fence.y -= 1;
                                self.nextMove = try gs.verifyMove(pi, self.nextMove.move);
                            }
                        },
                        .left => {
                            if (self.nextMove.move.fence.x > 0) {
                                self.nextMove.move.fence.x -= 1;
                                self.nextMove = try gs.verifyMove(pi, self.nextMove.move);
                            }
                        },
                        .right => {
                            if (self.nextMove.move.fence.x + 1 < GRIDSIZE-1) {
                                self.nextMove.move.fence.x += 1;
                                self.nextMove = try gs.verifyMove(pi, self.nextMove.move);
                            }
                        },
                        .enter => {
                            if (self.nextMove.legal) {
                                self.state = .Completed;
                            }
                        },
                        .ctrl => |c| switch (c) {
                            'i' => {    // tab
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
                var minx:usize = 0;
                if (gs.pawns[pi].pos.x > 1) {
                    minx = gs.pawns[pi].pos.x - PAWN_EXPLORE_DIST;
                }
                var miny:usize = 0;
                if (gs.pawns[pi].pos.y > 1) {
                    miny = gs.pawns[pi].pos.y - PAWN_EXPLORE_DIST;
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
                            if (self.nextMove.move.pawn.x < GRIDSIZE-1) {
                                if (self.nextMove.move.pawn.x + 1 <= gs.pawns[pi].pos.x + PAWN_EXPLORE_DIST) {
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
                            if (self.nextMove.move.pawn.y < GRIDSIZE-1) {
                                if (self.nextMove.move.pawn.y + 1 <= gs.pawns[pi].pos.y + PAWN_EXPLORE_DIST) {
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
                            'i' => {    // tab
                                if (gs.pawns[pi].numFences < NUM_FENCES_PER_PLAYER) {
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

    pub fn paint(self: *Self, display:*Display) !void {
        switch(self.state) {
            .Completed => {
            },
            .MovingPawn => {
                if (self.nextMove.legal) {
                    drawPawnHighlight(display, self.nextMove.move.pawn.x, self.nextMove.move.pawn.y, .green);
                } else {
                    drawPawnHighlight(display, self.nextMove.move.pawn.x, self.nextMove.move.pawn.y, .red);
                }
            },
            .MovingFence => {
                if ((time.millis() / 100) % 5 > 0) {    // flash highlight
                    if (self.nextMove.legal) {
                        drawFenceHighlight(display, self.nextMove.move.fence.x, self.nextMove.move.fence.y, .white, self.nextMove.move.fence.dir);
                    } else {
                        drawFenceHighlight(display, self.nextMove.move.fence.x, self.nextMove.move.fence.y, .red, self.nextMove.move.fence.dir);
                    }
                }
            },
            .Idle => {},
        }
    }
};

pub const GameState = struct {
    const Self = @This();
    pawns:[NUM_PAWNS]Pawn,

    pub fn init() Self {
        return Self {
            .pawns = .{
                // pawn starting positions
                .{.goaly = GRIDSIZE-1, .pos=.{.x = (GRIDSIZE-1)/2, .y = 0}, .numFences = 0, .fences = undefined},
                .{.goaly = 0, .pos=.{.x = (GRIDSIZE-1)/2, .y = GRIDSIZE-1}, .numFences = 0, .fences = undefined},
            },
        };
    }

    pub fn movePlayer(self:*Self, pi:usize, x:usize, y:usize) void {
        self.pawns[pi].x = x;
        self.pawns[pi].y = y;
    }

    pub fn verifyMove(self:*const Self, pi:usize, move:Move) !VerifiedMove {
        return .{
            .move = move,
            .legal = try self.isLegalMove(pi, move),
        };
    }

    pub fn hasWon(self:*const Self, pi:usize) bool {
        return self.pawns[pi].pos.y == self.pawns[pi].goaly;
    }

    pub fn getAllLegalMoves(self:*const Self, pi:usize, moves:*[MAXMOVES]Move) !usize {
        var numMoves:usize = 0;

        // find all possible pawn moves -2 -> +2 around current pos
        var px = @as(isize, @intCast(self.pawns[pi].pos.x)) - 2;
        while(px <= self.pawns[pi].pos.x + 2) : (px += 1) {
            var py = @as(isize, @intCast(self.pawns[pi].pos.y)) - 2;
            while(py <= self.pawns[pi].pos.y + 2) : (py += 1) {
                if (px >= 0 and px < GRIDSIZE and py >= 0 and py < GRIDSIZE) {  // on grid
                    const move = Move{.pawn = .{.x = @as(usize, @intCast(px)), .y = @as(usize, @intCast(py))}};
                    const vm = try self.verifyMove(pi, move);
                    if (vm.legal) {
                        moves[numMoves] = move;
                        numMoves += 1;
                    }
                }
            }
        }

        // find all possible fence moves
        for (0..GRIDSIZE-1) |fx| {
            for (0..GRIDSIZE-1) |fy| {
                const movev = Move{.fence = .{.x = fx, .y = fy, .dir = .vert}};
                const moveh = Move{.fence = .{.x = fx, .y = fy, .dir = .horz}};
                const vmv = try self.verifyMove(pi, movev);
                const vmh = try self.verifyMove(pi, moveh);
                if (vmv.legal) {
                    moves[numMoves] = movev;
                    numMoves += 1;
                }
                if (vmh.legal) {
                    moves[numMoves] = moveh;
                    numMoves += 1;
                }
            }
        }

        return numMoves;
    }

    // only check if a 1 step move is illegal due to landing on a pawn
    fn isLegalPawnMove1Pawn(self:*const Self, pos:Pos, move:Move) !bool {
        _ = pos;    // doesn't matter where we started
        switch(move) {
            .skip, .fence => return error.InvalidMoveErr,
            .pawn => |pawnmove| {
                for (self.pawns) |p| {
                    // check landing on (any) player
                    if ((pawnmove.x == p.pos.x and pawnmove.y == p.pos.y)) {
                        return false;
                    }
                }
            }
        }
        return true;
    }

    // check that pawn can still reach goal after fence is placed
    fn isLegalFenceGoalBlocked(self:*const Self, x:usize, y:usize, goaly:usize, pi:usize, move:Move) !bool {
        // similar to findPath(), checks if goal line is reachable once move is made
        // flood fills until goal is reached
        // A* or Dijkstra's would be faster here
        switch(move) {
            .fence => {
                var gs = self.*;  // clone gamestate
                const vm = VerifiedMove{.move = move, .legal = true};   // we know it's safe at this point, except for blocking
                try gs.applyMove(pi, vm);   // place fence in clone

                var visited:[GRIDSIZE*GRIDSIZE]bool = undefined;
                var toExpand:[GRIDSIZE*GRIDSIZE]Pos = undefined;
                var toExpandTopIndex:usize = 0;

                for (0..GRIDSIZE*GRIDSIZE) |i| {
                    visited[i] = false;
                }

                // push starting node
                toExpand[toExpandTopIndex] = .{.x=x, .y=y};
                visited[y*GRIDSIZE+x] = true;
                toExpandTopIndex += 1;
                
                const xos = [4]isize {-1, 0, 1, 0};
                const yos = [4]isize {0, -1, 0, 1};

                while(toExpandTopIndex > 0) {
                    // pop
                    const pos = toExpand[toExpandTopIndex-1];
                    toExpandTopIndex -= 1;

                    if (pos.y == goaly) {
                        return true;    // reached goal
                    }

                    for (0..4) |i| {    // all four directions
                        var px:isize = @as(isize, @intCast(pos.x)) + xos[i];
                        var py:isize = @as(isize, @intCast(pos.y)) + yos[i];

                        // clip to bounds
                        if (px < 0) {
                            px = 0;
                        }
                        if (px > GRIDSIZE-1) {
                            px = GRIDSIZE-1;
                        }
                        if (py < 0) {
                            py = 0;
                        }
                        if (py > GRIDSIZE-1) {
                            py = GRIDSIZE-1;
                        }

                        const m = .{.pawn = .{.x = @as(usize, @intCast(px)), .y = @as(usize, @intCast(py))}};
                        if (!visited[(m.pawn.y)*GRIDSIZE+m.pawn.x]) {
                            if (try gs.isLegalPawnMove1Fence(pos, m)) {
                                // push
                                toExpand[toExpandTopIndex] = .{.x = m.pawn.x, .y = m.pawn.y};
                                visited[(m.pawn.y)*GRIDSIZE+m.pawn.x] = true;
                                toExpandTopIndex += 1;
                            }
                        }
                    }
                }
                return false;
            },
            else => {
                return error.InvalidMoveErr;
            },
        }
        return true;
    }

    // only check if one step move is illegal due to hitting a fence
    fn isLegalPawnMove1Fence(self:*const Self, pos:Pos, move:Move) !bool {
        switch(move) {
            .skip, .fence => return error.InvalidMoveErr,
            .pawn => |pawnmove| {
                // check if pawn moves through any fences
                for (self.pawns) |p| {
                    for (0..p.numFences) |fi| {
                        const f = p.fences[fi];

                        if (pawnmove.y != pos.y) {   // vert pawn movement
                            if (f.dir == .horz) {   // horizontal fence
                                const yinc = pawnmove.y > pos.y;
                                if (pawnmove.x >= f.x and pawnmove.x < f.x+2) { // in fence columns
                                    if (yinc) {
                                        if (pawnmove.y == f.y+1) {
                                            return false;
                                        }
                                    } else {
                                        if (pawnmove.y == f.y) {
                                            return false;
                                        }
                                    }
                                }
                            }
                        }

                        if (pawnmove.x != pos.x) {   // horz pawn movement
                            if (f.dir == .vert) {   // vert fence
                                const xinc = pawnmove.x > pos.x;
                                if (pawnmove.y >= f.y and pawnmove.y < f.y+2) { // in fence rows
                                    if (xinc) {
                                        if (pawnmove.x == f.x+1) {
                                            return false;
                                        }
                                    } else {
                                        if (pawnmove.x == f.x) {
                                            return false;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return true;
    }

    // is this a legal one step pawn move
    fn isLegalPawnMove1(self:*const Self, pos:Pos, move:Move) !bool {
        switch(move) {
            .skip, .fence => return error.InvalidMoveErr,
            .pawn => {
                if (!try self.isLegalPawnMove1Pawn(pos, move)) {
                    return false;
                }

                if (!try self.isLegalPawnMove1Fence(pos, move)) {
                    return false;
                }
            }
        }
        return true;
    }

    // is this a legal one/multi step pawn move
    fn isLegalMovePawn(self:*const Self, pos:Pos, move:Move) !bool {
        switch(move) {
            .skip, .fence => return error.InvalidMoveErr,
            .pawn => |pawnmove| {
                if (pawnmove.x > GRIDSIZE-1 or pawnmove.y > GRIDSIZE-1) { // basic bounds
                    return false;
                }

                // check single orthogonal movement
                // signed dist
                const xds = @as(isize, @intCast(pawnmove.x)) - @as(isize, @intCast(pos.x));
                const yds = @as(isize, @intCast(pawnmove.y)) - @as(isize, @intCast(pos.y));
                // abs dist
                const xd = @abs(xds);
                const yd = @abs(yds);

                if (xd > 2 or yd > 2) {
                    return false;   // too far
                }

                if ((xd == 1 and yd == 0) or (yd == 1 and xd == 0)) {   // single step orthogonal move
                    if (!try self.isLegalPawnMove1(pos, move)) {
                        return false;
                    }
                } else {    // 2 step move
                    // run move in 2 phases
                    if (xd + yd > 2) {
                        // allow one square diagonal, or 2 square linear jump, nothing else
                        return false;
                    }
                    // Now, in one of following cases {xd=0, yd=1}, {xd=1, yd=0}, {xd=1, yd=1}
                    // look at both ways of getting to move, 2 corners

                    // get the position of the pawn which is not us
                    for (self.pawns) |p| {
                        // this assumes NUM_PAWNS == 2
                        std.debug.assert(NUM_PAWNS == 2);
                        if (!(p.pos.x == pos.x and p.pos.y == pos.y)) {
                        }
                    }

                    // one of those 3 positions must contain a pawn
                    const x1 = if (xds > 0) pos.x + 1 else if (xds == 0) pos.x else pos.x - 1;
                    const y1 = if (yds > 0) pos.y + 1 else if (yds == 0) pos.y else pos.y - 1;
                    const firstMoves:[2]Move = .{
                        Move{.pawn = .{.x = x1, .y = pos.y}},    // horz
                        Move{.pawn = .{.x = pos.x, .y = y1}},    // vert
                    };

                    // find the position which hits a pawn
                    var firstMoveOpt:?Move = null;
                    for (firstMoves) |m| {
                        // first move MUST hit a pawn and not self
                        if (!(m.pawn.x == pos.x and m.pawn.y == pos.y)) {
                            if (!try self.isLegalPawnMove1Pawn(pos, m)) {
                                firstMoveOpt = m;
                                break;
                            }
                        }
                    }
                    if (firstMoveOpt) |firstMove| {
                        // must NOT hit a fence
                        if (!try self.isLegalPawnMove1Fence(pos, firstMove)) {
                            return false;
                        }

                        const secondMove = Move{.pawn = .{.x = pawnmove.x, .y = pawnmove.y}};
                        // must be a regular valid move
                        if (!try self.isLegalPawnMove1(.{.x=firstMove.pawn.x, .y=firstMove.pawn.y}, secondMove)) {
                            return false;
                        }
                    } else {
                        return false;   // no pawn found
                    }
                }
            },
        }
        return true;

    }

    fn isLegalMove(self:*const Self, pi:usize, move:Move) !bool {
        switch(move) {
            .skip => {
            },
            .pawn => {
                return try self.isLegalMovePawn(self.pawns[pi].pos, move);
            },
            .fence => |fencemove| {
                if (fencemove.x > GRIDSIZE-2 or fencemove.y > GRIDSIZE-2) {   // basic bounds
                    return false;
                }

                // has a fence available
                if (self.pawns[pi].numFences >= NUM_FENCES_PER_PLAYER) {
                    return false;
                }

                // check if overlaps a fence (either player)
                for (self.pawns) |p| {
                    for (0..p.numFences) |fi| {
                        const f = p.fences[fi];
                        // check fencemove vs f for overlap
                        switch(fencemove.dir) {
                            .vert => {
                                switch(f.dir) {
                                    .vert => {
                                        if (fencemove.x == f.x) {   // vertically aligned
                                            const dist = @abs(@as(isize, @intCast(fencemove.y)) - @as(isize, @intCast(f.y)));
                                            if (dist < 2) {
                                                return false;   // overlapping vertically
                                            }
                                        }
                                    },
                                    .horz => {
                                        if (fencemove.x == f.x and fencemove.y == f.y) {
                                            return false;   // crossing
                                        }
                                    },
                                }
                            },
                            .horz => {
                                switch(f.dir) {
                                    .vert => {
                                        if (fencemove.x == f.x and fencemove.y == f.y) {
                                            return false;   // crossing
                                        }
                                    },
                                    .horz => {
                                        if (fencemove.y == f.y) {   // horizontally aligned
                                            const dist = @abs(@as(isize, @intCast(fencemove.x)) - @as(isize, @intCast(f.x)));
                                            if (dist < 2) {
                                                return false;   // overlapping horizontally
                                            }
                                        }
                                    },
                                }
                            },

                        }
                    }
                }

                // check if this move prevents either pawn from reaching goal
                for (self.pawns) |p| {
                    if (!try self.isLegalFenceGoalBlocked(p.pos.x, p.pos.y, p.goaly, pi, move)) {
                        return false;
                    }
                }
            },
        }
        return true;
    }

    pub fn applyMove(self:*Self, pi:usize, move:VerifiedMove) !void {
        switch(move.move) {
            .skip => {
                // turn was skipped
            },
            .pawn => |pawnmove| {
                self.pawns[pi].pos = pawnmove;
            },
            .fence => |fencemove| {
                if (self.pawns[pi].numFences < NUM_FENCES_PER_PLAYER) {
                    self.pawns[pi].fences[self.pawns[pi].numFences] = fencemove;
                    self.pawns[pi].numFences += 1;
                } else {
                    return error.OutOfFencesErr;
                }
            },
        }
    }
};

fn drawGame(display:*Display, gs:*GameState, gspi:usize) !void {
    try drawStats(display, gs, gspi);
    drawBoard(display);
    var pi:usize = 0;
    for (gs.pawns) |p| {
        drawPawn(display, p.pos.x, p.pos.y, pawnColour[pi]);
        for (0..p.numFences) |fi| {
            const f = p.fences[fi];
            drawFence(display, f.x, f.y, fenceColour, f.dir);
        }
        pi += 1;
    }
}

fn paintString(display: *Display, bg:color.Color, fg:color.Color, bold:bool, xpos: usize, ypos: usize, sl: []u8) !void {
    var strx = xpos;
    for (sl) |elem| {
        try display.setPixel(strx, ypos, .{ .fg = fg, .bg = bg, .c = elem, .bold = bold});
        strx += 1;
    }
}

fn drawStats(display:*Display, gs:*const GameState, pi:usize) !void {
    var buf: [32]u8 = undefined;

    var statsXoff:usize = 0;
    var statsYoff:usize = 0;

    if (mini) {
        statsXoff = 41;
        statsYoff = 3;
    } else {
        statsXoff = 59;
        statsYoff = 2;
    }

    switch(players[0]) {
        .Human => try paintString(display, .black, .white, pi==0, statsXoff, statsYoff, try std.fmt.bufPrint(&buf, "Player 1: Human", .{})),
        .Machine => try paintString(display, .black, .white, pi==0, statsXoff, statsYoff, try std.fmt.bufPrint(&buf, "Player 1: Machine", .{})),
    }
    try paintString(display, .black, .white, pi==0, statsXoff, statsYoff+1, try std.fmt.bufPrint(&buf, "Wins: {d}", .{wins[0]}));
    try paintString(display, .black, .white, pi==0, statsXoff, statsYoff+2, try std.fmt.bufPrint(&buf, "Fences: {d}", .{NUM_FENCES_PER_PLAYER - gs.pawns[0].numFences}));

    switch(players[1]) {
        .Human => try paintString(display, .black, .white, pi==1, statsXoff, statsYoff+4, try std.fmt.bufPrint(&buf, "Player 2: Human", .{})),
        .Machine => try paintString(display, .black, .white, pi==1, statsXoff, statsYoff+4, try std.fmt.bufPrint(&buf, "Player 2: Machine", .{})),
    }
    try paintString(display, .black, .white, pi==1, statsXoff, statsYoff+5, try std.fmt.bufPrint(&buf, "Wins: {d}", .{wins[1]}));
    try paintString(display, .black, .white, pi==1, statsXoff, statsYoff+6, try std.fmt.bufPrint(&buf, "Fences: {d}", .{NUM_FENCES_PER_PLAYER - gs.pawns[1].numFences}));

    if (gs.hasWon(0)) {
        try paintString(display, .black, .white, true, statsXoff, statsYoff+15, try std.fmt.bufPrint(&buf, "Player1 won", .{}));
        try paintString(display, .black, .white, true, statsXoff, statsYoff+16, try std.fmt.bufPrint(&buf, "Player2 lost", .{}));
    }
    if (gs.hasWon(1)) {
        try paintString(display, .black, .white, true, statsXoff, statsYoff+15, try std.fmt.bufPrint(&buf, "Player1 lost", .{}));
        try paintString(display, .black, .white, true, statsXoff, statsYoff+16, try std.fmt.bufPrint(&buf, "Player2 won", .{}));
    }

    if (players[0] == .Human or players[1] == .Human) {
        try paintString(display, .black, .white, true, statsXoff, statsYoff+8, try std.fmt.bufPrint(&buf, "q - quit", .{}));
        try paintString(display, .black, .white, true, statsXoff, statsYoff+9, try std.fmt.bufPrint(&buf, "cursors - set pos", .{}));
        try paintString(display, .black, .white, true, statsXoff, statsYoff+10, try std.fmt.bufPrint(&buf, "enter - confirm", .{}));
        try paintString(display, .black, .white, true, statsXoff, statsYoff+11, try std.fmt.bufPrint(&buf, "tab - fence/pawn", .{}));
        try paintString(display, .black, .white, true, statsXoff, statsYoff+12, try std.fmt.bufPrint(&buf, "space - rotate fence", .{}));
    }

    if (lastTurnStr) |s| {
        try paintString(display, .black, .white, true, statsXoff, statsYoff+14, try std.fmt.bufPrint(&buf, "{s}", .{s}));
    }
}

fn drawBoard(display:*Display) void {
    if (mini) {
        // draw squares
        for (0..GRIDSIZE) |x| {
            for (0..GRIDSIZE) |y| {
                if (x == 0) {
                    // row labels
                    try display.setPixel(xoff + 4*x, yoff + 2*y, .{ .fg = .white, .bg = .blue, .c = ROW_LABEL_START + @as(u8, @intCast(y)), .bold = true });
                }

                // pawn squares
                try display.setPixel(xoff + 4*x + label_extra_w, yoff + 2*y, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                try display.setPixel(xoff + 4*x+1 + label_extra_w, yoff + 2*y, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });

                if (true) {
                    if (x != GRIDSIZE-1) {
                        try display.setPixel(xoff + 4*x+2 + label_extra_w, yoff + 2*y, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                        try display.setPixel(xoff + 4*x+3 + label_extra_w, yoff + 2*y, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                    }

                    if (y != GRIDSIZE-1) {
                        try display.setPixel(xoff + 4*x + label_extra_w, yoff + 2*y + 1, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                        try display.setPixel(xoff + 4*x+1 + label_extra_w, yoff + 2*y + 1, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                    }

                }
            }
        }

        // draw fence join spots 
        for (0..GRIDSIZE-1) |xg| {
            for (0..GRIDSIZE-1) |yg| {
                try display.setPixel(xoff + 4*xg+2 + label_extra_w, yoff + 2*yg + 1, .{ .fg = .white, .bg = .white, .c = ' ', .bold = false });
                try display.setPixel(xoff + 4*xg+3 + label_extra_w, yoff + 2*yg + 1, .{ .fg = .white, .bg = .white, .c = ' ', .bold = false });
            }
        }

        // column labels
        for (0..GRIDSIZE) |x| {
            try display.setPixel(xoff + 4*x + label_extra_w, yoff + 2*GRIDSIZE, .{ .fg = .white, .bg = .blue, .c = COLUMN_LABEL_START + @as(u8, @intCast(x)), .bold = true });
        }
    } else {
        // draw border
        for (0..GRIDSIZE*6+2) |x| {
            try display.setPixel(xoff + x - 2, yoff-1, .{ .fg = .white, .bg = .white, .c = ' ', .bold = false }); // top
            try display.setPixel(xoff + x - 2, (yoff + 3*GRIDSIZE) - 1, .{ .fg = .white, .bg = .white, .c = ' ', .bold = false }); // bottom
        }
        for (0..GRIDSIZE*3) |y| {
            try display.setPixel(xoff - 2, yoff + y, .{ .fg = .white, .bg = .white, .c = ' ', .bold = false }); // left
            try display.setPixel(xoff - 1, yoff + y, .{ .fg = .white, .bg = .white, .c = ' ', .bold = false }); // left

            try display.setPixel(xoff + 6*GRIDSIZE - 2, yoff + y, .{ .fg = .white, .bg = .white, .c = ' ', .bold = false }); // right
            try display.setPixel(xoff + 6*GRIDSIZE - 1, yoff + y, .{ .fg = .white, .bg = .white, .c = ' ', .bold = false }); // right
        }

        // column labels
        for (0..GRIDSIZE) |x| {
            try display.setPixel(xoff + 6*x+1, yoff + 3*GRIDSIZE - 1, .{ .fg = .black, .bg = .white, .c = COLUMN_LABEL_START + @as(u8, @intCast(x)), .bold = true });
        }

        // draw squares
        for (0..GRIDSIZE) |x| {
            for (0..GRIDSIZE) |y| {
                if (x == 0) {
                    // row labels
                    try display.setPixel(xoff + 6*x - 2, yoff + 3*y, .{ .fg = .black, .bg = .white, .c = ROW_LABEL_START + @as(u8, @intCast(y)), .bold = true });
                }

                // pawn squares
                try display.setPixel(xoff + 6*x + 0, yoff + 3*y, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                try display.setPixel(xoff + 6*x + 1, yoff + 3*y, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                try display.setPixel(xoff + 6*x + 2, yoff + 3*y, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                try display.setPixel(xoff + 6*x + 3, yoff + 3*y, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });

                try display.setPixel(xoff + 6*x + 0, yoff + 3*y+1, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                try display.setPixel(xoff + 6*x + 1, yoff + 3*y+1, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                try display.setPixel(xoff + 6*x + 2, yoff + 3*y+1, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
                try display.setPixel(xoff + 6*x + 3, yoff + 3*y+1, .{ .fg = .white, .bg = .black, .c = ' ', .bold = false });
            }
        }

    }
}

fn drawPawn(display:*Display, x:usize, y:usize, c:color.Color) void {
    if (mini) {
        try display.setPixel(xoff + 4*x + label_extra_w, yoff + 2*y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(xoff + 4*x+1 + label_extra_w, yoff + 2*y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
    } else {
        try display.setPixel(xoff + 6*x + 0, yoff + 3*y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(xoff + 6*x + 1, yoff + 3*y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(xoff + 6*x + 2, yoff + 3*y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(xoff + 6*x + 3, yoff + 3*y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });

        try display.setPixel(xoff + 6*x + 0, yoff + 3*y+1, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(xoff + 6*x + 1, yoff + 3*y+1, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(xoff + 6*x + 2, yoff + 3*y+1, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(xoff + 6*x + 3, yoff + 3*y+1, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
    }
}

fn drawPawnHighlight(display:*Display, x:usize, y:usize, c:color.Color) void {
    if (mini) {
        try display.setPixel(xoff + 4*x + label_extra_w - 1, yoff + 2*y, .{ .fg = .white, .bg = c, .c = '[', .bold = false });
        try display.setPixel(xoff + 4*x + label_extra_w + 2, yoff + 2*y, .{ .fg = .white, .bg = c, .c = ']', .bold = false });
    } else {
        try display.setPixel(xoff + 6*x - 1, yoff + 3*y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(xoff + 6*x + 4, yoff + 3*y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(xoff + 6*x - 1, yoff + 3*y + 1, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
        try display.setPixel(xoff + 6*x + 4, yoff + 3*y + 1, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
    }
}

fn drawFence(display:*Display, x:usize, y:usize, c:color.Color, dir:Dir) void {
    // x,y is most NW square adjacent to fence
    if (mini) {
        if (dir == .horz) {
            for (0..6) |xi| {
                try display.setPixel(xi + xoff + 4*x + label_extra_w, yoff + 2*y+1, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
            }
        } else {
            for (0..3) |yi| {
                try display.setPixel(xoff + 4*x+2 + label_extra_w, yi + yoff + 2*y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
                try display.setPixel(xoff + 4*x+2+1 + label_extra_w, yi + yoff + 2*y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
            }
        }
    } else {
        if (dir == .horz) {
            for (0..10) |xi| {
                try display.setPixel(xoff + 6*x + xi, yoff + 3*y + 2, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
            }
        } else {
            for (0..5) |yi| {
                try display.setPixel(xoff + 6*x + 4, yoff + 3*y + yi, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
                try display.setPixel(xoff + 6*x + 5, yoff + 3*y + yi, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
            }
        }
    }
}

fn drawFenceHighlight(display:*Display, x:usize, y:usize, c:color.Color, dir:Dir) void {
    if (mini) {
        // x,y is most NW square adjacent to fence
        if (dir == .horz) {
            for (0..6) |xi| {
                try display.setPixel(xi + xoff + 4*x + label_extra_w, yoff + 2*y+1, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
            }
        } else {
            for (0..3) |yi| {
                try display.setPixel(xoff + 4*x+2 + label_extra_w, yi + yoff + 2*y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
                try display.setPixel(xoff + 4*x+2+1 + label_extra_w, yi + yoff + 2*y, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
            }
        }
    } else {
        if (dir == .horz) {
            for (0..10) |xi| {
                try display.setPixel(xoff + 6*x + xi, yoff + 3*y + 2, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
            }
        } else {
            for (0..5) |yi| {
                try display.setPixel(xoff + 6*x + 4, yoff + 3*y + yi, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
                try display.setPixel(xoff + 6*x + 5, yoff + 3*y + yi, .{ .fg = .white, .bg = c, .c = ' ', .bold = false });
            }
        }
    }
}

fn parseCommandLine() !void {
    const allocator = std.heap.page_allocator;
    const App = yazap.App;
    const Arg = yazap.Arg;

    var app = App.init(allocator, "zoridor", null);
    defer app.deinit();

    var zoridor = app.rootCommand();

    var player1_opt = Arg.singleValueOptionWithValidValues(
        "player1",
        '1',
        "Player 1 type",
        &[_][]const u8{ "human", "machine" }
    );
    player1_opt.setValuePlaceholder("human|machine");
    try zoridor.addArg(player1_opt);

    var player2_opt = Arg.singleValueOptionWithValidValues(
        "player2",
        '2',
        "Player 2 type",
        &[_][]const u8{ "human", "machine" }
    );
    player2_opt.setValuePlaceholder("human|machine");
    try zoridor.addArg(player2_opt);

    var randseed_opt = Arg.singleValueOption("randseed", 'r', "Set random seed");
    randseed_opt.setValuePlaceholder("12345");
    try zoridor.addArg(randseed_opt);

    const forever_opt = Arg.booleanOption("forever", 'f', "Play forever");
    try zoridor.addArg(forever_opt);

    const mini_opt = Arg.booleanOption("mini", 'm', "Mini display < 80x24");
    try zoridor.addArg(mini_opt);

    const matches = try app.parseProcess();

    if (matches.containsArg("forever")) {
        playForever = true;
    }

    if (matches.containsArg("mini")) {
        mini = true;
    }

    if (matches.containsArg("randseed")) {
        const seedStr = matches.getSingleValue("randseed").?;
        const i = std.fmt.parseInt(u32, seedStr, 10) catch return;
        RANDOMSEED = i;
    }

    if (matches.containsArg("player1")) {
        const typ = matches.getSingleValue("player1").?;

        if (std.mem.eql(u8, typ, "human")) {
            players[0] = .Human;
        } else {
            players[0] = .Machine;
        }
    }

    if (matches.containsArg("player2")) {
        const typ = matches.getSingleValue("player2").?;

        if (std.mem.eql(u8, typ, "human")) {
            players[1] = .Human;
        } else {
            players[1] = .Machine;
        }
    }
}

fn emitMoves(turnN:usize, moves:[2]Move) !void {
    var b1:[16]u8 = undefined;
    var b2:[16]u8 = undefined;
    const s1 = try moves[0].toString(&b1);
    const s2 = try moves[1].toString(&b2);

    lastTurnStr = try std.fmt.bufPrint(&lastTurnBuf, "Turn: {d}. {s} {s}", .{turnN+1, s1, s2});
}

pub fn main() !void {
    var exitReq = false;

    try parseCommandLine();

    while(!exitReq) {
        var turnN:usize = 0;
        var gameOver = false;
        time.initTime();

        var lastMoves:[NUM_PAWNS]Move = undefined;

        var display = try Display.init();
        display.cls();
        defer display.destroy();

        var humanUi = HumanUi.init();
        var machineUi = MachineUi.init();

        try display.paint();

        var gs = GameState.init();

        var pi:usize = 0;   // whose turn is it

        switch(players[pi]) {
            .Human => {
                try humanUi.selectMoveInteractive(&gs, pi);
            },
            .Machine => {
                try machineUi.selectMoveInteractive(&gs, pi);
            },
        }

        while (!gameOver) {
            var timeout:i32 = 100;
            if (players[0] == .Machine and players[1] == .Machine) {
                timeout = 0;
            }
            const next = try display.getEvent(timeout);

            try humanUi.handleEvent(next, &gs, pi);
            try machineUi.handleEvent(next, &gs, pi);

            switch(players[pi]) {
                .Human => {
                    if (humanUi.getCompletedMove()) |move| {
                        // apply the move
                        try gs.applyMove(pi, move);
                        lastMoves[pi] = move.move;
                        if (pi == NUM_PAWNS - 1) {  // final player to take turn
                            try emitMoves(turnN, lastMoves);
                            turnN += 1;
                        }

                        if (gs.hasWon(pi)) {
                            wins[pi] += 1;
                            gameOver = true;
                        }

                        // select next player to make a move
                        pi = (pi + 1) % NUM_PAWNS;

                        switch(players[pi]) {
                            .Human => {
                                try humanUi.selectMoveInteractive(&gs, pi);
                            },
                            .Machine => {
                                try machineUi.selectMoveInteractive(&gs, pi);
                            },
                        }
                    }
                },
                .Machine => {
                    if (machineUi.getCompletedMove()) |move| {
                        // apply the move
                        try gs.applyMove(pi, move);
                        lastMoves[pi] = move.move;
                        if (pi == NUM_PAWNS - 1) {  // final player to take turn
                            try emitMoves(turnN, lastMoves);
                            turnN += 1;
                        }


                        if (gs.hasWon(pi)) {
                            wins[pi] += 1;
                            gameOver = true;
                        }

                        // select next player to make a move
                        pi = (pi + 1) % NUM_PAWNS;

                        switch(players[pi]) {
                            .Human => {
                                try humanUi.selectMoveInteractive(&gs, pi);
                            },
                            .Machine => {
                                try machineUi.selectMoveInteractive(&gs, pi);
                            },
                        }
                    }
                },
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
            try humanUi.paint(&display);

            try display.paint();
        }
        if (!playForever) {
            exitReq = true;
        }
    }
}
