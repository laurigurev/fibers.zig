const std = @import("std");
const fib = @import("fibers.zig");

fn foo() void {
    // print_nt_tib();
    std.debug.print("hello fibers!\n", .{});

    // std.os.windows.kernel32.ExitProcess(0);
}

pub fn main() !void {
    std.debug.print("\n", .{});

    const len: usize = 16*1024;

    const MEM_COMMIT: u32 = 0x00001000;
    const PAGE_EXECUTE_READWRITE: u32 = 0x40;

    // const buf: [len]u8 = undefined;
    const ptr: *anyopaque = try std.os.windows.VirtualAlloc(null, len, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    var sp: usize = @intFromPtr(ptr) + len;
    std.debug.print("sp {}, sp%16={}\n", .{sp, sp%16});
    sp = sp & (std.math.maxInt(usize) - 15);
    std.debug.print("sp {}, sp%16={}\n", .{sp, sp%16});

    var c: fib.Context = .{};
    c.rip = @constCast(@ptrCast(&foo));
    c.rsp = @ptrFromInt(sp);
    // c.rbp = @ptrFromInt(sp);
    c.fiber_storage = 0;
    c.deallocation_stack = @intFromPtr(ptr);
    c.stack_limit = @intFromPtr(ptr);
    c.stack_base = sp;

    std.debug.print("c {any}\n", .{c});

    print_nt_tib();
    
    fib.setContext(&c);

    std.debug.print("hello main!\n", .{});
}

inline fn print_nt_tib() void {
    var fib_data: usize = 0;
    var dstk: usize = 0;
    var lim: usize = 0;
    var base: usize = 0;
    var gsb: usize = 0;

    asm volatile (
        // load new addresses into NT_TIB
        \\ movq %gs:(0x30), %r8
            
        // load fiber local storage
        \\ movq 0x20(%r8), %[fib]
            
        // load current deallocation stack
        \\ movq 0x1478(%r8), %[dstk]
            
        // load current stack limit
        \\ movq 0x10(%r8), %[lim]
            
        // load current stack base
        \\ movq 0x08(%r8), %[base]

        // load guaranteed stack bytes
        \\ movq 0x1748(%r8), %[gsb]
        : [fib] "={r9}" (fib_data),
          [dstk] "={r10}" (dstk),
          [lim] "={r11}" (lim),
          [base] "={rdx}" (base),
          [gsb] "={rcx}" (gsb)
    );

    std.debug.print("fiber data {}, deallocation stack {}, stack limit {}, stack base {}, guaranteed stack bytes {}\n",
        .{fib_data, dstk, lim, base, gsb});
}

