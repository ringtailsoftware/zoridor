const std = @import("std");
const expect = std.testing.expect;

const BitGraph = @import("graph.zig").BitGraph;
const GameState = @import("gamestate.zig").GameState;
const PosDir = @import("gamestate.zig").PosDir;
const Move = @import("gamestate.zig").Move;
const PosPath = @import("gamestate.zig").PosPath;
const Pos = @import("gamestate.zig").Pos;
const Pawn = @import("gamestate.zig").Pawn;
const Dir = @import("gamestate.zig").Dir;
const UiAgentMachine = @import("uiagentmachine.zig").UiAgentMachine;
const config = @import("config.zig");
const UiAgent = @import("ui.zig").UiAgent;
const clock = @import("clock.zig");
const GameRecord = @import("record.zig").GameRecord;

test "bitgraph-edge" {
    var g = BitGraph.init();
    try expect(!g.hasAnyEdges(11));
    try expect(!g.hasAnyEdges(12));
    g.addEdgeBi(11, 12);
    try expect(g.hasAnyEdges(11));
    try expect(g.hasAnyEdges(12));
    try expect(g.hasEdgeUni(11, 12));
    try expect(g.hasEdgeUni(12, 11));
    g.delEdgeBi(11, 12);
    try expect(!g.hasAnyEdges(11));
    try expect(!g.hasAnyEdges(12));
    try expect(!g.hasEdgeUni(11, 12));
    try expect(!g.hasEdgeUni(12, 11));
}

test "bitgraph-delnode" {
    var g = BitGraph.init();
    g.addGridEdges();

    try expect(g.hasEdgeUni(12, 11));
    try expect(g.hasEdgeUni(12, 13));
    try expect(g.hasEdgeUni(12, 3));
    try expect(g.hasEdgeUni(12, 21));

    g.delNode(12);

    try expect(g.hasEdgeUni(11, 13));
    try expect(g.hasEdgeUni(11, 21));
    try expect(g.hasEdgeUni(11, 3));
    try expect(g.hasEdgeUni(3, 21));
    try expect(g.hasEdgeUni(3, 13));
    try expect(g.hasEdgeUni(3, 11));
    try expect(g.hasEdgeUni(13, 3));
    try expect(g.hasEdgeUni(13, 11));
    try expect(g.hasEdgeUni(13, 21));
    try expect(g.hasEdgeUni(21, 11));
    try expect(g.hasEdgeUni(21, 3));
    try expect(g.hasEdgeUni(21, 13));

    try expect(true);
}

test "bitgraph-path-unreachable" {
    var g = BitGraph.init();

    var pathbuf: [BitGraph.MAXPATH]BitGraph.NodeId = undefined;
    const range: BitGraph.NodeIdRange = .{
        .min = BitGraph.coordPosToNodeId(.{ .x = 0, .y = 8 }),
        .max = BitGraph.coordPosToNodeId(.{ .x = 8, .y = 8 }),
    };
    try expect(g.findShortestPath(0, range, &pathbuf, true) == null);
    try expect(g.findShortestPath(0, range, &pathbuf, false) == null);
}

