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
        .root_source_file = b.path(if (web) "src/webmain.zig" else "src/main.zig"),
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
        b.installFile("src/cart.html", "cart.html");
        b.installFile("src/cart.wasm", "cart.wasm");
        b.installFile("src/wasm4.css", "wasm4.css");
        b.installFile("src/wasm4.js", "wasm4.js");
        b.installFile("src/zoridor.js", "zoridor.js");
        b.installFile("src/live.js", "live.js");
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
        exe_unit_tests.root_module.addOptions("buildopts", options);

        const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_exe_unit_tests.step);
    }

    // allow @import("buildopts")
    exe.root_module.addOptions("buildopts", options);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);


    // web server
    const serve_exe = b.addExecutable(.{
        .name = "serve",
        .root_source_file = b.path("httpserver/serve.zig"),
        .target = stdTarget,
        .optimize = optimize,
    });

    const mod_server = b.addModule("StaticHttpFileServer", .{
        .root_source_file = b.path("httpserver/root.zig"),
        .target = stdTarget,
        .optimize = optimize,
    });

    mod_server.addImport("mime", b.dependency("mime", .{
        .target = stdTarget,
        .optimize = optimize,
    }).module("mime"));

    serve_exe.root_module.addImport("StaticHttpFileServer", mod_server);

    const run_serve_exe = b.addRunArtifact(serve_exe);
    if (b.args) |args| run_serve_exe.addArgs(args);

    const serve_step = b.step("serve", "Serve a directory of files");
    serve_step.dependOn(&run_serve_exe.step);

}
