const std = @import("std");
const fib = @import("fibers");

fn foo() void {
    const thread = fib.getThreadId();
    const user_data = fib.getUserData(Foo);

    std.debug.print("[foo0] thread {}, user_data {}\n", .{thread, user_data.*});
    fib.pause(1);

    while (true) {
        if (fib.dec("bar")) {
            break;
        }
        std.debug.print("[foo1] thread {}, paused!\n", .{thread});
        fib.pause(0);
    }

    std.debug.print("[foo2] thread {}, user_data {}\n", .{thread, user_data.*});
    fib.pause(1);

    std.debug.print("[foo3] thread {}, hello!\n", .{thread});
    fib.pause(0);

    std.debug.print("[foo4] thread {}, hello!\n", .{thread});

    fib.exit();
}

fn bar() void {
    const thread = fib.getThreadId();
    const user_data = fib.getUserData(Bar);

    std.debug.print("[bar0] thread {}, user_data {}\n", .{thread, user_data.*});

    while (true) {
        if (fib.dec("foo")) {
            break;
        }
        std.debug.print("[bar1] thread {}, paused!\n", .{thread});
        fib.pause(0);
    }
    
    fib.pause(1);

    while (true) {
        if (fib.dec("foo")) {
            break;
        }
        std.debug.print("[bar2] thread {}, paused!\n", .{thread});
        fib.pause(0);
    }
    
    std.debug.print("[bar3] thread {}, user_data {}\n", .{thread, user_data.*});
}

const Foo = struct {
    a: u64 = 0,
    b: u64 = 1,
    c: u64 = 2,
    d: u64 = 3,
};

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

    fib.push(.{ .name = "bar", .func = p_bar, .user_data = bar_user_data});
    fib.push(.{ .name = "foo", .func = p_foo, .user_data = foo_user_data});

    fib.start();

    std.debug.print("end main!\n", .{});
}

