// https://www.youtube.com/watch?v=HIVBhKj7gQU
// https://swedishcoding.com/wp-content/uploads/2015/03/parallelizing_the_naughty_dog_engine_using_fibers.pdf
// https://graphitemaster.github.io/fibers/
// https://www.youtube.com/watch?v=QZt9dQ-3B9U
// https://web.stanford.edu/class/archive/cs/cs107/cs107.1166/guide_x86-64.html
// https://wiki.cdot.senecapolytechnic.ca/wiki/X86_64_Register_and_Instruction_Quick_Start
// https://en.wikipedia.org/wiki/Function_prologue_and_epilogue
// https://andreaspk.github.io/posts/2019-02-16-Windows%20Calling%20Convention.html
// https://joeduffyblog.com/2006/06/17/tebs-and-stacks/
// https://en.wikipedia.org/wiki/Win32_Thread_Information_Block
// https://stackoverflow.com/questions/30725276/modifying-the-stack-on-windows-tib-and-exceptions

// TODO:
// - find out if you need to return from context switch
// - coroutine api and dataflow
// - scheduling implementation
// - multithreading (win32 threads or concurrency kit for primitives)
// - compile time checks for platforms and cpus

const std = @import("std");

const CONTEXT = std.os.windows.CONTEXT;
const WINAPI = std.os.windows.WINAPI;

pub extern "ntdll" fn RtlCaptureContext(ctx: *CONTEXT) callconv(WINAPI) void;
pub extern "ntdll" fn RtlRestoreContext(ctx: *CONTEXT, exception: ?*anyopaque) callconv(WINAPI) void;

fn ptrAdd(ptr: *anyopaque, a: usize) *anyopaque {
    var tmp: usize = @intFromPtr(ptr);
    tmp += a;
    return @ptrFromInt(tmp);
}

fn ptrSub(ptr: *anyopaque, a: usize) *anyopaque {
    var tmp: usize = @intFromPtr(ptr);
    tmp -= a;
    return @ptrFromInt(tmp);
}

pub const Context = packed struct {
    rip: ?*anyopaque = null,
    rsp: ?*anyopaque = null,
    
    rbx: ?*anyopaque = null,
    rbp: ?*anyopaque = null,
    r12: ?*anyopaque = null,
    r13: ?*anyopaque = null,
    r14: ?*anyopaque = null,
    r15: ?*anyopaque = null,
    rdi: ?*anyopaque = null,
    rsi: ?*anyopaque = null,

    xmm6: i128 = 0,
    xmm7: i128 = 0,
    xmm8: i128 = 0,
    xmm9: i128 = 0,
    xmm10: i128 = 0,
    xmm11: i128 = 0,
    xmm12: i128 = 0,
    xmm13: i128 = 0,
    xmm14: i128 = 0,
    xmm15: i128 = 0,
};

pub fn setContext(c: *Context) noreturn {
    var ctx: CONTEXT = undefined;
    RtlCaptureContext(&ctx);

    ctx.Rip = @intFromPtr(c.*.rip);
    ctx.Rsp = @intFromPtr(ptrSub(c.*.rsp.?, 8));
    
    // TODO: test out if this is super necessary
    const teb = std.os.windows.teb();
    teb.*.NtTib.StackBase = ptrSub(c.*.rsp.?, 8);
    teb.*.NtTib.StackLimit = ptrSub(c.*.rsp.?, 4096);
    
    RtlRestoreContext(&ctx, null);
     
    asm volatile (
        // save return address
        \\ movq 8*0(%[ptr]), %r8
            
        // load new satck pot
        \\ movq 8*1(%[ptr]), %rsp
            
        // load preserved registers
        \\ movq 8*2(%[ptr]), %rbx
        \\ movq 8*3(%[ptr]), %rbp
        \\ movq 8*4(%[ptr]), %r12
        \\ movq 8*5(%[ptr]), %r13
        \\ movq 8*6(%[ptr]), %r14
        \\ movq 8*7(%[ptr]), %r15
        \\ movq 8*8(%[ptr]), %rdi
        \\ movq 8*9(%[ptr]), %rsi
        \\ movups 8*10+16*0(%[ptr]), %xmm6
        \\ movups 8*10+16*1(%[ptr]), %xmm7
        \\ movups 8*10+16*2(%[ptr]), %xmm8
        \\ movups 8*10+16*3(%[ptr]), %xmm9
        \\ movups 8*10+16*4(%[ptr]), %xmm10
        \\ movups 8*10+16*5(%[ptr]), %xmm11
        \\ movups 8*10+16*6(%[ptr]), %xmm12
        \\ movups 8*10+16*7(%[ptr]), %xmm13
        \\ movups 8*10+16*8(%[ptr]), %xmm14
        \\ movups 8*10+16*9(%[ptr]), %xmm15

        // push rip to stack for return
        \\ pushq %r8
        \\ xor %eax, %eax
        \\ retq
            :
            :[ptr] "rdx" (c)
    );

    @trap();
}

