//      FIBER'S STACK
//   
//   |-----------------| <- low addr
//   | - - - - - - - - |
//   | - - - - - - - - |
//   | - - - - - - - - |
//   | - - - - - - - - |
//   | - - - - - - - - |
//   | - - - - - - - - |
//   | - - - - - - - - |
//   | - - - - - - - - |
//   | - return addr - |
//   | - - old ctx - - |
//   |-----------------| <- high addr
//   

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
// https://sonictk.github.io/asm_tutorial/#beatingthecompiler
// https://stackoverflow.com/questions/57212012/how-to-load-address-of-function-or-label-into-register

// TODO:
// - scheduling implementation
// - multithreading (win32 threads or concurrency kit for primitives)
// - compile time checks for platforms and cpus
// - checks for stack and memory alignment
// - measure cycles
// - add support for custom data
// - allocator
// - wait list control integer

fn RingBuffer(comptime T: type, comptime len: usize) type {
	return struct {
		const Self = @This();
		
		start: usize = 0,
		end: usize = 0,
		num: usize = 0,
		data: [len]T = undefined,

		fn push(self: *Self, t: T) void {
			if (self.num == len) {
				@panic("RingArray does not have anywhere to push!");
			}
			
			self.data[self.end] = t;
			self.num += 1;
			self.end += 1;
			if (self.end == len) {
				self.end = 0;
			}
		}

		fn pop(self: *Self) T {
			if (self.num == 0) {
				@panic("RingArray does not have anything to pop!");
			}
			const tmp = self.data[self.start];
			self.num -= 1;
			self.start += 1;
			if (self.start == len) {
				self.start = 0;
			}
			return tmp;
		}
		
		fn pop_silent(self: *Self) *T {
			if (self.num == 0) {
				@panic("RingArray does not have anything to pop!");
			}
			const tmp = &self.data[self.start];
			self.num -= 1;
			self.start += 1;
			if (self.start == len) {
				self.start = 0;
			}
			return tmp;
		}

		fn last(self: *Self) *T {
			if (self.num == 0) {
				@panic("RingArray is empty!");
			}
			return &self.data[self.end - 1];
		}
	};
}

pub const Info = struct {
	func: usize,
	mem: usize,
	size: usize,
};

pub const Context = packed struct {
    rip: u64 = 0,
    rsp: u64 = 0,
    
    rbx: u64 = 0,
    rbp: u64 = 0,
    r12: u64 = 0,
    r13: u64 = 0,
    r14: u64 = 0,
    r15: u64 = 0,
    rdi: u64 = 0,
    rsi: u64 = 0,

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
    fiber_storage: u64 = 0,
    deallocation_stack: u64 = 0,
    stack_limit: u64 = 0,
    stack_base: u64 = 0,
};

var fibers: RingBuffer(Info, 128) = .{};
var wait_list: RingBuffer(Context, 16) = .{};

pub fn poll() bool {
	if (fibers.num != 0 or wait_list.num != 0) {
		return true;
	}
	return false;
}

pub fn run() void {
	if (wait_list.num != 0) {
		cont();
	}
	else {
		pop();
	}
}

pub fn push(info: Info) void {
	// TODO: check size is more than 2xcontext size
	fibers.push(info);
}

