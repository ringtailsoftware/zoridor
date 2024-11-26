const std = @import("std");

pub const BitGraph = struct {
    pub const NodeId = u8; // 0 <= n < 81
    pub const Coord = u4; // 0 <= n < 9
    pub const CoordPos = struct { x: Coord, y: Coord };
    pub const NodeIdRange = struct { // a range of continuous node ids inclusive of min and max
        min: NodeId,
        max: NodeId,
    };
    pub const MAXPATH = 9 * 9;
    const Self = @This();

    bitMatrix: [9 * 9]u128, // 81 lines, each using first 81 bits

    pub fn init() Self {
        return Self{
            .bitMatrix = std.mem.zeroes([9 * 9]u128),
        };
    }

    pub fn clone(other: *const Self) Self {
        return other.*;
    }

    pub fn delNode(self: *Self, dn: NodeId) void {
        // disconnect/orphan node, routing around it in graph

        // contruct list in outgoing of everything dn is currently connected to
        var outgoing: [9 * 9]NodeId = undefined;
        var numOutgoing: usize = 0;

        for (0..9 * 9) |n| { // could look at a smaller set, but should be quite fast
            if (dn != n) {
                if (self.hasEdgeUni(dn, @as(NodeId, @intCast(n)))) {
                    outgoing[numOutgoing] = @intCast(n);
                    numOutgoing += 1;
                }
            }
        }

        // for every node, if it did connect to dn, reroute to dn's children
        for (0..9 * 9) |n| {
            if (dn != n) { // not self
                if (self.hasEdgeUni(@intCast(n), @as(NodeId, @intCast(dn)))) {
                    for (outgoing[0..numOutgoing]) |outn| {
                        if (n != outn) { // don't connect nodes to selves
                            self.addEdgeBi(@intCast(n), outn);
                        }
                    }
                    self.delEdgeBi(dn, @intCast(n)); // remove old edge to dn
                }
            }
        }
    }

    // add a bidirectional edge
    pub fn addEdgeBi(self: *Self, n1: NodeId, n2: NodeId) void {
        std.debug.assert(n1 < 9 * 9);
        std.debug.assert(n2 < 9 * 9);
        std.debug.assert(n1 != n2);
        self.bitMatrix[n1] |= @as(u128, 1) << @as(u7, @intCast(n2));
        self.bitMatrix[n2] |= @as(u128, 1) << @as(u7, @intCast(n1));
    }

    // delete a bidirectional edge
    pub fn delEdgeBi(self: *Self, n1: NodeId, n2: NodeId) void {
        std.debug.assert(n1 < 9 * 9);
        std.debug.assert(n2 < 9 * 9);
        std.debug.assert(n1 != n2);
        self.bitMatrix[n1] &= ~(@as(u128, 1) << @as(u7, @intCast(n2)));
        self.bitMatrix[n2] &= ~(@as(u128, 1) << @as(u7, @intCast(n1)));
    }

    pub fn hasAnyEdges(self: *const Self, n1: NodeId) bool {
        std.debug.assert(n1 < 9 * 9);
        return self.bitMatrix[n1] != 0;
    }

    pub fn hasEdgeUni(self: *const Self, n1: NodeId, n2: NodeId) bool {
        std.debug.assert(n1 < 9 * 9);
        std.debug.assert(n2 < 9 * 9);
        std.debug.assert(n1 != n2);
        return self.bitMatrix[n1] & @as(u128, 1) << @as(u7, @intCast(n2)) > 0;
    }

    pub fn coordPosToNodeId(p: CoordPos) NodeId {
        std.debug.assert(p.x < 9);
        std.debug.assert(p.y < 9);
        return @as(NodeId, @intCast(p.y)) * 9 + @as(NodeId, @intCast(p.x));
    }

    pub fn nodeIdToCoordPos(n: NodeId) CoordPos {
        std.debug.assert(n < 9 * 9);
        const y = n / 9;
        const x = n - (y * 9);
        return .{ .x = @intCast(x), .y = @intCast(y) };
    }

    pub fn addCoordEdgeBi(self: *Self, a: CoordPos, b: CoordPos) void {
        self.addEdgeBi(coordPosToNodeId(a), coordPosToNodeId(b));
    }

    pub fn hasCoordEdgeUni(self: *const Self, a: CoordPos, b: CoordPos) bool {
        return self.hasEdgeUni(coordPosToNodeId(a), coordPosToNodeId(b));
    }

    pub fn delCoordEdgeBi(self: *Self, a: CoordPos, b: CoordPos) void {
        self.delEdgeBi(coordPosToNodeId(a), coordPosToNodeId(b));
    }

    pub fn addGridEdges(self: *Self) void {
        // all bi-directional links between all orthogonal nodes on grid
        for (0..9) |y| {
            for (0..9) |x| {
                // many edges being repeatedly added, slow but harmless
                // left
                if (x > 0) {
                    self.addCoordEdgeBi(.{ .x = @intCast(x), .y = @intCast(y) }, .{ .x = @intCast(x - 1), .y = @intCast(y) });
                }
                // right
                if (x < 8) {
                    self.addCoordEdgeBi(.{ .x = @intCast(x), .y = @intCast(y) }, .{ .x = @intCast(x + 1), .y = @intCast(y) });
                }
                // up
                if (y > 0) {
                    self.addCoordEdgeBi(.{ .x = @intCast(x), .y = @intCast(y) }, .{ .x = @intCast(x), .y = @intCast(y - 1) });
                }
                // down
                if (y < 8) {
                    self.addCoordEdgeBi(.{ .x = @intCast(x), .y = @intCast(y) }, .{ .x = @intCast(x), .y = @intCast(y + 1) });
                }
            }
        }
    }

    pub fn findShortestPath(self: *const Self, start: NodeId, goal: NodeIdRange, path: *[MAXPATH]NodeId, anyPath: bool) ?[]NodeId {
        // find shortest path from start to any node in goal range, returning slice of NodeIds using path as buffer
        // if anyPath is set, exit with non-null result if goal is ever reached
        const NodeData = struct {
            parent: NodeId,
            pathCost: ?u8,
        };

        var nodes: [9 * 9]NodeData = undefined;
        for (0..9 * 9) |i| {
            nodes[i] = .{
                .pathCost = null, // unknown
                .parent = undefined,
            };
        }

        // stack of nodes to expand
        var toExpand: [9 * 9]NodeId = undefined;
        var toExpandTopIndex: usize = 0;

        // push starting node position to be expanded
        toExpand[toExpandTopIndex] = start;
        toExpandTopIndex += 1;
        nodes[start].pathCost = 0;

        outer: while (toExpandTopIndex > 0) {
            // pop
            const n = toExpand[toExpandTopIndex - 1]; // new pos to explore
            toExpandTopIndex -= 1;

            // for everything n is connected to
            if (self.hasAnyEdges(n)) {
                for (0..9 * 9) |n2| {
                    if (n != n2) {
                        if (self.hasEdgeUni(n, @as(NodeId, @intCast(n2)))) {
                            // n has edge to n2
                            var doExplore = false;
                            if (nodes[n2].pathCost) |existingCost| {
                                if (nodes[n].pathCost.? + 1 < existingCost) {
                                    doExplore = true;
                                }
                            } else { // unvisited node
                                doExplore = true;
                            }
                            if (doExplore) {
                                nodes[n2].pathCost = nodes[n].pathCost.? + 1;
                                nodes[n2].parent = n;

                                // push
                                toExpand[toExpandTopIndex] = @as(NodeId, @intCast(n2));
                                toExpandTopIndex += 1;
                            }

                            if (anyPath) {
                                if (n2 >= goal.min and n2 <= goal.max) {
                                    continue :outer;
                                }
                            }
                        }
                    }
                }
            }
        }

        // all discovered path costs
        //        for (0..9) |y| {
        //            for (0..9) |x| {
        //                if (nodes[y*9+x].pathCost) |cost| {
        //                    std.debug.print("{d:0>2} ", .{cost});
        //                } else {
        //                    std.debug.print("XX ", .{});
        //                }
        //            }
        //            std.debug.print("\r\n", .{});
        //        }
        //        std.debug.print("\r\n", .{});
        //self.print();
        //self.printEdges();

        // find cheapest node on the goal line, then work backwards from there to find path
        var bestPathCost: usize = undefined;
        var bestGoal: ?NodeId = null;
        var first = true;
        for (goal.min..goal.max + 1) |g| {
            if (nodes[g].pathCost) |pathCost| {
                if (first or pathCost < bestPathCost) {
                    first = false;
                    bestGoal = @as(NodeId, @intCast(g));
                    bestPathCost = pathCost;
                }
            }
        }

        if (bestGoal) |g| {
            //            std.debug.print("{any} -> {any} ({any})\r\n", .{start, g, nodes[g].pathCost.?});
            // work backwards from the the target until reaching the root
            const pathLen = nodes[g].pathCost.?;
            path[nodes[g].pathCost.?] = g;
            var cur = g;
            while (true) {
                const n = nodes[cur];
                path[n.pathCost.?] = cur;
                if (n.pathCost == 0) { // reached starting node
                    break;
                }
                cur = n.parent;
            }
            return path[0 .. pathLen + 1];
        } else {
            // goal unreachable
            return null;
        }
    }

    pub fn printEdges(self: *const Self) void {
        for (0..9 * 9) |i| {
            std.debug.print("{d} => ", .{i});
            for (0..9 * 9) |j| {
                if (i != j) {
                    if (self.hasEdgeUni(@intCast(i), @intCast(j))) {
                        std.debug.print("{d} ", .{j});
                    }
                }
            }
            std.debug.print("\r\n", .{});
        }
        std.debug.print("\r\n", .{});
    }

    pub fn print(self: *const Self) void {
        // 00<>01< 02
        // ^V  ^V  V
        // 03<>04<>05
        std.debug.print("\r\n", .{});

        for (0..9) |y| {
            for (0..9) |x| {
                std.debug.print("{d:0>2}", .{coordPosToNodeId(.{ .x = @intCast(x), .y = @intCast(y) })});
                const me = CoordPos{ .x = @intCast(x), .y = @intCast(y) };
                if (x < 8) {
                    const right = CoordPos{ .x = @intCast(x + 1), .y = @intCast(y) };
                    if (self.hasCoordEdgeUni(right, me)) {
                        std.debug.print("<", .{});
                    } else {
                        std.debug.print(" ", .{});
                    }

                    if (self.hasCoordEdgeUni(me, right)) {
                        std.debug.print(">", .{});
                    } else {
                        std.debug.print(" ", .{});
                    }
                }
            }
            std.debug.print("\r\n", .{});
            if (y < 8) {
                for (0..9) |x| {
                    const me = CoordPos{ .x = @intCast(x), .y = @intCast(y) };
                    const down = CoordPos{ .x = @intCast(x), .y = @intCast(y + 1) };
                    if (self.hasCoordEdgeUni(me, down)) {
                        std.debug.print("V", .{});
                    } else {
                        std.debug.print(" ", .{});
                    }
                    if (self.hasCoordEdgeUni(down, me)) {
                        std.debug.print("^", .{});
                    } else {
                        std.debug.print(" ", .{});
                    }
                    std.debug.print("  ", .{});
                }
            }
            std.debug.print("\r\n", .{});
        }
        std.debug.print("\r\n", .{});
    }
};
