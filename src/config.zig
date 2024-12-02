const mibu = @import("mibu");
const color = mibu.color;
const yazap = @import("yazap"); // command line parsing
const std = @import("std");
const UiAgent = @import("ui.zig").UiAgent;

pub const GRIDSIZE: usize = 9;
pub const NUM_PAWNS = 2;
pub const NUM_FENCES = 20;
pub const MAXMOVES = (5 * 5) + 2 * (9 - 1) * (9 - 1); // largest possible number of legal moves, pawnmoves + fencemoves
pub const PAWN_EXPLORE_DIST = 2; // how many squares away to allow interactive exploring for pawn move
pub const pawnColour = [NUM_PAWNS]color.Color{ .yellow, .magenta };
pub const fenceColour: color.Color = .white;
pub const UI_XOFF = 3;
pub const UI_YOFF = 2;
pub const label_extra_w = 3;
pub const COLUMN_LABEL_START = 'a';
pub const ROW_LABEL_START = '1';

pub var mini = false;

pub var RANDOMSEED: ?u32 = null; // null = set from clock
pub var RANDOMNESS: u32 = 0;

pub var playForever = false;
pub var players:[NUM_PAWNS]UiAgent = undefined;
pub var b64GameStart:?[]u8 = null;

// for holding last turn string
pub var lastTurnBuf: [32]u8 = undefined;
pub var lastTurnStr: ?[]u8 = null;
pub var wins: [NUM_PAWNS]usize = .{ 0, 0 };

pub fn parseCommandLine() !void {
    const allocator = std.heap.page_allocator;
    const App = yazap.App;
    const Arg = yazap.Arg;

    var app = App.init(allocator, "zoridor", null);
    defer app.deinit();

    var zoridor = app.rootCommand();

    // find all available agent names
    var agentNames:[std.meta.fields(UiAgent).len][]const u8 = undefined;
    inline for (std.meta.fields(UiAgent), 0..) |f, i| {
        agentNames[i] = f.name;
    }

    const player1_opt = Arg.singleValueOptionWithValidValues("player1", '1', "Player 1 type", &agentNames);
    try zoridor.addArg(player1_opt);

    const player2_opt = Arg.singleValueOptionWithValidValues("player2", '2', "Player 2 type", &agentNames);
    try zoridor.addArg(player2_opt);

    var randseed_opt = Arg.singleValueOption("seedrand", 's', "Set random seed");
    randseed_opt.setValuePlaceholder("12345");
    try zoridor.addArg(randseed_opt);

    var randscore_opt = Arg.singleValueOption("randscore", 'r', "Set random move scoring value 0=same every time 100=random errors");
    randscore_opt.setValuePlaceholder("0");
    try zoridor.addArg(randscore_opt);

    const forever_opt = Arg.booleanOption("forever", 'f', "Play forever");
    try zoridor.addArg(forever_opt);

    const mini_opt = Arg.booleanOption("mini", 'm', "Mini display < 80x24");
    try zoridor.addArg(mini_opt);

    var load_opt = Arg.singleValueOption("load", 'l', "Load base64 game");
    load_opt.setValuePlaceholder("");
    try zoridor.addArg(load_opt);

    const matches = try app.parseProcess();

    if (matches.containsArg("forever")) {
        playForever = true;
    }

    if (matches.containsArg("mini")) {
        mini = true;
    }

    if (matches.containsArg("load")) {
        if (matches.getSingleValue("load")) |b64str| {
            b64GameStart = try allocator.dupe(u8, b64str);
        }
    }

    if (matches.containsArg("randseed")) {
        if (matches.getSingleValue("randseed")) |seedStr| {
            const i = std.fmt.parseInt(u32, seedStr, 10) catch return;
            RANDOMSEED = i;
        }
    }

    if (matches.containsArg("randscore")) {
        if (matches.getSingleValue("randscore")) |randStr| {
            const i = std.fmt.parseInt(u32, randStr, 10) catch return;
            RANDOMNESS = i;
        }
    }

    if (matches.containsArg("player1")) {
        if (matches.getSingleValue("player1")) |typ| {
            players[0] = try UiAgent.make(typ);
        }
    }

    if (matches.containsArg("player2")) {
        if (matches.getSingleValue("player2")) |typ| {
            players[1] = try UiAgent.make(typ);
        }
    }
}