fn pop() void {
	const info: Info = fibers.pop();
	
	var new: Context = .{};
	new.rip = info.func;
	new.rsp = info.mem + info.size - @sizeOf(Context);
    new.fiber_storage = 0;
    new.deallocation_stack = info.mem;
    new.stack_limit = info.mem;
    new.stack_base = info.mem + info.size;

	// saving current context at the bottom of the stack
	asm volatile (
			// instruction pointer is not needed because we
			// return using RETQ
        	// \\ movq %rip, 8*0(%[stack])
		
			// saving registers
        	\\ movq %rsp, 8*1(%[stack])
        	\\ movq %rbx, 8*2(%[stack])
        	\\ movq %rbp, 8*3(%[stack])
        	\\ movq %r12, 8*4(%[stack])
        	\\ movq %r13, 8*5(%[stack])
        	\\ movq %r14, 8*6(%[stack])
        	\\ movq %r15, 8*7(%[stack])
        	\\ movq %rdi, 8*8(%[stack])
        	\\ movq %rsi, 8*9(%[stack])
			
        	\\ movups %xmm6,  8*10(%[stack])
        	\\ movups %xmm7,  8*12(%[stack])
        	\\ movups %xmm8,  8*14(%[stack])
        	\\ movups %xmm9,  8*16(%[stack])
        	\\ movups %xmm10, 8*18(%[stack])
        	\\ movups %xmm11, 8*20(%[stack])
        	\\ movups %xmm12, 8*22(%[stack])
        	\\ movups %xmm13, 8*24(%[stack])
        	\\ movups %xmm14, 8*26(%[stack])
        	\\ movups %xmm15, 8*28(%[stack])
			
			// saving TIB data
        	\\ movq %gs:(0x30), %r10
			
        	\\ movq 0x20(%r10), %rax
        	\\ movq %rax, 8*30(%[stack])
        	\\ movq 0x1478(%r10), %rax
        	\\ movq %rax, 8*31(%[stack])
        	\\ movq 0x10(%r10), %rax
        	\\ movq %rax, 8*32(%[stack])
        	\\ movq 0x08(%r10), %rax
        	\\ movq %rax, 8*33(%[stack])
			:
			:[stack] "{rcx}" (new.rsp)
	);

	asm volatile (
			// loading newly created context
        	\\ movq 8*0(%[dst]), %rdx
        	\\ movq 8*1(%[dst]), %rsp
        	\\ movq 8*2(%[dst]), %rbx
        	\\ movq 8*3(%[dst]), %rbp
        	\\ movq 8*4(%[dst]), %r12
        	\\ movq 8*5(%[dst]), %r13
        	\\ movq 8*6(%[dst]), %r14
        	\\ movq 8*7(%[dst]), %r15
        	\\ movq 8*8(%[dst]), %rdi
        	\\ movq 8*9(%[dst]), %rsi
			
        	\\ movups 8*10(%[dst]), %xmm6
        	\\ movups 8*12(%[dst]), %xmm7
        	\\ movups 8*14(%[dst]), %xmm8
        	\\ movups 8*16(%[dst]), %xmm9
        	\\ movups 8*18(%[dst]), %xmm10
        	\\ movups 8*20(%[dst]), %xmm11
        	\\ movups 8*22(%[dst]), %xmm12
        	\\ movups 8*24(%[dst]), %xmm13
        	\\ movups 8*26(%[dst]), %xmm14
        	\\ movups 8*28(%[dst]), %xmm15
			
			// loading new TIB stuff
        	\\ movq %gs:(0x30), %r10
			
        	\\ movq 8*30(%[dst]), %rax
        	\\ movq %rax, 0x20(%r10)
        	\\ movq 8*31(%[dst]), %rax
        	\\ movq %rax, 0x1478(%r10)
        	\\ movq 8*32(%[dst]), %rax
        	\\ movq %rax, 0x10(%r10)
        	\\ movq 8*33(%[dst]), %rax
        	\\ movq %rax, 0x08(%r10)
			
        	\\ callq *%rdx
			:
			:[dst] "{rcx}" (&new)
	);

	asm volatile (
			// retrieving old context that was saved
			// at the bottom of the stack
        	\\ movq %gs:(0x30), %r10
        	\\ movq 0x08(%r10), %rax
			\\ leaq -8*34(%rax), %rcx

			// getting instruction pointer is not 
			// necessary
        	// \\ movq 8*0(%[dst]), %rdx

			// retrieving old registers
        	\\ movq 8*1(%rcx), %rsp
        	\\ movq 8*2(%rcx), %rbx
        	\\ movq 8*3(%rcx), %rbp
        	\\ movq 8*4(%rcx), %r12
        	\\ movq 8*5(%rcx), %r13
        	\\ movq 8*6(%rcx), %r14
        	\\ movq 8*7(%rcx), %r15
        	\\ movq 8*8(%rcx), %rdi
        	\\ movq 8*9(%rcx), %rsi
			
        	\\ movups 8*10(%rcx), %xmm6
        	\\ movups 8*12(%rcx), %xmm7
        	\\ movups 8*14(%rcx), %xmm8
        	\\ movups 8*16(%rcx), %xmm9
        	\\ movups 8*18(%rcx), %xmm10
        	\\ movups 8*20(%rcx), %xmm11
        	\\ movups 8*22(%rcx), %xmm12
        	\\ movups 8*24(%rcx), %xmm13
        	\\ movups 8*26(%rcx), %xmm14
        	\\ movups 8*28(%rcx), %xmm15
			
			// retrieving old TIB data
        	\\ movq  8*30(%rcx), %rax
        	\\ movq  %rax, 0x20(%r10)
        	\\ movq  8*31(%rcx), %rax
        	\\ movq  %rax, 0x1478(%r10)
        	\\ movq  8*32(%rcx), %rax
        	\\ movq  %rax, 0x10(%r10)
        	\\ movq  8*33(%rcx), %rax
        	\\ movq  %rax, 0x08(%r10)
			:
			:
	);
}

