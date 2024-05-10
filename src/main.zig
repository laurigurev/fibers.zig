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

    // const p_foo: usize = @intFromPtr(&foo);
    // const p_bar: usize = @intFromPtr(&bar);

    // const len: usize = fib.sizeof();

    // const MEM_COMMIT: u32 = 0x00001000;
    // const PAGE_EXECUTE_READWRITE: u32 = 0x40;
    // const ptr: *anyopaque = try std.os.windows.VirtualAlloc(null, len, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    // const mem: usize = @intFromPtr(ptr);

    // fib.init(mem);

    // const foo_user_data = fib.pack(Foo{});
    // const bar_user_data = fib.pack(Bar{});

    // fib.push(.{ .name = "foo", .func = p_foo, .user_data = foo_user_data});
    // fib.push(.{ .name = "bar", .func = p_bar, .user_data = bar_user_data});

    // while (fib.poll()) {
    //     fib.run();
    // }

    g_spinlock.init();

    _ = CreateThread(null, 0, &thread_entry, null, 0, null);
    _ = CreateThread(null, 0, &thread_entry, null, 0, null);

    std.debug.print("end main!\n", .{});

    while (true) {
        asm volatile("pause" ::);
    }
}

const builtin = @import("builtin");
const native_arch = builtin.cpu.arch;

const WINAPI: std.builtin.CallingConvention = if (native_arch == .x86) .Stdcall else .C;

// https://learn.microsoft.com/en-us/windows/win32/winprog/windows-data-types
const HANDLE = ?*anyopaque;
const SIZE_T = u64;
const LPVOID = ?*anyopaque;
const DWORD = u32;
const LPDWORD = ?*u32;

// https://learn.microsoft.com/en-us/previous-versions/windows/desktop/legacy/ms686736(v=vs.85)
const LPTHREAD_START_ROUTINE = *const fn (lpParameter: LPVOID) callconv(WINAPI) DWORD;

// https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createthread
extern "kernel32" fn CreateThread(
    lpThreadAttributes: ?*anyopaque,
    dwStackSize: SIZE_T,
    lpStartAddress: LPTHREAD_START_ROUTINE,
    lpParameter: LPVOID,
    dwCreationFlags: DWORD, 
    lpThreadId: LPDWORD
) callconv(WINAPI) HANDLE;

// https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getcurrentthreadid
extern "kernel32" fn GetCurrentThreadId() callconv(WINAPI) DWORD;

// https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-exitprocess
extern "kernel32" fn ExitProcess(uExitCode: c_uint) callconv(WINAPI) noreturn;

fn thread_entry(lpParameter: LPVOID) callconv(WINAPI) DWORD {
    _ = lpParameter;
    while (true) {
        if (g_spinlock.trylock()) {
            defer g_spinlock.unlock();

            if (g_counter < 10) {
                const thread_id: u32 = GetCurrentThreadId();
                std.debug.print("thread [{}] counter {}\n", .{thread_id, g_counter});
                g_counter += 1;
            }
            else {
                ExitProcess(0);
            }
        }
    }
}

var g_counter: u32 = 0;
var g_spinlock: Spinlock = .{};

// TODO: generic
const Spinlock = struct {
    const Self = @This();
    
    value: u32 = undefined,

    fn init(self: *Self) void {
        self.value = 0;
        @fence(.seq_cst);
    }

    // TODO: figure out what's the difference with cp_spinlock_fas_lock(...)
    // TODO: figure out what's the difference with cp_spinlock_fas_lock_eb(...)
    fn trylock(self: *Self) bool {
        @fence(.seq_cst);
        while (@cmpxchgWeak(u32, &self.value, 0, 1, .seq_cst, .seq_cst) != null) {
            asm volatile("pause" ::);
        }
        @fence(.seq_cst);
        return true;
    }

    fn unlock(self: *Self) void {
        @fence(.seq_cst);
        self.value = 0;
        @fence(.seq_cst);
    }
};

