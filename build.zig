const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    const zigline = b.dependency("zigline", .{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const exe = b.addExecutable(.{
        .name = "fy",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zigline", zigline.module("zigline"));

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    // Build tests in Debug mode to avoid optimizer-related heisenbugs during CI
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .Debug,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // macOS codesign configuration for JIT
    const builtin = @import("builtin");
    // Default to ad-hoc signing ("-") to avoid prompts locally.
    // Provide -Dcodesign-id="Your Identity" for release signing.
    const codesign_id_opt = b.option([]const u8, "codesign-id", "Code signing identity for macOS JIT (omit for ad-hoc)");
    const codesign_id = codesign_id_opt orelse "-";
    if (builtin.os.tag == .macos) {
        // Optionally sign unit test binary if you really need hardened runtime + JIT in tests
        const sign_tests_enabled = b.option(bool, "codesign-tests", "Codesign unit tests for macOS JIT (default: false)") orelse false;
        if (sign_tests_enabled) {
            const sign_tests = b.addSystemCommand(&[_][]const u8{
                "codesign", "-s", codesign_id, "--force", "--entitlements", "entitlements.plist", "--options", "runtime",
            });
            sign_tests.addFileArg(unit_tests.getEmittedBin());
            sign_tests.step.dependOn(&unit_tests.step);
            run_unit_tests.step.dependOn(&sign_tests.step);
        }
    }

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // gen-ffi tool — FFI binding generator
    const gen_ffi = b.addExecutable(.{
        .name = "gen-ffi",
        .root_source_file = b.path("tools/gen-ffi.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(gen_ffi);

    const run_gen_ffi = b.addRunArtifact(gen_ffi);
    run_gen_ffi.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_gen_ffi.addArgs(args);
    }
    const gen_ffi_step = b.step("gen-ffi", "Run FFI binding generator");
    gen_ffi_step.dependOn(&run_gen_ffi.step);

    // Codesign main exe on macOS
    if (builtin.os.tag == .macos) {
        const sign_exe = b.addSystemCommand(&[_][]const u8{
            "codesign", "-s", codesign_id, "--force", "--entitlements", "entitlements.plist", "--options", "runtime",
        });
        sign_exe.addFileArg(exe.getEmittedBin());
        sign_exe.step.dependOn(&exe.step);
        run_cmd.step.dependOn(&sign_exe.step);

        // Ensure install runs after signing emitted fy so installed binary is signed
        b.getInstallStep().dependOn(&sign_exe.step);

        // Expose an explicit step to install and sign artifacts
        const install_signed = b.step("install-signed", "Install and sign fy with entitlements");
        install_signed.dependOn(b.getInstallStep());
    }
}