pub fn pause() void {
	wait_list.push(.{});
	const ctx = wait_list.last();
	
	// creating new context to return to
	asm volatile (
			// saving label as return point since
			// we want to use RETQ
        	\\ leaq CONTINUE0(%rip), %rax
        	\\ movq %rax, 8*0(%[ctx])
			
        	\\ movq %rsp, 8*1(%[ctx])
        	\\ movq %rbx, 8*2(%[ctx])
        	\\ movq %rbp, 8*3(%[ctx])
        	\\ movq %r12, 8*4(%[ctx])
        	\\ movq %r13, 8*5(%[ctx])
        	\\ movq %r14, 8*6(%[ctx])
        	\\ movq %r15, 8*7(%[ctx])
        	\\ movq %rdi, 8*8(%[ctx])
        	\\ movq %rsi, 8*9(%[ctx])
			
        	\\ movups %xmm6,  8*10(%[ctx])
        	\\ movups %xmm7,  8*12(%[ctx])
        	\\ movups %xmm8,  8*14(%[ctx])
        	\\ movups %xmm9,  8*16(%[ctx])
        	\\ movups %xmm10, 8*18(%[ctx])
        	\\ movups %xmm11, 8*20(%[ctx])
        	\\ movups %xmm12, 8*22(%[ctx])
        	\\ movups %xmm13, 8*24(%[ctx])
        	\\ movups %xmm14, 8*26(%[ctx])
        	\\ movups %xmm15, 8*28(%[ctx])
			
        	\\ movq %gs:(0x30), %r10
			
        	\\ movq 0x20(%r10), %rax
        	\\ movq %rax, 8*30(%[ctx])
        	\\ movq 0x1478(%r10), %rax
        	\\ movq %rax, 8*31(%[ctx])
        	\\ movq 0x10(%r10), %rax
        	\\ movq %rax, 8*32(%[ctx])
        	\\ movq 0x08(%r10), %rax
        	\\ movq %rax, 8*33(%[ctx])

			// return address can be found in the stack
			\\ leaq -8*34(%rax), %rdx
			\\ leaq -8*1(%rdx), %rsp
			\\ retq
			
			\\ CONTINUE0:
			:
			:[ctx] "{rcx}" (ctx)
	);
}

const std = @import("std");

