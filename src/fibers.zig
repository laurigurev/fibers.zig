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
// https://stackoverflow.com/questions/71259613/c-fibers-crashing-on-printf
// https://github.com/boostorg/context
// https://medium.com/@sruthk/cracking-assembly-introduction-to-assembly-language-a4ad14e601a1

// TODO:
// - coroutine api and dataflow
// - scheduling implementation
// - multithreading (win32 threads or concurrency kit for primitives)
// - compile time checks for platforms and cpus

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

    // NT_TIB stuff
    fiber_storage: usize = 0,
    deallocation_stack: usize = 0,
    stack_limit: usize = 0,
    stack_base: usize = 0,
};

comptime {
    staticAssert(@offsetOf(Context, "fiber_storage") == 8*30);
    staticAssert(@offsetOf(Context, "deallocation_stack") == 8*31);
    staticAssert(@offsetOf(Context, "stack_limit") == 8*32);
    staticAssert(@offsetOf(Context, "stack_base") == 8*33);
}

fn staticAssert(comptime x: bool) void {
    if (!x) {
        @compileError("static assert failed!");
    }
}

pub fn setContext(c: *Context) void {
    var current: Context = .{};
    
    asm volatile (
        // load new addresses into NT_TIB
        \\ movq  %gs:(0x30), %r10
        
        
            
        // restore fiber local storage
        \\ movq  0x20(%r10), %rax
        \\ movq  %rax, 8*30(%[src])
         
        // restore current deallocation stack
        \\ movq  0x1478(%r10), %rax
        \\ movq  %rax, 8*31(%[src])
         
        // restore current stack limit
        \\ movq  0x10(%r10), %rax
        \\ movq  %rax, 8*32(%[src])
         
        // restore current stack base
        \\ movq  0x08(%r10), %rax
        \\ movq  %rax, 8*33(%[src])
        
        // load new stack pointer
        \\ movq %rsp, 8*1(%[src])
         
        // load preserved registers
        \\ movq %rbx, 8*2(%[src])
        \\ movq %rbp, 8*3(%[src])
        \\ movq %r12, 8*4(%[src])
        \\ movq %r13, 8*5(%[src])
        \\ movq %r14, 8*6(%[src])
        \\ movq %r15, 8*7(%[src])
        \\ movq %rdi, 8*8(%[src])
        \\ movq %rsi, 8*9(%[src])
        \\ movups %xmm6, 8*10+16*0(%[src])
        \\ movups %xmm7, 8*10+16*1(%[src])
        \\ movups %xmm8, 8*10+16*2(%[src])
        \\ movups %xmm9, 8*10+16*3(%[src])
        \\ movups %xmm10, 8*10+16*4(%[src])
        \\ movups %xmm11, 8*10+16*5(%[src])
        \\ movups %xmm12, 8*10+16*6(%[src])
        \\ movups %xmm13, 8*10+16*7(%[src])
        \\ movups %xmm14, 8*10+16*8(%[src])
        \\ movups %xmm15, 8*10+16*9(%[src])
        
        
         
        // restore fiber local storage
        \\ movq  8*30(%[dst]), %rax
        \\ movq  %rax, 0x20(%r10)
         
        // restore current deallocation stack
        \\ movq  8*31(%[dst]), %rax
        \\ movq  %rax, 0x1478(%r10)
         
        // restore current stack limit
        \\ movq  8*32(%[dst]), %rax
        \\ movq  %rax, 0x10(%r10)
         
        // restore current stack base
        \\ movq  8*33(%[dst]), %rax
        \\ movq  %rax, 0x08(%r10)
        
        // save return address
        \\ movq 8*0(%[dst]), %r11
         
        // load new stack pointer
        \\ movq 8*1(%[dst]), %rsp
         
        // load preserved registers
        \\ movq 8*2(%[dst]), %rbx
        \\ movq 8*3(%[dst]), %rbp
        \\ movq 8*4(%[dst]), %r12
        \\ movq 8*5(%[dst]), %r13
        \\ movq 8*6(%[dst]), %r14
        \\ movq 8*7(%[dst]), %r15
        \\ movq 8*8(%[dst]), %rdi
        \\ movq 8*9(%[dst]), %rsi
        \\ movups 8*10+16*0(%[dst]), %xmm6
        \\ movups 8*10+16*1(%[dst]), %xmm7
        \\ movups 8*10+16*2(%[dst]), %xmm8
        \\ movups 8*10+16*3(%[dst]), %xmm9
        \\ movups 8*10+16*4(%[dst]), %xmm10
        \\ movups 8*10+16*5(%[dst]), %xmm11
        \\ movups 8*10+16*6(%[dst]), %xmm12
        \\ movups 8*10+16*7(%[dst]), %xmm13
        \\ movups 8*10+16*8(%[dst]), %xmm14
        \\ movups 8*10+16*9(%[dst]), %xmm15
        
        // since jump is going to push rbp,
        // make sure rsp is 16 byte aligned
        // \\ leaq -8*1(%rsp), %rsp
        // jump to new rip
        // \\ jmpq *%r11
        // other possibility is to use retq or callq
        \\ pushq %[src]
        \\ pushq %[src]
        \\ callq *%r11
        \\ popq %[src]
        \\ popq %[src]
        
        
        
        \\ movq  %gs:(0x30), %r10
        
        \\ movq  8*30(%[src]), %rax
        \\ movq  %rax, 0x20(%r10)
         
        // restore current deallocation stack
        \\ movq  8*31(%[src]), %rax
        \\ movq  %rax, 0x1478(%r10)
         
        // restore current stack limit
        \\ movq  8*32(%[src]), %rax
        \\ movq  %rax, 0x10(%r10)
         
        // restore current stack base
        \\ movq  8*33(%[src]), %rax
        \\ movq  %rax, 0x08(%r10)
        
        // load new stack pointer
        \\ movq 8*1(%[src]), %rsp
         
        // load preserved registers
        \\ movq 8*2(%[src]), %rbx
        \\ movq 8*3(%[src]), %rbp
        \\ movq 8*4(%[src]), %r12
        \\ movq 8*5(%[src]), %r13
        \\ movq 8*6(%[src]), %r14
        \\ movq 8*7(%[src]), %r15
        \\ movq 8*8(%[src]), %rdi
        \\ movq 8*9(%[src]), %rsi
        \\ movups 8*10+16*0(%[src]), %xmm6
        \\ movups 8*10+16*1(%[src]), %xmm7
        \\ movups 8*10+16*2(%[src]), %xmm8
        \\ movups 8*10+16*3(%[src]), %xmm9
        \\ movups 8*10+16*4(%[src]), %xmm10
        \\ movups 8*10+16*5(%[src]), %xmm11
        \\ movups 8*10+16*6(%[src]), %xmm12
        \\ movups 8*10+16*7(%[src]), %xmm13
        \\ movups 8*10+16*8(%[src]), %xmm14
        \\ movups 8*10+16*9(%[src]), %xmm15
            :
            :[dst] "{rcx}" (c),
             [src] "{rdx}" (&current),
            : "rax", "r10", "r11"
    );
}