test "bitgraph-path-reachable2" {
    var g = BitGraph.init();

    g.addGridEdges();
    // divide vertically
    g.delCoordEdgeBi(.{ .x = 2, .y = 0 }, .{ .x = 3, .y = 0 });
    g.delCoordEdgeBi(.{ .x = 2, .y = 1 }, .{ .x = 3, .y = 1 });
    g.delCoordEdgeBi(.{ .x = 2, .y = 2 }, .{ .x = 3, .y = 2 });
    g.delCoordEdgeBi(.{ .x = 2, .y = 3 }, .{ .x = 3, .y = 3 });
    g.delCoordEdgeBi(.{ .x = 2, .y = 4 }, .{ .x = 3, .y = 4 });
    g.delCoordEdgeBi(.{ .x = 2, .y = 5 }, .{ .x = 3, .y = 5 });
    g.delCoordEdgeBi(.{ .x = 2, .y = 6 }, .{ .x = 3, .y = 6 });
    g.delCoordEdgeBi(.{ .x = 2, .y = 7 }, .{ .x = 3, .y = 7 });
    g.delCoordEdgeBi(.{ .x = 2, .y = 8 }, .{ .x = 3, .y = 8 });

    // on connection
    g.addCoordEdgeBi(.{ .x = 2, .y = 5 }, .{ .x = 3, .y = 5 });

    var pathbuf: [BitGraph.MAXPATH]BitGraph.NodeId = undefined;

    const range: BitGraph.NodeIdRange = .{
        .min = BitGraph.coordPosToNodeId(.{ .x = 8, .y = 8 }),
        .max = BitGraph.coordPosToNodeId(.{ .x = 8, .y = 8 }),
    };

    try expect(g.findShortestPath(0, range, &pathbuf, true) != null);

    const p = g.findShortestPath(0, range, &pathbuf, true);
    const anyplen = p.?.len;

    if (g.findShortestPath(0, range, &pathbuf, false)) |path| {
        //const expectedPath = [_]BitGraph.NodeId{ 0, 9, 18, 27, 36, 45, 46, 47, 48, 57, 66, 75, 76, 77, 78, 79, 80 };
        //try expect(std.mem.eql(BitGraph.NodeId, path, &expectedPath));
        try expect(path.len <= anyplen); // check that optimal path at least as good as anypath
    } else {
        try expect(false);
    }

    // remove connection
    g.delCoordEdgeBi(.{ .x = 2, .y = 5 }, .{ .x = 3, .y = 5 });

    try expect(g.findShortestPath(0, range, &pathbuf, true) == null);
    try expect(g.findShortestPath(0, range, &pathbuf, false) == null);
}

test "bitgraph-path-reachable" {
    var g = BitGraph.init();
    g.addGridEdges();

    var pathbuf: [BitGraph.MAXPATH]BitGraph.NodeId = undefined;
    const range: BitGraph.NodeIdRange = .{
        .min = BitGraph.coordPosToNodeId(.{ .x = 0, .y = 8 }),
        .max = BitGraph.coordPosToNodeId(.{ .x = 8, .y = 8 }),
    };

    try expect(g.findShortestPath(0, range, &pathbuf, true) != null);

    if (g.findShortestPath(0, range, &pathbuf, false)) |path| {
        const expectedPath = [_]BitGraph.NodeId{ 0, 9, 18, 27, 36, 45, 54, 63, 72 };
        try expect(std.mem.eql(BitGraph.NodeId, path, &expectedPath));
    } else {
        try expect(false);
    }

    g.delCoordEdgeBi(.{ .x = 0, .y = 0 }, .{ .x = 0, .y = 1 });

    try expect(g.findShortestPath(0, range, &pathbuf, true) != null);

    if (g.findShortestPath(0, range, &pathbuf, false)) |path| {
        const expectedPath = [_]BitGraph.NodeId{ 0, 1, 10, 19, 28, 37, 46, 55, 64, 73 };
        try expect(std.mem.eql(BitGraph.NodeId, path, &expectedPath));
    } else {
        try expect(false);
    }
}

