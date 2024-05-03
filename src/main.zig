const std = @import("std");
const fib = @import("fibers.zig");

fn foo() noreturn {
    const teb = std.os.windows.teb();
    std.debug.print("stackbase {}, stacklimit {}\n", .{teb.*.NtTib.StackBase, teb.*.NtTib.StackLimit});

    std.debug.print("hello fibers!\n", .{});
    std.os.windows.kernel32.ExitProcess(0);
}

pub fn main() !void {
    std.debug.print("\n", .{});

    const len: usize = 4096;

    const MEM_COMMIT: u32 = 0x00001000;
    const PAGE_EXECUTE_READWRITE: u32 = 0x40;

    // const buf: [len]u8 = undefined;
    const ptr: *anyopaque = try std.os.windows.VirtualAlloc(null, len, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    var sp: usize = @intFromPtr(ptr) + len;
    sp = sp & (std.math.maxInt(usize) - 15);

    // const rsp: ?*anyopaque = @ptrFromInt(sp);
    // std.debug.print("sp {}, rsp {?}\n", .{sp, rsp});
    // const _sp = sp & (std.math.maxInt(usize) - 15);

    // rsp = @ptrFromInt(_sp);
    // std.debug.print("sp {}, rsp {?}\n", .{_sp, rsp});

    // sp -= 128;

    std.debug.print("sp {}\n", .{sp});
    // std.debug.print("sp {}\n", .{sp});

    var c: fib.Context = .{};
    c.rip = @constCast(@ptrCast(&foo));
    c.rsp = @ptrFromInt(sp);
    c.xmm7 = 0x10;

    std.debug.print("c {any}\n", .{c});
    std.debug.print("&foo() {}\n", .{&foo});
    std.debug.print("&buf {any}\n", .{ptr});

    // const tmp = std.os.windows.peb();
    // _ = tmp;

    const teb = std.os.windows.teb();
    std.debug.print("stackbase {}, stacklimit {}\n",
        .{teb.*.NtTib.StackBase, teb.*.NtTib.StackLimit});
    std.debug.print("stackbase {}, stacklimit {}\n",
        .{@intFromPtr(teb.*.NtTib.StackBase), @intFromPtr(teb.*.NtTib.StackLimit)});

    fib.setContext(&c);

    // var ctx: std.os.windows.CONTEXT = undefined;
    // std.os.windows.ntdll.RtlCaptureContext(&ctx);
    // std.debug.print("context {}\n", .{ctx});
}
