const std = @import("std");
const builtin = @import("builtin");
const native_arch = builtin.cpu.arch;

const TestInfo = struct {
    results: []u32 = undefined,
    threads: [4]u32 = [_]u32{ 0 } ** 4,
    visits: [4]u32 = [_]u32{ 0 } ** 4,
};

var g_counter: u32 = 0;
var g_spinlock: Spinlock = .{};

const TEST_SIZE: usize = 100000000;
// const TEST_SIZE: usize = 10;
const TEST_LEN: usize = 8;
pub fn run_tests() void {
    const len: usize = TEST_SIZE * @sizeOf(u32);
    
    const MEM_COMMIT: u32 = 0x00001000;
    const PAGE_EXECUTE_READWRITE: u32 = 0x40;
    const ptr: *anyopaque = std.os.windows.VirtualAlloc(null, len, MEM_COMMIT, PAGE_EXECUTE_READWRITE) catch unreachable;

    var results: []u32 = undefined;
    results.ptr = @ptrCast(@alignCast(ptr));
    results.len = TEST_SIZE;

    for (0..TEST_LEN) |i| {
        g_counter = 0;
        
        const info: TestInfo = .{ .results = results };
        
        var threads = [_]HANDLE{ null } ** 4;
        threads[0] = CreateThread(null, 0, &thread_entry_test, @constCast(@ptrCast(&info)), 0, null);
        threads[1] = CreateThread(null, 0, &thread_entry_test, @constCast(@ptrCast(&info)), 0, null);
        threads[2] = CreateThread(null, 0, &thread_entry_test, @constCast(@ptrCast(&info)), 0, null);
        threads[3] = CreateThread(null, 0, &thread_entry_test, @constCast(@ptrCast(&info)), 0, null);
        
        _ = WaitForMultipleObjects(threads.len, &threads[0], 1, INFINITE); 
        
        var errors: u32 = 0;
        for (0..TEST_SIZE) |j| {
            if (info.results[j] != j) {
                errors += 1;
            }
            info.results[j] = 0;
        }

        std.debug.print("[test {}] total size {}, errors {}\n", .{i, TEST_SIZE, errors});
        for (info.threads, info.visits) |t, v| {
            std.debug.print("    [thread {}] visits {}\n", .{t, v});
        }
    }
}
fn thread_entry_test(lpParameter: LPVOID) callconv(WINAPI) DWORD {
    if (lpParameter == null) {
        return 1;
    }
    
    const info: *TestInfo = @alignCast(@ptrCast(lpParameter));
    
    outer: while (true) {
        g_spinlock.lock();
        defer g_spinlock.unlock();
        
        if (g_counter < TEST_SIZE) {
            const idx: u32 = g_counter;
            info.*.results[idx] = g_counter;
            
            const thread_id: u32 = GetCurrentThreadId();
            // std.debug.print("thread [{}] counter {}\n", .{thread_id, g_counter});
            
            g_counter += 1;

            for (info.*.threads, 0..) |t, i| {
                if (t == thread_id) {
                    info.*.visits[i] += 1;
                    continue :outer;
                }
            }
            
            for (info.*.threads, 0..) |t, i| {
                if (t == 0) {
                    info.*.threads[i] = thread_id;
                    info.*.visits[i] += 1;
                    break;
                }
            }
        }
        else {
            break;
        }
    }
    
    return 0;
}

const WINAPI: std.builtin.CallingConvention = if (native_arch == .x86) .Stdcall else .C;

// https://learn.microsoft.com/en-us/windows/win32/winprog/windows-data-types
const HANDLE = ?*anyopaque;
const SIZE_T = u64;
const LPVOID = ?*anyopaque;
const DWORD = u32;
const LPDWORD = ?*u32;
const BOOL = i32;
const INFINITE: u32 = 0xffffffff;

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

// https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitformultipleobjects
extern "kernel32" fn WaitForMultipleObjects(
  nCount: DWORD,
  lpHandles: *const HANDLE,
  bWaitAll: BOOL,
  dwMilliseconds: DWORD
) callconv(WINAPI) DWORD;

extern "kernel32" fn SwitchToThread() callconv(WINAPI) BOOL;

extern "kernel32" fn Sleep(dwMilliseconds: DWORD) callconv(WINAPI) void;

const Spinlock = struct {
    const Self = @This();
    
    value: u32 = undefined,

    fn init(self: *Self) void {
        self.value = 0;
    }
    fn lock(self: *Self) void {
        const EXPONENTIAL_BACKOFF_MIN: u32 = 4;
        const EXPONENTIAL_BACKOFF_MAX: u32 = 1024;
        
        var backoff: u32 = EXPONENTIAL_BACKOFF_MIN;
        while (@cmpxchgWeak(u32, &self.value, 0, 1, .seq_cst, .seq_cst) != null) {
            for (0..backoff) |_| {
            }
            backoff = @min(backoff << 1, EXPONENTIAL_BACKOFF_MAX);
        }
    }
    fn unlock(self: *Self) void {
        self.value = 0;
    }
};

