const std = @import("std");

const Display = @import("display.zig").Display;

const clock = @import("clock.zig");
const config = @import("config.zig");

const GameState = @import("gamestate.zig").GameState;
const GameRecord = @import("record.zig").GameRecord;
const Move = @import("gamestate.zig").Move;

const UiAgent = @import("ui.zig").UiAgent;
const UiAgentHuman = @import("uiagenthuman.zig").UiAgentHuman;
const UiAgentMachine = @import("uiagentmachine.zig").UiAgentMachine;
const drawGame = @import("ui.zig").drawGame;
const emitMoves = @import("ui.zig").emitMoves;

const buildopts = @import("buildopts");

const console = @import("console.zig").getWriter().writer();

const w4 = @import("wasm4.zig");

var human_pi:usize = 0;

const WebState = struct {
    pi: usize,
    gs: GameState,
    record: GameRecord,
    recordB64Buf: ?[]const u8,  // base64 of all moves performed so far
    startB64Buf: [1024]u8,  // buffer to setup initial game state
    start: ?[]u8,
};
var wstate:WebState = undefined;
var inited = false;

var endgame = true;
var endgame_time:u32 = 0;

fn updateRecord(move:Move) !void {
    _ = move;
//    try wstate.record.append(move);
//    // generate base64 for game
//    if (wstate.recordB64Buf) |buf| {
//        std.heap.page_allocator.free(buf);
//        wstate.recordB64Buf = null;
//    }
//    wstate.recordB64Buf = try wstate.record.toStringBase64Alloc(std.heap.page_allocator);
}

// exposed to JS
fn getNextMoveInternal() !void {
//_ = console.print("gnmi {d}\r\n", .{wstate.pi}) catch 0;
    wstate.pi = (wstate.pi + 1) % config.NUM_PAWNS;

    // FIXME assumes move is available immediately, js should poll for it and call process repeatedly
    try config.players[wstate.pi].selectMoveInteractive(&wstate.gs, wstate.pi);
    try config.players[wstate.pi].process(&wstate.gs, wstate.pi);
    if (config.players[wstate.pi].getCompletedMove()) |vmove| {
        try wstate.gs.applyMove(wstate.pi, vmove);
        try updateRecord(vmove.move);
        // next player
        wstate.pi = (wstate.pi + 1) % config.NUM_PAWNS;
    }
}

export fn isFenceMoveLegal(x:usize, y:usize, dir:u8) bool {
    const move = Move{ .fence = .{ .pos = .{ .x = @intCast(x), .y = @intCast(y) }, .dir = if (dir=='v') .vert else .horz } };
    const vm = try wstate.gs.verifyMove(wstate.pi, move);
    return vm.legal;
}

export fn isPawnMoveLegal(x:usize, y:usize) bool {
    const move = Move{ .pawn = .{ .x = @intCast(x), .y = @intCast(y) } };
    const vm = try wstate.gs.verifyMove(wstate.pi, move);
    return vm.legal;
}

export fn moveFence(x:usize, y:usize, dir:u8) void {
    const move = Move{ .fence = .{ .pos = .{ .x = @intCast(x), .y = @intCast(y) }, .dir = if (dir=='v') .vert else .horz } };
    const vm = try wstate.gs.verifyMove(wstate.pi, move);
    try wstate.gs.applyMove(wstate.pi, vm);
    _ = updateRecord(vm.move) catch 0;

    // move opponent
    _ = getNextMoveInternal() catch 0;
}

export fn movePawn(x:usize, y:usize) void {
    const move = Move{ .pawn = .{ .x = @intCast(x), .y = @intCast(y) } };
    const vm = try wstate.gs.verifyMove(wstate.pi, move);
    try wstate.gs.applyMove(wstate.pi, vm);
    _ = updateRecord(vm.move) catch 0;

    // move opponent
    _ = getNextMoveInternal() catch 0;
}

export fn getPlayerIndex() usize {
    return wstate.pi;
}

export fn hasWon(pi:usize) bool {
    return wstate.gs.hasWon(pi);
}

