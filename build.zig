const std = @import("std");

pub fn build(b: *std.Build) void {
    var options = b.addOptions();
    const web = b.option(bool, "web", "Target web") orelse false;   // -Dweb=<bool>
    options.addOption(bool, "web", web);

    const stdTarget = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const webTarget = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const exe = b.addExecutable(.{
        .name = "zoridor",
        .root_source_file = b.path("src/main.zig"),
        .target = if (web) webTarget else stdTarget,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    if (web) {
        std.debug.print("Building for web\n", .{});
        b.installFile("src/index.html", "index.html");
        b.installFile("src/zoridor.js", "zoridor.js");
        exe.rdynamic = true;
    } else {
        std.debug.print("Building for terminal (not web)\n", .{});
        const mibu = b.dependency("mibu", .{
            .target = stdTarget,
            .optimize = optimize,
        });
        exe.root_module.addImport("mibu", mibu.module("mibu"));

        const yazap = b.dependency("yazap", .{});
        exe.root_module.addImport("yazap", yazap.module("yazap"));

        const exe_unit_tests = b.addTest(.{
            .root_source_file = b.path("src/test.zig"),
            .target = stdTarget,
            .optimize = optimize,
        });
        exe_unit_tests.root_module.addImport("mibu", mibu.module("mibu"));

        const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_exe_unit_tests.step);
    }

    // allow @import("buildopts")
    exe.root_module.addOptions("buildopts", options);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

}