test "gamestate-fenceplace" {
    const f1 = PosDir{
        .pos = .{ .x = 0, .y = 0 },
        .dir = .horz,
    };

    const f2 = PosDir{
        .pos = .{ .x = 0, .y = 0 },
        .dir = .vert,
    };

    const f3 = PosDir{
        .pos = .{ .x = 0, .y = 1 },
        .dir = .horz,
    };

    const f4 = PosDir{
        .pos = .{ .x = 1, .y = 0 },
        .dir = .vert,
    };

    const f5 = PosDir{
        .pos = .{ .x = 2, .y = 0 },
        .dir = .horz,
    };

    const f6 = PosDir{
        .pos = .{ .x = 0, .y = 2 },
        .dir = .vert,
    };

    const f7 = PosDir{
        .pos = .{ .x = 0, .y = 1 },
        .dir = .vert,
    };

    const f8 = PosDir{
        .pos = .{ .x = 1, .y = 1 },
        .dir = .vert,
    };

    const f9 = PosDir{
        .pos = .{ .x = 1, .y = 0 },
        .dir = .horz,
    };

    var gs = GameState.init();
    // can place either
    try expect(gs.canPlaceFence(f1));
    try expect(gs.canPlaceFence(f2));

    // can't place crossing overlap v over h
    gs.placeFence(0, f1);
    try expect(!gs.canPlaceFence(f2));

    // can't place crossing overlap h over v
    gs = GameState.init();
    gs.placeFence(0, f2);
    try expect(!gs.canPlaceFence(f1));

    // can place parallel h
    gs = GameState.init();
    gs.placeFence(0, f1);
    try expect(gs.canPlaceFence(f3));
    gs.placeFence(0, f3);

    // can place parallel v
    gs = GameState.init();
    gs.placeFence(0, f2);
    try expect(gs.canPlaceFence(f4));
    gs.placeFence(0, f4);

    // can place end to end h
    gs = GameState.init();
    gs.placeFence(0, f1);
    try expect(gs.canPlaceFence(f5));
    gs.placeFence(0, f5);

    // can place end to end v
    gs = GameState.init();
    gs.placeFence(0, f2);
    try expect(gs.canPlaceFence(f6));
    gs.placeFence(0, f6);

    // cannot place overlap h
    gs = GameState.init();
    gs.placeFence(0, f1);
    try expect(!gs.canPlaceFence(f9));

    // cannot place overlap v
    gs = GameState.init();
    gs.placeFence(0, f2);
    try expect(!gs.canPlaceFence(f7));

    // can place t shape
    gs = GameState.init();
    gs.placeFence(0, f1);
    try expect(gs.canPlaceFence(f8));
    gs.placeFence(0, f8);
}

test "gamestate-fenceplace-T" {
    var gs = GameState.init();

    const f1 = PosDir{
        .pos = .{ .x = 0, .y = 1 },
        .dir = .vert,
    };

    const f2 = PosDir{
        .pos = .{ .x = 0, .y = 0 },
        .dir = .horz,
    };

    try expect(gs.canPlaceFence(f1));
    gs.placeFence(0, f1);
    try expect(gs.canPlaceFence(f2));
    gs.placeFence(0, f2);
}

test "gamestate-fenceplace-blockpawn" {
    var gs = GameState.init();
    var x: usize = 0;
    while (x < 8) : (x += 2) {
        gs.placeFence(0, .{
            .pos = .{ .x = @intCast(x), .y = @intCast(3) },
            .dir = .horz,
        });
    }

    const f1 = PosDir{
        .pos = .{ .x = 7, .y = 2 },
        .dir = .vert,
    };

    const f2 = PosDir{
        .pos = .{ .x = 7, .y = 1 },
        .dir = .horz,
    };

    try expect(gs.canPlaceFence(f1));
    gs.placeFence(0, f1);
    try expect(!gs.canPlaceFence(f2));
}

test "gamestate-pawnmove" {
    var gs = GameState.init();

    // can move down, up, right, left
    var pos = gs.getPawnPos(0);
    pos.y += 1;
    try expect(gs.canMovePawn(0, pos));
    gs.movePawn(0, pos);
    pos.y -= 1;
    try expect(gs.canMovePawn(0, pos));
    gs.movePawn(0, pos);
    pos.x += 1;
    try expect(gs.canMovePawn(0, pos));
    gs.movePawn(0, pos);
    pos.x -= 1;
    try expect(gs.canMovePawn(0, pos));
    gs.movePawn(0, pos);

    // X|
    //  |
    const f1 = PosDir{
        .pos = .{ .x = 4, .y = 0 },
        .dir = .vert,
    };
    gs = GameState.init();
    pos = gs.getPawnPos(0);
    gs.placeFence(0, f1);
    pos.x += 1;
    try expect(!gs.canMovePawn(0, pos));

    // |X
    // |
    const f2 = PosDir{
        .pos = .{ .x = 3, .y = 0 },
        .dir = .vert,
    };
    gs = GameState.init();
    pos = gs.getPawnPos(0);
    gs.placeFence(0, f2);
    pos.x -= 1;
    try expect(!gs.canMovePawn(0, pos));

    //  X
    // --
    const f3 = PosDir{
        .pos = .{ .x = 3, .y = 0 },
        .dir = .horz,
    };
    gs = GameState.init();
    pos = gs.getPawnPos(0);
    gs.placeFence(0, f3);
    pos.y += 1;
    try expect(!gs.canMovePawn(0, pos));

    // --
    //  X
    const f4 = PosDir{
        .pos = .{ .x = 3, .y = 7 },
        .dir = .horz,
    };
    gs = GameState.init();
    pos = gs.getPawnPos(1);
    gs.placeFence(0, f4);
    pos.y -= 1;
    try expect(!gs.canMovePawn(0, pos));
}