export fn getNumFences() usize {
    return wstate.gs.numFences;
}
export fn getFencePosX(i:usize) usize {
    return wstate.gs.fences[i].pos.x;
}
export fn getFencePosY(i:usize) usize {
    return wstate.gs.fences[i].pos.y;
}
export fn getFencePosDir(i:usize) usize {
    return switch(wstate.gs.fences[i].dir) {
        .vert => 'v',
        .horz => 'h',
    };
}

export fn getPawnPosX(pi:usize) usize {
    return wstate.gs.getPawnPos(pi).x;
}
export fn getPawnPosY(pi:usize) usize {
    return wstate.gs.getPawnPos(pi).y;
}

export fn getFencesRemaining(pi:usize) usize {
    return wstate.gs.pawns[pi].numFencesRemaining;
}

export fn restart(pi:usize) bool {
//    const b64input = wstate.startB64Buf[0..setupB64Len];
    //_ = console.print("RESTART setupB64Len={d} s={s}\n", .{setupB64Len, b64input}) catch 0;
    return gamesetup(pi, null) catch false;
}

export fn allocUint8(length: u32) [*]const u8 {
    const slice = std.heap.page_allocator.alloc(u8, length) catch
        @panic("failed to allocate memory");
    return slice.ptr;
}

export fn getGameStartRecordLen() usize {
    return wstate.startB64Buf.len;
}

export fn getGameStartRecordPtr() [*]const u8 {
    return (&wstate.startB64Buf).ptr;
}

export fn getGameRecordPtr() [*]const u8 {
    if (wstate.recordB64Buf) |b| {
        return b.ptr;
    } else {
        return @ptrFromInt(0xDEADBEEF);  // len will be 0, so ignored
    }
}
export fn getGameRecordLen() usize {
    if (wstate.recordB64Buf) |b| {
        return b.len;
    } else {
        return 0;
    }
}

fn gamesetup(piStart:usize, b64O:?[]const u8) !bool {
    if (inited) {
        wstate.record.deinit();
        if (wstate.recordB64Buf != null) {
            std.heap.page_allocator.free(wstate.recordB64Buf.?);
        }
    }

    var pi = piStart;
    var gs = GameState.init();
    var recordB64Buf:?[]const u8 = null;
    var record:GameRecord = undefined;
    if (b64O) |b64| {
        // user supplied starting state
        record = try GameRecord.initFromBase64(std.heap.page_allocator, b64);
        gs = try record.toGameState(true);
        recordB64Buf = try record.toStringBase64Alloc(std.heap.page_allocator);
        pi += record.getAllMoves().len % 2;
    } else {
        record = try GameRecord.init(std.heap.page_allocator);
    }

    wstate = .{
        .pi = pi,
        .gs = gs,
        .record = record,
        .recordB64Buf = recordB64Buf,
        .startB64Buf = undefined,
        .start = null,
    };
    inited = true;
    config.players[0] = try UiAgent.make("machine");    // should be "null"
    config.players[1] = try UiAgent.make("machine");
    if (pi != 0) {
        _ = getNextMoveInternal() catch 0;
    }
    return true;
}

fn pixel(x: i32, y: i32) void {
    // The byte index into the framebuffer that contains (x, y)
    //const idx = (@intCast(y) * 160 + @intCast(usize, x)) >> 2;
    const idx:usize = @intCast((y * 160 + x) >> 2);

    // Calculate the bits within the byte that corresponds to our position
    const shift:u3 = @intCast((x & 0b11) * 2);
    const mask:u8 = @as(u8, 0b11) << shift;

    // Use the first DRAW_COLOR as the pixel color
    const palette_color:u8 = @intCast(w4.DRAW_COLORS.* & 0b1111);
    if (palette_color == 0) {
        // Transparent
        return;
    }
    const color:u8 = (palette_color - 1) & 0b11;

    // Write to the framebuffer
    w4.FRAMEBUFFER[idx] = (color << shift) | (w4.FRAMEBUFFER[idx] & ~mask);
}

fn dotrect(x:i32, y:i32, w:i32, h:i32) void {
    var xen = false;
    var yen = false;
    for (@intCast(x)..@intCast(x+w)) |xo| {
        xen = !xen;
        for (@intCast(y)..@intCast(y+h)) |yo| {
            yen = !yen;
            if (xen and yen) {
                pixel(@intCast(xo), @intCast(yo));
            }
        }
    }
}

