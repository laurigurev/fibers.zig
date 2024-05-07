const std = @import("std");
const fib = @import("fibers.zig");

fn foo() void {
    std.debug.print("hello fibers from foo at step 0!\n", .{});
    fib.pause();
    std.debug.print("hello fibers from foo at step 1!\n", .{});
    fib.pause();
    std.debug.print("hello fibers from foo at step 2!\n", .{});
    fib.pause();
    std.debug.print("hello fibers from foo at step 3!\n", .{});
}

fn bar() void {
    std.debug.print("hello fibers from bar!\n", .{});
}

pub fn main() !void {
    std.debug.print("begin main!\n", .{});

    const p_foo: usize = @intFromPtr(&foo);
    const p_bar: usize = @intFromPtr(&bar);

    const len: usize = 16*1024;

    const MEM_COMMIT: u32 = 0x00001000;
    const PAGE_EXECUTE_READWRITE: u32 = 0x40;
    const ptr: *anyopaque = try std.os.windows.VirtualAlloc(null, len, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    const mem: usize = @intFromPtr(ptr);

    fib.push(.{ .func = p_foo, .mem = mem         , .size = 8*1024 });
    fib.push(.{ .func = p_bar, .mem = mem + 8*1024, .size = 8*1024 });

    while (fib.poll()) {
        fib.run();
    }

    std.debug.print("end main!\n", .{});
}

