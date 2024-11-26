const mibu = @import("mibu");
const color = mibu.color;
const PlayerType = @import("ui.zig").PlayerType;
const yazap = @import("yazap"); // command line parsing
const std = @import("std");

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
pub var players: [NUM_PAWNS]PlayerType = .{ .Human, .Machine };

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

    var player1_opt = Arg.singleValueOptionWithValidValues("player1", '1', "Player 1 type", &[_][]const u8{ "human", "machine" });
    player1_opt.setValuePlaceholder("human|machine");
    try zoridor.addArg(player1_opt);

    var player2_opt = Arg.singleValueOptionWithValidValues("player2", '2', "Player 2 type", &[_][]const u8{ "human", "machine" });
    player2_opt.setValuePlaceholder("human|machine");
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

    if (matches.containsArg("randscore")) {
        const randStr = matches.getSingleValue("randscore").?;
        const i = std.fmt.parseInt(u32, randStr, 10) catch return;
        RANDOMNESS = i;
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