test "gamestate-jumponwin" {
    // pawn should be able to end game by jumping onto opponent if they're blocking the goal line
    var gs = GameState.init();

    const f1 = PosDir{
        .pos = .{ .x = 0, .y = 7 },
        .dir = .vert,
    };
    gs = GameState.init();
    gs.placeFence(0, f1);

    gs.pawns[0].pos.x = 0;
    gs.pawns[0].pos.y = 7;

    gs.pawns[1].pos.x = 0;
    gs.pawns[1].pos.y = 8;

    try expect(gs.canMovePawn(0, .{.x=0, .y=8}));
}

test "coordpos" {
    // convert node id into coords and back
    var i: BitGraph.NodeId = 0;
    for (0..9) |y| {
        for (0..9) |x| {
            const cp = BitGraph.nodeIdToCoordPos(i);
            const ni = BitGraph.coordPosToNodeId(.{ .x = @intCast(x), .y = @intCast(y) });
            try expect(ni == i);
            try expect(cp.x == x and cp.y == y);
            i += 1;
        }
    }
}

test "gamestate-pawnpath" {
    var gs = GameState.init();
    var x: usize = 0;
    // place obstacles
    while (x < 8) : (x += 2) {
        gs.placeFence(0, .{
            .pos = .{ .x = @intCast(x), .y = @intCast(3) },
            .dir = .horz,
        });
    }

    const pos = gs.getPawnPos(0);
    var pathbuf: [BitGraph.MAXPATH]BitGraph.NodeId = undefined;

    const goal = gs.getPawnGoal(0);

    // plan path
    if (gs.graph.findShortestPath(BitGraph.coordPosToNodeId(.{ .x = @intCast(pos.x), .y = @intCast(pos.y) }), goal, &pathbuf, false)) |path| {
        // follow path, skip starting pos at start of list
        for (path[1..path.len]) |n| {
            const nextpos = BitGraph.nodeIdToCoordPos(n);
            try expect(gs.canMovePawn(0, nextpos));
            gs.movePawn(0, nextpos);
        }
    } else {
        try expect(false);
    }
}

test "gamestate-pawnonpawn" {
    var gs = GameState.init();

    // Place pawn 1 to right of pawn 0

    gs.pawns[0].pos.x = 4;
    gs.pawns[0].pos.y = 4;

    gs.pawns[1].pos.x = 5;
    gs.pawns[1].pos.y = 4;

    var pos = gs.getPawnPos(0);
    pos.x += 1;
    try expect(!gs.canMovePawn(0, pos)); // cannot land on pawn

    pos = gs.getPawnPos(0);
    pos.x += 2;
    try expect(gs.canMovePawn(0, pos)); // can jump over pawn
}