fn cont() void {
	const ctx: *Context = wait_list.pop_silent();
	
	// saving current context and overriding old context
	asm volatile (
			// No need to save instruction pointer since we
			// use RETQ
        	// \\ leaq CONTINUE1(%rip), %rax
        	// \\ movq %rax, 8*0(%[stack])
			
			// saving registers
        	\\ movq %rsp, 8*1(%[stack])
        	\\ movq %rbx, 8*2(%[stack])
        	\\ movq %rbp, 8*3(%[stack])
        	\\ movq %r12, 8*4(%[stack])
        	\\ movq %r13, 8*5(%[stack])
        	\\ movq %r14, 8*6(%[stack])
        	\\ movq %r15, 8*7(%[stack])
        	\\ movq %rdi, 8*8(%[stack])
        	\\ movq %rsi, 8*9(%[stack])
			
        	\\ movups %xmm6,  8*10(%[stack])
        	\\ movups %xmm7,  8*12(%[stack])
        	\\ movups %xmm8,  8*14(%[stack])
        	\\ movups %xmm9,  8*16(%[stack])
        	\\ movups %xmm10, 8*18(%[stack])
        	\\ movups %xmm11, 8*20(%[stack])
        	\\ movups %xmm12, 8*22(%[stack])
        	\\ movups %xmm13, 8*24(%[stack])
        	\\ movups %xmm14, 8*26(%[stack])
        	\\ movups %xmm15, 8*28(%[stack])
			
			// saving TIB data
        	\\ movq %gs:(0x30), %r10
			
        	\\ movq 0x20(%r10), %rax
        	\\ movq %rax, 8*30(%[stack])
        	\\ movq 0x1478(%r10), %rax
        	\\ movq %rax, 8*31(%[stack])
        	\\ movq 0x10(%r10), %rax
        	\\ movq %rax, 8*32(%[stack])
        	\\ movq 0x08(%r10), %rax
        	\\ movq %rax, 8*33(%[stack])

			// replacing bottom most return address in the stack
			\\ leaq -8*1(%[stack]), %rax
        	\\ leaq CONTINUE1(%rip), %rdx
			\\ movq %rdx, (%rax)
			:
			:[stack] "{rcx}" (ctx.stack_base - @sizeOf(Context))
	);

	// restoring context from the wait list
	asm volatile (
			// restoring registers
        	\\ movq 8*0(%[ctx]), %rdx
        	\\ movq 8*1(%[ctx]), %rsp
        	\\ movq 8*2(%[ctx]), %rbx
        	\\ movq 8*3(%[ctx]), %rbp
        	\\ movq 8*4(%[ctx]), %r12
        	\\ movq 8*5(%[ctx]), %r13
        	\\ movq 8*6(%[ctx]), %r14
        	\\ movq 8*7(%[ctx]), %r15
        	\\ movq 8*8(%[ctx]), %rdi
        	\\ movq 8*9(%[ctx]), %rsi
			
        	\\ movups 8*10(%[ctx]), %xmm6
        	\\ movups 8*12(%[ctx]), %xmm7
        	\\ movups 8*14(%[ctx]), %xmm8
        	\\ movups 8*16(%[ctx]), %xmm9
        	\\ movups 8*18(%[ctx]), %xmm10
        	\\ movups 8*20(%[ctx]), %xmm11
        	\\ movups 8*22(%[ctx]), %xmm12
        	\\ movups 8*24(%[ctx]), %xmm13
        	\\ movups 8*26(%[ctx]), %xmm14
        	\\ movups 8*28(%[ctx]), %xmm15
			
			// restoring TIB data
        	\\ movq %gs:(0x30), %r10
			
        	\\ movq 8*30(%[ctx]), %rax
        	\\ movq %rax, 0x20(%r10)
        	\\ movq 8*31(%[ctx]), %rax
        	\\ movq %rax, 0x1478(%r10)
        	\\ movq 8*32(%[ctx]), %rax
        	\\ movq %rax, 0x10(%r10)
        	\\ movq 8*33(%[ctx]), %rax
        	\\ movq %rax, 0x08(%r10)
			
			// DONT'T use RETQ since we don't want to disturb
			// the current %RSP and we have replaced return 
			// address in previous asm block
        	\\ jmpq *%rdx
			:
			:[ctx] "{rcx}" (ctx)
	);

	// restoring this context
	asm volatile (
			// a label where context returns to
			\\ CONTINUE1:
			
			// retrieving context from the stack
        	\\ movq %gs:(0x30), %r10
        	\\ movq 0x08(%r10), %rax
			\\ leaq -8*34(%rax), %rcx
			
			// no need to replace instruction pointer
        	// \\ movq 8*0(%[dst]), %rdx

			// restoring registers
        	\\ movq 8*1(%rcx), %rsp
        	\\ movq 8*2(%rcx), %rbx
        	\\ movq 8*3(%rcx), %rbp
        	\\ movq 8*4(%rcx), %r12
        	\\ movq 8*5(%rcx), %r13
        	\\ movq 8*6(%rcx), %r14
        	\\ movq 8*7(%rcx), %r15
        	\\ movq 8*8(%rcx), %rdi
        	\\ movq 8*9(%rcx), %rsi
			
        	\\ movups 8*10(%rcx), %xmm6
        	\\ movups 8*12(%rcx), %xmm7
        	\\ movups 8*14(%rcx), %xmm8
        	\\ movups 8*16(%rcx), %xmm9
        	\\ movups 8*18(%rcx), %xmm10
        	\\ movups 8*20(%rcx), %xmm11
        	\\ movups 8*22(%rcx), %xmm12
        	\\ movups 8*24(%rcx), %xmm13
        	\\ movups 8*26(%rcx), %xmm14
        	\\ movups 8*28(%rcx), %xmm15
			
			// restoring TIB data
        	\\ movq  8*30(%rcx), %rax
        	\\ movq  %rax, 0x20(%r10)
        	\\ movq  8*31(%rcx), %rax
        	\\ movq  %rax, 0x1478(%r10)
        	\\ movq  8*32(%rcx), %rax
        	\\ movq  %rax, 0x10(%r10)
        	\\ movq  8*33(%rcx), %rax
        	\\ movq  %rax, 0x08(%r10)
			:
			:
	);
}

fn staticAssert(comptime x: bool) void {
    if (!x) {
        @compileError("static assert failed!");
    }
}

comptime {
	// TODO: test other offsets, cpu arch and os
	staticAssert(@sizeOf(Context) == 8*34);
}

