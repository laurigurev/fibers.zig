const std = @import("std");
const fib = @import("fibers.zig");

fn foo() void {
    const user_data = fib.getUserData(Foo);
    std.debug.print("hello fibers from foo at step 0 with user data of {}!\n", .{user_data.*});
    fib.pause(1);
    std.debug.print("hello fibers from foo at step 1!\n", .{});
    fib.pause(0);
    std.debug.print("hello fibers from foo at step 2!\n", .{});
    fib.pause(0);
    std.debug.print("hello fibers from foo at step 3!\n", .{});
}

const Foo = struct {
    a: u64 = 0,
    b: u64 = 1,
    c: u64 = 2,
    d: u64 = 3,
};

fn bar() void {
    const user_data = fib.getUserData(Bar);
    std.debug.print("hello fibers from bar with user data of {}!\n", .{user_data.*});
    const foo_val = fib.get_value("foo");
    fib.set_value("foo", foo_val - 1);
}

const Bar = struct {
    a: u64 = 4,
    b: u64 = 5,
    c: u64 = 6,
};

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

    const foo_user_data = fib.pack(Foo{});
    const bar_user_data = fib.pack(Bar{});

    fib.push(.{ .name = "foo", .func = p_foo, .user_data = foo_user_data});
    fib.push(.{ .name = "bar", .func = p_bar, .user_data = bar_user_data});

    while (fib.poll()) {
        fib.run();
    }

    std.debug.print("end main!\n", .{});
}