test "gamestate-pawnonpawnwall" {
    var gs = GameState.init();

    gs.pawns[0].pos.x = 4;
    gs.pawns[0].pos.y = 5;

    gs.pawns[1].pos.x = 4;
    gs.pawns[1].pos.y = 6;

    // --
    // 0
    // 1
    const f1 = PosDir{
        .pos = .{ .x = 4, .y = 4 },
        .dir = .horz,
    };
    gs.placeFence(0, f1);
    var pos = gs.getPawnPos(1);
    pos.y -= 1;
    pos.x += 1;
    try expect(gs.canMovePawn(1, pos));

    pos = gs.getPawnPos(1);
    pos.y -= 1;
    pos.x -= 1;
    try expect(gs.canMovePawn(1, pos));

    pos = gs.getPawnPos(1);
    pos.y -= 2;
    try expect(!gs.canMovePawn(1, pos));

    pos = gs.getPawnPos(1);
    pos.y -= 2;
    pos.x += 1;
    try expect(!gs.canMovePawn(1, pos));

    pos = gs.getPawnPos(1);
    pos.y -= 2;
    pos.x -= 1;
    try expect(!gs.canMovePawn(1, pos));
}

test "gamestate-findpath" {
    var gs = GameState.init();
    var x: usize = 0;
    // place obstacles
    while (x < 8) : (x += 2) {
        gs.placeFence(0, .{
            .pos = .{ .x = @intCast(x), .y = @intCast(3) },
            .dir = .horz,
        });
    }

    var pathbuf: PosPath = undefined;
    const pathO = gs.findShortestPath(0, gs.getPawnPos(0), &pathbuf);

    if (pathO) |path| {
        const expectedPath = [_]Pos { .{ .x = 5, .y = 0 }, .{ .x = 6, .y = 0 }, .{ .x = 6, .y = 1 }, .{ .x = 7, .y = 1 }, .{ .x = 7, .y = 2 }, .{ .x = 7, .y = 3 }, .{ .x = 8, .y = 3 }, .{ .x = 8, .y = 4 }, .{ .x = 8, .y = 5 }, .{ .x = 8, .y = 6 }, .{ .x = 8, .y = 7 }, .{ .x = 8, .y = 8 } };

        try expect(path.len == expectedPath.len);
        for (path, 0..) |p, i| {
            try expect(p.x == expectedPath[i].x and p.y == expectedPath[i].y);
        }
    } else {
        try expect(false);
    }
}

test "gamestate-findpath-pawnjump" {
    var gs = GameState.init();
    // place obstacles
    // |
    // |0
    // |1
    // |
    var y: usize = 0;
    while (y < 8) : (y += 2) {
        gs.placeFence(0, .{
            .pos = .{ .x = @intCast(3), .y = @intCast(y) },
            .dir = .vert,
        });
    }

    gs.pawns[1].pos.y -= 1; // move off of the goal line for simplicity

    var pathbuf: PosPath = undefined;
    const pathO = gs.findShortestPath(0, gs.getPawnPos(0), &pathbuf);
    if (pathO) |path| {
        // checking it jumps over the final pawn
        const expectedPath = [_]Pos{ .{ .x = 4, .y = 1 }, .{ .x = 4, .y = 2 }, .{ .x = 4, .y = 3 }, .{ .x = 4, .y = 4 }, .{ .x = 4, .y = 5 }, .{ .x = 4, .y = 6 }, .{ .x = 4, .y = 8 } };
        try expect(path.len == expectedPath.len);
        for (path, 0..) |p, i| {
            try expect(p.x == expectedPath[i].x and p.y == expectedPath[i].y);
        }
    } else {
        try expect(false);
    }
}

