const std = @import("std");
const fib = @import("fibers.zig");

fn foo() void {
    std.debug.print("hello fibers from foo at step 0!\n", .{});
    fib.pause(0);
    std.debug.print("hello fibers from foo at step 1!\n", .{});
    fib.pause(0);
    std.debug.print("hello fibers from foo at step 2!\n", .{});
    fib.pause(0);
    std.debug.print("hello fibers from foo at step 3!\n", .{});
}

fn bar() void {
    std.debug.print("hello fibers from bar!\n", .{});
    // const foo_val = fib.get_value("foo");
    // fib.set_value("foo", foo_val - 1);
}

pub fn main() !void {
    std.debug.print("begin main!\n", .{});

    const p_foo: usize = @intFromPtr(&foo);
    const p_bar: usize = @intFromPtr(&bar);

    const len: usize = fib.sizeof();

    const MEM_COMMIT: u32 = 0x00001000;
    const PAGE_EXECUTE_READWRITE: u32 = 0x40;
    const ptr: *anyopaque = try std.os.windows.VirtualAlloc(null, len, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    const mem: usize = @intFromPtr(ptr);

    fib.init(mem);

    fib.push(.{ .name = "foo", .func = p_foo});
    fib.push(.{ .name = "bar", .func = p_bar});

    while (fib.poll()) {
        fib.run();
    }

    std.debug.print("end main!\n", .{});
}