fn blit_counter(xoff:usize, yoff:usize) void {
    const counter_sprite = [13]u13{
        0b0000111110000,
        0b0001111111000,
        0b0011111111100,
        0b0111111111110,
        0b1111111111111,
        0b1111111111111,
        0b1111111111111,
        0b1111111111111,
        0b1111111111111,
        0b0111111111110,
        0b0011111111100,
        0b0001111111000,
        0b0000111110000,
    };

    for (0..13) |y| {
        for (0..13) |x| {
            if (counter_sprite[y] & (@as(u13, 1) << @intCast(x)) != 0) {
                pixel(@intCast(xoff + x), @intCast(yoff + y));
            }
        }
    }
}

fn drawboard() void {
    const mouse  = w4.MOUSE_BUTTONS.*;
    const mouseX = w4.MOUSE_X.*;
    const mouseY = w4.MOUSE_Y.*;

    const colour_p0 = 0x11;
    const colour_p1 = 0x44;
    const colour_fence = 0x44;
    const colour_bg = 0x22;
    const colour_squares = 0x33;

    // background
    w4.DRAW_COLORS.* = colour_fence;
    w4.rect(0, 0, 160, 160); 

    const board_off_x = 10;
    const board_off_y = 9;
    const sq_sz = 13;
    const fence_sz = 3;

    // panels
    const p0_panel_x = 0;
    const p0_panel_y = 0;
    const p0_panel_w = 159;
    const p0_panel_h = 8;
    w4.DRAW_COLORS.* = colour_bg;
    w4.rect(p0_panel_x, p0_panel_y, p0_panel_w, p0_panel_h);

    const p1_panel_x = 0;
    const p1_panel_y = 151;
    const p1_panel_w = 159;
    const p1_panel_h = 8;
    w4.DRAW_COLORS.* = colour_bg;
    w4.rect(p1_panel_x, p1_panel_y, p1_panel_w, p1_panel_h);

    const left_panel_x = 1;
    const left_panel_y = 9;
    const left_panel_w = 8;
    const left_panel_h = 141;
    w4.DRAW_COLORS.* = colour_bg;
    w4.rect(left_panel_x, left_panel_y, left_panel_w, left_panel_h);

    const name = "Zoridor";
    w4.DRAW_COLORS.* = 0x24;
    var ch_y:i32 = @as(i32, left_panel_y) + ((left_panel_h - (name.len * 8)))/2;
    for (0..name.len) |i| {
        w4.text(&.{name[(i + clock.millis() / 1000) % name.len]}, left_panel_x, ch_y);
        ch_y += 8;
    }

    const right_panel_x = 152;
    const right_panel_y = 9;
    const right_panel_w = 7;
    const right_panel_h = 141;
    w4.DRAW_COLORS.* = colour_bg;
    w4.rect(right_panel_x, right_panel_y, right_panel_w, right_panel_h);

    // draw board squares
    w4.DRAW_COLORS.* = colour_bg;
    w4.rect(board_off_x, board_off_y, 9*sq_sz + 8*fence_sz, 9*sq_sz + 8*fence_sz); 

    w4.DRAW_COLORS.* = colour_squares;
    for (0..9) |y| {
        for (0..9) |x| {
            const tlx = board_off_x + (x * (sq_sz+fence_sz));
            const tly = board_off_y + (y * (sq_sz+fence_sz));
            w4.rect(@intCast(tlx), @intCast(tly), sq_sz, sq_sz);
        }
    }

    // p0 fences remaining
    const p0_fences_remaining = getFencesRemaining(0);
    w4.DRAW_COLORS.* = colour_p0;
    for (0..p0_fences_remaining) |i| {
        const tlx = 1 + p0_panel_x + i * (fence_sz + (fence_sz-1));
        const tly = p0_panel_y + 1;
        const w = fence_sz;
        const h = p0_panel_h - 2;
        w4.rect(@intCast(tlx), @intCast(tly), w, h);
    }

    // p1 fences remaining
    const p1_fences_remaining = getFencesRemaining(1);
    w4.DRAW_COLORS.* = colour_p1;
    for (0..p1_fences_remaining) |i| {
        const tlx = 1 + p1_panel_x + i * (fence_sz + (fence_sz-1));
        const tly = p1_panel_y + 1;
        const w = fence_sz;
        const h = p1_panel_h - 2;
        w4.rect(@intCast(tlx), @intCast(tly), w, h);
    }

    // p0 counter
    const p0_board_x = getPawnPosX(0);
    const p0_board_y = getPawnPosY(0);
    w4.DRAW_COLORS.* = colour_p0;
    blit_counter(board_off_x + (p0_board_x * (sq_sz+fence_sz)), board_off_y + (p0_board_y * (sq_sz+fence_sz)));

    // p1 counter
    const p1_board_x = getPawnPosX(1);
    const p1_board_y = getPawnPosY(1);
    w4.DRAW_COLORS.* = colour_p1;
    blit_counter(board_off_x + (p1_board_x * (sq_sz+fence_sz)), board_off_y + (p1_board_y * (sq_sz+fence_sz)));

    
    const numfences = getNumFences();
    for (0..numfences) |i| {
        switch(getFencePosDir(i)) {
            'v' => {
                const vert_fence_x = getFencePosX(i);
                const vert_fence_y = getFencePosY(i);
                w4.DRAW_COLORS.* = colour_fence;
                const tlx = board_off_x + (vert_fence_x * (sq_sz+fence_sz)) + sq_sz;
                const tly = board_off_y + (vert_fence_y * (sq_sz+fence_sz));
                w4.rect(@intCast(tlx), @intCast(tly), fence_sz, sq_sz*2 + fence_sz);

            },
            'h' => {
                const horz_fence_x = getFencePosX(i);
                const horz_fence_y = getFencePosY(i);
                w4.DRAW_COLORS.* = colour_fence;
                const tlx = board_off_x + (horz_fence_x * (sq_sz+fence_sz));
                const tly = board_off_y + (horz_fence_y * (sq_sz+fence_sz)) + sq_sz;
                w4.rect(@intCast(tlx), @intCast(tly), sq_sz*2 + fence_sz, fence_sz);
            },
            else => {},
        }
    }

//    // draw a horz fence
//    {
//    const horz_fence_x = 2;
//    const horz_fence_y = 2;
//    w4.DRAW_COLORS.* = colour_fence;
//    const tlx = board_off_x + (horz_fence_x * (sq_sz+fence_sz));
//    const tly = board_off_y + (horz_fence_y * (sq_sz+fence_sz)) + sq_sz;
//    w4.rect(@intCast(tlx), @intCast(tly), sq_sz*2 + fence_sz, fence_sz);
//    }
//
//    // draw a vert fence
//    {
//    const vert_fence_x = 3;
//    const vert_fence_y = 6;
//    w4.DRAW_COLORS.* = colour_fence;
//    const tlx = board_off_x + (vert_fence_x * (sq_sz+fence_sz)) + sq_sz;
//    const tly = board_off_y + (vert_fence_y * (sq_sz+fence_sz));
//    w4.rect(@intCast(tlx), @intCast(tly), fence_sz, sq_sz*2 + fence_sz);
//    }

//pixel(mouseX, mouseY);

    // check if mouse is in a board square
    for (0..9) |y| {
        for (0..9) |x| {
            const tlx = board_off_x + (x * (sq_sz+fence_sz));
            const tly = board_off_y + (y * (sq_sz+fence_sz));
            if (mouseX >= tlx and mouseX < tlx + sq_sz) {
                if (mouseY > tly and mouseY < tly + sq_sz) {
                    if (!endgame and isPawnMoveLegal(x, y)) {
                        if (human_pi == 0) {
                            w4.DRAW_COLORS.* = colour_p0;
                        } else {
                            w4.DRAW_COLORS.* = colour_p1;
                        }
                        if (mouse != 0) {                    
                            movePawn(x, y);
                            return;
                        }
                    } else {
                        w4.DRAW_COLORS.* = colour_bg;
                    }
                    if (!endgame) {
                        blit_counter(board_off_x + (x * (sq_sz+fence_sz)), board_off_y + (y * (sq_sz+fence_sz)));
                    }
                }
            }
        }
    }

    // check if mouse is in a horz fence
    for (0..8) |y| {
        for (0..8) |x| {
            const tlx = board_off_x + (x * (sq_sz+fence_sz));
            const tly = board_off_y + (y * (sq_sz+fence_sz)) + sq_sz;
            const w = sq_sz;
            const h = fence_sz;

            if (mouseX >= tlx and mouseX < tlx + w) {
                if (mouseY > tly and mouseY < tly + h) {
                    if (!endgame) {
                        if (isFenceMoveLegal(x, y, 'h')) {
                            w4.DRAW_COLORS.* = colour_fence;
                            w4.rect(@intCast(tlx), @intCast(tly), sq_sz*2 + fence_sz, h);
                            if (mouse != 0) {                    
                                moveFence(x, y, 'h');
                                return;
                            }
                        } else {
                            w4.DRAW_COLORS.* = colour_fence;
                            dotrect(@intCast(tlx), @intCast(tly), sq_sz*2 + fence_sz, h);
                        }
                    }
                }
            }
        }
    }

    // check if mouse is in a vert fence
    for (0..8) |y| {
        for (0..8) |x| {
            const tlx = board_off_x + (x * (sq_sz+fence_sz)) + sq_sz;
            const tly = board_off_y + (y * (sq_sz+fence_sz));
            const w = fence_sz;
            const h = sq_sz;

            if (mouseX >= tlx and mouseX < tlx + w) {
                if (mouseY > tly and mouseY < tly + h) {
                    if (!endgame) {
                        if (isFenceMoveLegal(x, y, 'v')) {
                            w4.DRAW_COLORS.* = colour_fence;
                            w4.rect(@intCast(tlx), @intCast(tly), w, sq_sz*2 + fence_sz);
                            if (mouse != 0) {                    
                                moveFence(x, y, 'v');
                                return;
                            }
                        } else {
                            w4.DRAW_COLORS.* = colour_fence;
                            dotrect(@intCast(tlx), @intCast(tly), w, sq_sz*2 + fence_sz);
                        }
                    }
                }
            }
        }
    }

    if (hasWon(human_pi)) {
        w4.DRAW_COLORS.* = 0x21;
        const s = "You won!";
        w4.text(s, (160 - s.len*8)/2, (160 - 24)/2);
        if (!endgame) {
            endgame = true;
            endgame_time = clock.millis();
            return;
        }
    }
    if (hasWon((human_pi + 1) % config.NUM_PAWNS)) {
        w4.DRAW_COLORS.* = 0x24;
        const s = "You lost!";
        w4.text(s, (160 - s.len*8)/2, (160 - 24)/2);
        if (!endgame) {
            endgame = true;
            endgame_time = clock.millis();
            return;
        }
    }

    if (endgame) {
        if (clock.millis() > endgame_time + 100) {
            w4.DRAW_COLORS.* = 0x21;
            const s = "Click to pick player";
            w4.text(s, (160 - s.len*8)/2, (160 - 8)/2);

            w4.DRAW_COLORS.* = 0x21;
            w4.text("Play first?", p0_panel_x, p0_panel_y);
            w4.DRAW_COLORS.* = 0x24;
            w4.text("Play second?", p1_panel_x, p1_panel_y);

            if (mouse != 0) {
                // click top/bottom half
                if (mouseY < 160/2) {
                    human_pi = 0;
                    endgame = false;
                    _ = restart(human_pi);
                }
                if (mouseY >= 160/2) {
                    human_pi = 1;
                    endgame = false;
                    _ = restart(human_pi);
                }

            }
        }
    }
}

fn gamestart() !void {
    _ = restart(human_pi);
}

export fn start() void {
    w4.PALETTE.* = .{    0xfefeff,    0xf0a8b8,    0x708ace,    0x2c2f51};

    gamestart() catch @panic("start");
}

export fn update() void {
    clock.advance(1000/60);
    drawboard();
}