test "finderr1" {
    var gs = GameState.init();

    const pi = 0;
    gs.graph = .{ .bitMatrix = .{ 514, 1029, 10, 20, 40, 80, 160, 320, 131200, 1025, 2562, 5120, 10240, 20480, 8192, 16842752, 33718272, 67174656, 134742016, 269746176, 539492352, 1078984704, 2157969408, 4299161600, 8623521792, 17263820800, 34393423872, 68988174336, 138110566400, 276221132800, 552442265600, 1104884531200, 2209769062400, 4419538124800, 8839076249600, 17609433022464, 35321945260032, 343865819136, 687731638272, 1375463276544, 2750926553088, 1131401759948800, 2262803519897600, 4525607039795200, 9016029707501568, 70437463654400, 175921860444160, 72409437758816256, 144818875517632512, 288511851128422400, 2253998836940800, 5633897580724224, 11267795161448448, 4521191813414912, 9259400833873739776, 90071992547409920, 180284722583175168, 360569445166350336, 144678138029277184, 295147905179352825856, 592601653367919345664, 1186356228240445538304, 2363489084444036300800, 4740831241341864247296, 9490849825923564306432, 92233720368547758080, 184467440737095516160, 368934881474191032320, 148150413341979836416, 303413199445879311826944, 607416694702117329305600, 1210111022921365013397504, 9453956337776145203200, 23630279158421935620096, 47223664828696452136960, 94447329657392904273920, 188894659314785808547840, 377789318629571617095680, 756168933069501939843072, 1512337866139003879686144, 606824093048749409959936 } };
    gs.pawns = .{ Pawn{ .pos = .{ .x = 2, .y = 0 }, .goaly = 8, .numFencesRemaining = 1 }, Pawn{ .pos = .{ .x = 1, .y = 7 }, .goaly = 0, .numFencesRemaining = 1 } };
    gs.fences = .{ PosDir{ .pos = .{ .x = 3, .y = 4 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 5, .y = 5 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 3, .y = 6 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 2, .y = 7 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 1, .y = 4 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 7, .y = 5 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 4, .y = 7 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 5, .y = 6 }, .dir = Dir.vert }, PosDir{ .pos = .{ .x = 0, .y = 1 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 2, .y = 1 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 4, .y = 1 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 4, .y = 5 }, .dir = Dir.vert }, PosDir{ .pos = .{ .x = 5, .y = 1 }, .dir = Dir.vert }, PosDir{ .pos = .{ .x = 4, .y = 0 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 2, .y = 0 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 6, .y = 0 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 0, .y = 5 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 1, .y = 6 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 0, .y = 0 }, .dir = Dir.vert }, PosDir{ .pos = .{ .x = 0, .y = 0 }, .dir = Dir.vert } };

    var pathbuf: PosPath = undefined;
    if (gs.findShortestPath(pi, gs.getPawnPos(pi), &pathbuf)) |_| {
        //std.debug.print("path={any}\r\n", .{path});
    } else {
        try expect(false);
    }
}

test "gamerr1" {
    var gs = GameState.init();

    const pi = 0;
    gs.graph = .{ .bitMatrix = .{ 514, 1029, 10, 20, 40, 80, 160, 320, 131200, 1025, 2562, 5120, 10240, 20480, 8192, 16842752, 33718272, 67174656, 134742016, 269746176, 539492352, 1078984704, 2157969408, 4299161600, 8623521792, 17263820800, 34393423872, 68988174336, 138110566400, 276221132800, 552442265600, 1104884531200, 2209769062400, 4419538124800, 8839076249600, 17609433022464, 35321945260032, 343865819136, 687731638272, 1375463276544, 2750926553088, 1131401759948800, 2262803519897600, 4525607039795200, 9016029707501568, 70437463654400, 175921860444160, 72409437758816256, 144818875517632512, 288511851128422400, 2253998836940800, 5633897580724224, 11267795161448448, 4521191813414912, 9259400833873739776, 90071992547409920, 180284722583175168, 360569445166350336, 144678138029277184, 295147905179352825856, 592601653367919345664, 1186356228240445538304, 2363489084444036300800, 4740831241341864247296, 9490849825923564306432, 92233720368547758080, 184467440737095516160, 368934881474191032320, 148150413341979836416, 303413199445879311826944, 607416694702117329305600, 1210111022921365013397504, 9453956337776145203200, 23630279158421935620096, 47223664828696452136960, 94447329657392904273920, 188894659314785808547840, 377789318629571617095680, 756168933069501939843072, 1512337866139003879686144, 606824093048749409959936 } };
    gs.pawns = .{ Pawn{ .pos = .{ .x = 2, .y = 0 }, .goaly = 8, .numFencesRemaining = 1 }, Pawn{ .pos = .{ .x = 1, .y = 7 }, .goaly = 0, .numFencesRemaining = 1 } };
    gs.fences = .{ PosDir{ .pos = .{ .x = 3, .y = 4 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 5, .y = 5 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 3, .y = 6 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 2, .y = 7 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 1, .y = 4 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 7, .y = 5 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 4, .y = 7 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 5, .y = 6 }, .dir = Dir.vert }, PosDir{ .pos = .{ .x = 0, .y = 1 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 2, .y = 1 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 4, .y = 1 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 4, .y = 5 }, .dir = Dir.vert }, PosDir{ .pos = .{ .x = 5, .y = 1 }, .dir = Dir.vert }, PosDir{ .pos = .{ .x = 4, .y = 0 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 2, .y = 0 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 6, .y = 0 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 0, .y = 5 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 1, .y = 6 }, .dir = Dir.horz }, PosDir{ .pos = .{ .x = 0, .y = 0 }, .dir = Dir.vert }, PosDir{ .pos = .{ .x = 0, .y = 0 }, .dir = Dir.vert } };

    //gs.print();

    var machine = UiAgentMachine.init();
    try machine.selectMoveInteractive(&gs, pi);
    _ = try machine.process(&gs, pi);

    if (machine.getCompletedMove()) |_| {
        //std.debug.print("{any}\r\n", .{vm});
        try expect(true);
    } else {
        try expect(false);
    }
}

