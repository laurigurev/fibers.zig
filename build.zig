const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
        
    
    
    const module = b.addModule("fibers", .{.root_source_file = .{ .path = "src/fibers.zig" } });
    
    const lib = b.addStaticLibrary(.{
        .name = "fibers",
        .root_source_file = .{ .path = "src/fibers.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);
    
    
    
    const lib_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/fibers.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    
    
    
    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = .{ .path = "example/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("fibers", module);
    b.installArtifact(exe);
    
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