test "record" {
    var record = try GameRecord.init(std.heap.page_allocator);
    defer record.deinit();

    const moves:[4]Move = .{
        .{ .pawn = .{ .x = 4, .y = 1 } },
        .{ .pawn = .{ .x = 4, .y = 7 } },
        .{ .fence = .{.pos = .{ .x = 7, .y = 7 }, .dir = .horz }},
        .{ .fence = .{.pos = .{ .x = 0, .y = 1 }, .dir = .vert }},
    };
    const expectedRaw:[4]u8 = .{ 141, 195, 127, 16 };

    // record all moves
    for (moves) |m| {
        try record.append(m);
    }
    
    // check stored list is same
    var storedMoves = record.getAllMoves();
    try expect(storedMoves.len == moves.len);
    for (0..moves.len) |i| {
        try expect(std.meta.eql(storedMoves[i], moves[i]));
    }

    // get raw byte representation
    var rawbuf:[128]u8 = undefined;
    const raw = try record.encodeRaw(&rawbuf);
    try expect(std.mem.eql(u8, &expectedRaw, raw));

    // convert raw back to new record
    var rec2 = try GameRecord.initFromBuf(std.heap.page_allocator, raw);
    defer rec2.deinit();
    storedMoves = rec2.getAllMoves();
    try expect(storedMoves.len == moves.len);
    for (0..moves.len) |i| {
        try expect(std.meta.eql(storedMoves[i], moves[i]));
    }

    const s = try rec2.printGlendenningAlloc(std.heap.page_allocator);
    defer std.heap.page_allocator.free(s);

    try expect(std.mem.eql(u8, s, "1. e2 e8\n2. h8h a2v\n"));
}

//test "speed" {
//    var pi:usize = 0;
//    config.players[0] = try UiAgent.make("random");
//    config.players[1] = try UiAgent.make("random");
//    const runs = 100;
//
//    clock.initTime();
//    const start = clock.millis();
//
//    for (0..runs) |_| {
//        var gs = GameState.init();
//        while(!gs.hasWon(0) and !gs.hasWon(1)) {
//            try config.players[pi].selectMoveInteractive(&gs, pi);
//            try config.players[pi].process(&gs, pi);
//            // FIXME assumes move is available immediately, should poll for it and call process repeatedly
//            if (config.players[pi].getCompletedMove()) |vmove| {
//                try gs.applyMove(pi, vmove);
//                pi = (pi + 1) % config.NUM_PAWNS;
//            }
//        }
//    }
//    const end = clock.millis();
//    std.debug.print("t={any}\r\n", .{end-start});
//
//    try expect(end-start < 3000);
//
//
//}
