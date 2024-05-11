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
//   | - return addr - | <- rsp
//   | - - old ctx - - |
//   | -  user data  - |
//   | - - header  - - |
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
// https://dev.to/kprotty/understanding-atomics-and-memory-ordering-2mom
// https://learn.microsoft.com/en-us/windows/win32/Sync/slim-reader-writer--srw--locks
// https://gist.github.com/cabarger/d3879745b8477670070f826cad2f027d?permalink_comment_id=4816454
// https://web.archive.org/web/20221127015901/http://concurrencykit.org/doc/ck_spinlock.html
// https://en.cppreference.com/w/cpp/atomic/memory_order
// https://llvm.org/docs/Atomics.html
// https://stackoverflow.com/questions/12346487/what-do-each-memory-order-mean
// https://www.youtube.com/watch?v=AN6XHy2znzc&list=PLxNPSjHT5qvsZyes3ATYvhPhwkoY33L2v
// https://geidav.wordpress.com/2016/03/12/important-properties-of-spinlocks/
// https://geidav.wordpress.com/tag/exponential-back-off/
// https://en.wikipedia.org/wiki/Exponential_backoff
// https://github.com/CoffeeBeforeArch/spinlocks/tree/main
// https://www.cs.utexas.edu/~bornholt/post/memory-models.html
// https://stackoverflow.com/questions/32705169/does-the-intel-memory-model-make-sfence-and-lfence-redundant
// https://preshing.com/20120515/memory-reordering-caught-in-the-act/
// https://preshing.com/20120625/memory-ordering-at-compile-time/
// https://en.wikipedia.org/wiki/Memory_ordering
// https://peeterjoot.wordpress.com/2009/12/04/intel-memory-ordering-fence-instructions-and-atomic-operations/

// TODO:
// - compile time checks for platforms and cpus
// - checks for stack and memory alignment
// - measure cycles
// - comment everything

const std = @import("std");
const builtin = @import("builtin");
const native_arch = builtin.cpu.arch;

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

fn RingBuffer(comptime T: type, comptime len: usize) type {
	return struct {
		const Self = @This();
		
		spinlock: Spinlock = .{},
		start: usize = 0,
		end: usize = 0,
		num: usize = 0,
		data: [len]T = undefined,

		fn init(self: *Self) void {
			self.spinlock.init();
		}

		fn push(self: *Self, t: T) void {
			self.spinlock.lock();
			defer self.spinlock.unlock();
			
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
			self.spinlock.lock();
			defer self.spinlock.unlock();
			
			if (self.num == 0) {
				return .{ .name = undefined, .func = 0, .user_data = 0 };
			}
			const tmp = self.data[self.start];
			self.num -= 1;
			self.start += 1;
			if (self.start == len) {
				self.start = 0;
			}
			return tmp;
		}
	};
}

const Allocator = struct {
	const Self = @This();
	
	spinlock: Spinlock = .{},
	status: u64 = 0,
	mem: usize = 0,

	fn init(self: *Self) void {
		self.spinlock.init();
	}
	
	fn alloc(self: *Self) usize {
		self.spinlock.lock();
		defer self.spinlock.unlock();
		
		const one: usize = 1;
		for (0..64) |i| {
			const a: u64 = @shlExact(one, @intCast(i));

			if ((self.status & a) == 0) {
				self.status = self.status | a;
				return self.mem + i * STACK_SIZE;
			}
		}
		return 0;
	}

	fn free(self: *Self, mem: usize) void {
		self.spinlock.lock();
		defer self.spinlock.unlock();
		
		const one: usize = 1;
		
		const a: usize = mem - self.mem;
		const b: usize = a / STACK_SIZE;
		const c: usize = @shlExact(one, @intCast(b));
		self.status &= ~c;
	}
};

const WaitList = struct {
	const Self = @This();
	
	spinlock: Spinlock = .{},
	keys: [WAIT_LIST_SIZE]u64 = [_]u64{ 0 } ** WAIT_LIST_SIZE,
	thread_ids: [WAIT_LIST_SIZE]u64 = [_]u64{ 0 } ** WAIT_LIST_SIZE,
	vals: [WAIT_LIST_SIZE]u32 = undefined,
	ctxs: [WAIT_LIST_SIZE]Context = undefined,
	
	fn init(self: *Self) void {
		self.spinlock.init();
	}
	
	// does not use spinlock!
	fn reserve_unsafe(self: *Self, key: u64) usize {
		for (self.keys, 0..) |k, i| {
			if (k == 0) {
				self.keys[i] = key;
				self.thread_ids[i] = 0;
				self.vals[i] = 0;
				return i;
			}
		}
		return WAIT_LIST_SIZE;
	}

	// searches for context with mathching key irrespective of other values
	fn search(self: *Self, key: u64) usize {
		self.spinlock.lock();
		defer self.spinlock.unlock();
		
		for (self.keys, 0..) |k, i| {
			if (key == k) {
				return i;
			}
		}
		return WAIT_LIST_SIZE;
	}
	
	// searches for valid context with zero value using thread id
	fn find_with_thread(self: *Self, thread_id: u64) usize {
		self.spinlock.lock();
		defer self.spinlock.unlock();
		
		for (self.keys, self.thread_ids, self.vals, 0..) |k, t, v, i| {
			if (k != 0 and t == thread_id and v == 0) {
				return i;
			}
		}
		return WAIT_LIST_SIZE;
	}

	// removes context if value is zero
	fn remove_at_zero(self: *Self, idx: usize) bool {
		self.spinlock.lock();
		defer self.spinlock.unlock();
		
		assert(self.keys[idx] != 0);
		if (self.vals[idx] == 0) {
			self.keys[idx] = 0;
			self.thread_ids[idx] = 0;
			self.vals[idx] = 0;
			return true;
		}
		return false;
	}
};

pub const Info = struct {
	const Self = @This();
	
	name: []const u8,
	func: u64,
	user_data: u256,

	fn is_valid(self: *const Self) bool {
		if (self.func == 0) {
			return false;
		}
		return true;
	}
};

const Context = packed struct {
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

const Header = packed struct {
	key: u64 = 0,
	p_user_data: u64 = 0,
	p_context: u64 = 0,
	thread_id: u64 = 0,
};

const STACK_SIZE: usize = 16*1024;
const WAIT_LIST_SIZE: usize = 16;
const MAX_CORES: usize = 2;

var b_exit: bool = false;

var allocator: Allocator = .{};
var fibers: RingBuffer(Info, 128) = .{};
var wait_list: WaitList = .{};

fn fnv1(str: []const u8) u64 {
	// https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function
	const FNV_offset_basis: u64 = 0xcbf29ce484222325;
	const FNV_prime: u64 = 0x100000001b3;

	var hash = FNV_offset_basis;
	for (str) |b| {
		hash = hash *| FNV_prime;
		hash = hash ^ b;
	}
	
	if (hash == 0) {
		hash = 1;
	}
	return hash;
}

pub fn sizeof() usize {
	return 64*STACK_SIZE;
}

pub fn init(mem: usize) void {
	allocator.status = 0;
	allocator.mem = mem;
	
	allocator.init();
	fibers.init();
	wait_list.init();
}

pub fn exit() void {
	b_exit = true;
}

pub fn dec(name: []const u8) bool {
	const key = fnv1(name);

	wait_list.spinlock.lock();
	defer wait_list.spinlock.unlock();

	for (wait_list.keys, 0..) |k, i| {
		if (key == k) {
			if (wait_list.vals[i] > 0) {
				wait_list.vals[i] -= 1;
				return true;
			}
		}
	}
	return false;
}

pub fn push(info: Info) void {
	fibers.push(info);
}

pub fn start() void {
	var threads: [MAX_CORES - 1]HANDLE = undefined;
	
	var system_info: SYSTEM_INFO = undefined;
	GetSystemInfo(&system_info);
	var num_cores: u32 = system_info.dwNumberOfProcessors;
	num_cores = @min(MAX_CORES - 1, num_cores);
	
	for (0..num_cores) |i| {
        threads[i] = CreateThread(null, 0, &thread_entry, null, 0, null);
	}
	
	run();
	
    _ = WaitForMultipleObjects(threads.len, &threads[0], 1, INFINITE); 
}

fn thread_entry(lpParameter: LPVOID) callconv(WINAPI) DWORD {
	_ = lpParameter;
	run();
	return 0;
}

fn run() void {
	const thread_id: u64 = GetCurrentThreadId();
	while (true) {
		if (b_exit) {
			break;
		}

		const wait_idx = wait_list.find_with_thread(thread_id);
		if (wait_idx != WAIT_LIST_SIZE) {
			__continue(&wait_list.ctxs[wait_idx]);
			
			const stack: usize = wait_list.ctxs[wait_idx].stack_limit;
			if (wait_list.remove_at_zero(wait_idx)) {
				allocator.free(stack);
			}
			
			continue;
		}
		
		const info: Info = fibers.pop();
		if (info.is_valid()) {
			const mem = allocator.alloc();
			const size = STACK_SIZE;

			var rsp: usize = mem + size - @sizeOf(Header);

			var header: Header = .{};
			header.key = fnv1(info.name);
			rsp -= 32;
			header.p_user_data = rsp;
			rsp -= @sizeOf(Context);
			header.p_context = rsp;
			header.thread_id = GetCurrentThreadId();

			var ctx: Context = .{};
			ctx.rip = info.func;
			ctx.rsp = rsp;
    		ctx.fiber_storage = 0;
    		ctx.deallocation_stack = mem;
    		ctx.stack_limit = mem;
    		ctx.stack_base = mem + size;

			const dst = @as([*]u8, @ptrFromInt(header.p_user_data))[0..32];
			const src = @as([*]const u8, @ptrCast(&info.user_data))[0..32];
			@memcpy(dst, src);
			
			// since we use items on the stack and don't
			// control where they are pushed, we use this
			// proxy for assembly only functions
			__pop(&header, &ctx);

			if (wait_list.search(header.key) == WAIT_LIST_SIZE) {
				allocator.free(mem);
			}

			continue;
		}

		for (0..16) |_| {
			asm volatile("pause" :::);
		}
	}
}

fn __pop(header: *Header, ctx: *Context) void {
	// saving current context at the bottom of the stack
	asm volatile (
			// saving header
			\\ leaq -8*4(%[base]), %[base]
			\\ movq 8*0(%rcx), %rax
			\\ movq %rax, 8*0(%[base])
			\\ movq 8*1(%rcx), %rax
			\\ movq %rax, 8*1(%[base])
			\\ movq 8*2(%rcx), %rax
			\\ movq %rax, 8*2(%[base])
			\\ movq 8*3(%rcx), %rax
			\\ movq %rax, 8*3(%[base])

			// move p_context to register
			\\ movq 8*2(%[base]), %r8
			
			// instruction pointer is not needed because we
			// return using RETQ
        	// \\ movq %rip, 8*0(%r8)
		
			// saving registers
        	\\ movq %rsp, 8*1(%r8)
        	\\ movq %rbx, 8*2(%r8)
        	\\ movq %rbp, 8*3(%r8)
        	\\ movq %r12, 8*4(%r8)
        	\\ movq %r13, 8*5(%r8)
        	\\ movq %r14, 8*6(%r8)
        	\\ movq %r15, 8*7(%r8)
        	\\ movq %rdi, 8*8(%r8)
        	\\ movq %rsi, 8*9(%r8)
			
        	\\ movups %xmm6,  8*10(%r8)
        	\\ movups %xmm7,  8*12(%r8)
        	\\ movups %xmm8,  8*14(%r8)
        	\\ movups %xmm9,  8*16(%r8)
        	\\ movups %xmm10, 8*18(%r8)
        	\\ movups %xmm11, 8*20(%r8)
        	\\ movups %xmm12, 8*22(%r8)
        	\\ movups %xmm13, 8*24(%r8)
        	\\ movups %xmm14, 8*26(%r8)
        	\\ movups %xmm15, 8*28(%r8)
			
			// saving TIB data
        	\\ movq %gs:(0x30), %r10
			
        	\\ movq 0x20(%r10), %rax
        	\\ movq %rax, 8*30(%r8)
        	\\ movq 0x1478(%r10), %rax
        	\\ movq %rax, 8*31(%r8)
        	\\ movq 0x10(%r10), %rax
        	\\ movq %rax, 8*32(%r8)
        	\\ movq 0x08(%r10), %rax
        	\\ movq %rax, 8*33(%r8)
			:
			:[base] "{r8}" (ctx.*.stack_base)
	);

	asm volatile (
			// loading newly created context
        	\\ movq 8*0(%rdx), %r8
        	\\ movq 8*1(%rdx), %rsp
        	\\ movq 8*2(%rdx), %rbx
        	\\ movq 8*3(%rdx), %rbp
        	\\ movq 8*4(%rdx), %r12
        	\\ movq 8*5(%rdx), %r13
        	\\ movq 8*6(%rdx), %r14
        	\\ movq 8*7(%rdx), %r15
        	\\ movq 8*8(%rdx), %rdi
        	\\ movq 8*9(%rdx), %rsi
			
        	\\ movups 8*10(%rdx), %xmm6
        	\\ movups 8*12(%rdx), %xmm7
        	\\ movups 8*14(%rdx), %xmm8
        	\\ movups 8*16(%rdx), %xmm9
        	\\ movups 8*18(%rdx), %xmm10
        	\\ movups 8*20(%rdx), %xmm11
        	\\ movups 8*22(%rdx), %xmm12
        	\\ movups 8*24(%rdx), %xmm13
        	\\ movups 8*26(%rdx), %xmm14
        	\\ movups 8*28(%rdx), %xmm15
			
			// loading new TIB stuff
        	\\ movq %gs:(0x30), %r9
			
        	\\ movq 8*30(%rdx), %rax
        	\\ movq %rax, 0x20(%r9)
        	\\ movq 8*31(%rdx), %rax
        	\\ movq %rax, 0x1478(%r9)
        	\\ movq 8*32(%rdx), %rax
        	\\ movq %rax, 0x10(%r9)
        	\\ movq 8*33(%rdx), %rax
        	\\ movq %rax, 0x08(%r9)
			
        	\\ callq *%r8
			:
			:
	);

	asm volatile (
			// retrieve header
        	\\ movq %gs:(0x30), %r10
        	\\ movq 0x08(%r10), %rax
        	\\ leaq -8*4(%rax), %rcx
			
			// retrieving old context that was saved
			// at the bottom of the stack
			\\ movq 8*2(%rcx), %rcx

			// getting instruction pointer is not 
			// necessary
        	// \\ movq 8*0(%rcx), %rdx

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
	
	_ = header;
}

pub fn pause(value: u32) void {
	var header: Header = .{};
	__get_header(&header);

	wait_list.spinlock.lock();
	const idx = wait_list.reserve_unsafe(header.key);

	wait_list.thread_ids[idx] = header.thread_id;
	wait_list.vals[idx] = value;

	// since we use items on the stack and don't
	// control where they are pushed, we use this
	// proxy for assembly only functions
	__pause0(&wait_list.ctxs[idx]);
	wait_list.spinlock.unlock();
	__pause1(header.p_context);
}

fn __get_header(header: *Header) void {
	_ = header;
	
	asm volatile(
        	\\ movq %gs:(0x30), %r8
        	\\ movq 0x08(%r8), %r8
			\\ leaq -8*4(%r8), %r8
			
			\\ movq 8*0(%r8), %rax
			\\ movq %rax, 8*0(%rcx)
			\\ movq 8*1(%r8), %rax
			\\ movq %rax, 8*1(%rcx)
			\\ movq 8*2(%r8), %rax
			\\ movq %rax, 8*2(%rcx)
			\\ movq 8*3(%r8), %rax
			\\ movq %rax, 8*3(%rcx)
			:::
	);
}

fn __pause0(ctx: *Context) void {
	_ = ctx;
	
	// creating new context to return to
	asm volatile (
			// saving label as return point since
			// we want to use RETQ
        	\\ leaq CONTINUE0(%rip), %rax
        	\\ movq %rax, 8*0(%rcx)
			
        	\\ movq %rsp, 8*1(%rcx)
        	\\ movq %rbx, 8*2(%rcx)
        	\\ movq %rbp, 8*3(%rcx)
        	\\ movq %r12, 8*4(%rcx)
        	\\ movq %r13, 8*5(%rcx)
        	\\ movq %r14, 8*6(%rcx)
        	\\ movq %r15, 8*7(%rcx)
        	\\ movq %rdi, 8*8(%rcx)
        	\\ movq %rsi, 8*9(%rcx)
			
        	\\ movups %xmm6,  8*10(%rcx)
        	\\ movups %xmm7,  8*12(%rcx)
        	\\ movups %xmm8,  8*14(%rcx)
        	\\ movups %xmm9,  8*16(%rcx)
        	\\ movups %xmm10, 8*18(%rcx)
        	\\ movups %xmm11, 8*20(%rcx)
        	\\ movups %xmm12, 8*22(%rcx)
        	\\ movups %xmm13, 8*24(%rcx)
        	\\ movups %xmm14, 8*26(%rcx)
        	\\ movups %xmm15, 8*28(%rcx)
			
        	\\ movq %gs:(0x30), %r8
			
        	\\ movq 0x20(%r8), %rax
        	\\ movq %rax, 8*30(%rcx)
        	\\ movq 0x1478(%r8), %rax
        	\\ movq %rax, 8*31(%rcx)
        	\\ movq 0x10(%r8), %rax
        	\\ movq %rax, 8*32(%rcx)
        	\\ movq 0x08(%r8), %rax
        	\\ movq %rax, 8*33(%rcx)
			:::
	);
}

fn __pause1(rsp: u64) void {
	_ = rsp;
	
	asm volatile(
			// return to function that called the context
			\\ leaq -8*1(%rcx), %rsp
			\\ retq
			
			\\ CONTINUE0:
			:::
	);
}

fn __continue(ctx: *Context) void {
	_ = ctx;
	
	// saving current context and overriding old context
	asm volatile (
			// load p_context from header
        	// \\ movq %gs:(0x30), %r10
        	// \\ movq 0x08(%r10), %rax
        	// \\ leaq -8*4(%rax), %rdx
			// \\ movq 8*2(%rdx), %rdx
			\\ movq 8*33(%rcx), %rax
        	\\ leaq -8*4(%rax), %rdx
			\\ movq 8*2(%rdx), %rdx
		
			// No need to save instruction pointer since we
			// use RETQ
        	// \\ leaq CONTINUE1(%rip), %rax
        	// \\ movq %rax, 8*0(%rdx)
			
			// saving registers
        	\\ movq %rsp, 8*1(%rdx)
        	\\ movq %rbx, 8*2(%rdx)
        	\\ movq %rbp, 8*3(%rdx)
        	\\ movq %r12, 8*4(%rdx)
        	\\ movq %r13, 8*5(%rdx)
        	\\ movq %r14, 8*6(%rdx)
        	\\ movq %r15, 8*7(%rdx)
        	\\ movq %rdi, 8*8(%rdx)
        	\\ movq %rsi, 8*9(%rdx)
			
        	\\ movups %xmm6,  8*10(%rdx)
        	\\ movups %xmm7,  8*12(%rdx)
        	\\ movups %xmm8,  8*14(%rdx)
        	\\ movups %xmm9,  8*16(%rdx)
        	\\ movups %xmm10, 8*18(%rdx)
        	\\ movups %xmm11, 8*20(%rdx)
        	\\ movups %xmm12, 8*22(%rdx)
        	\\ movups %xmm13, 8*24(%rdx)
        	\\ movups %xmm14, 8*26(%rdx)
        	\\ movups %xmm15, 8*28(%rdx)
			
			// saving TIB data
        	\\ movq %gs:(0x30), %r10
			
        	\\ movq 0x20(%r10), %rax
        	\\ movq %rax, 8*30(%rdx)
        	\\ movq 0x1478(%r10), %rax
        	\\ movq %rax, 8*31(%rdx)
        	\\ movq 0x10(%r10), %rax
        	\\ movq %rax, 8*32(%rdx)
        	\\ movq 0x08(%r10), %rax
        	\\ movq %rax, 8*33(%rdx)

			// replacing bottom most return address in the stack
			\\ leaq -8*1(%rdx), %rax
        	\\ leaq CONTINUE1(%rip), %r8
			\\ movq %r8, (%rax)
			:
			:
			// :[stack] "{rcx}" (ctx.*.stack_base - @sizeOf(Context))
	);

	// restoring context from the wait list
	asm volatile (
			// restoring registers
        	\\ movq 8*0(%rcx), %rdx
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
        	\\ movq %gs:(0x30), %r10
			
        	\\ movq 8*30(%rcx), %rax
        	\\ movq %rax, 0x20(%r10)
        	\\ movq 8*31(%rcx), %rax
        	\\ movq %rax, 0x1478(%r10)
        	\\ movq 8*32(%rcx), %rax
        	\\ movq %rax, 0x10(%r10)
        	\\ movq 8*33(%rcx), %rax
        	\\ movq %rax, 0x08(%r10)
			
			// DONT'T use CALLQ since we don't want to disturb
			// the current %RSP and we have replaced return 
			// address in previous asm block
        	\\ jmpq *%rdx
			:
			:
			// :[ctx] "{rcx}" (ctx)
	);

	// restoring this context
	asm volatile (
			// a label where context returns to
			\\ CONTINUE1:
			
			// load p_context from header
        	\\ movq %gs:(0x30), %r10
        	\\ movq 0x08(%r10), %rax
        	\\ leaq -8*4(%rax), %rdx
			\\ movq 8*2(%rdx), %rdx
			
			// no need to replace instruction pointer
        	// \\ movq 8*0(%rdx), %rdx

			// restoring registers
        	\\ movq 8*1(%rdx), %rsp
        	\\ movq 8*2(%rdx), %rbx
        	\\ movq 8*3(%rdx), %rbp
        	\\ movq 8*4(%rdx), %r12
        	\\ movq 8*5(%rdx), %r13
        	\\ movq 8*6(%rdx), %r14
        	\\ movq 8*7(%rdx), %r15
        	\\ movq 8*8(%rdx), %rdi
        	\\ movq 8*9(%rdx), %rsi
			
        	\\ movups 8*10(%rdx), %xmm6
        	\\ movups 8*12(%rdx), %xmm7
        	\\ movups 8*14(%rdx), %xmm8
        	\\ movups 8*16(%rdx), %xmm9
        	\\ movups 8*18(%rdx), %xmm10
        	\\ movups 8*20(%rdx), %xmm11
        	\\ movups 8*22(%rdx), %xmm12
        	\\ movups 8*24(%rdx), %xmm13
        	\\ movups 8*26(%rdx), %xmm14
        	\\ movups 8*28(%rdx), %xmm15
			
			// restoring TIB data
        	\\ movq  8*30(%rdx), %rax
        	\\ movq  %rax, 0x20(%r10)
        	\\ movq  8*31(%rdx), %rax
        	\\ movq  %rax, 0x1478(%r10)
        	\\ movq  8*32(%rdx), %rax
        	\\ movq  %rax, 0x10(%r10)
        	\\ movq  8*33(%rdx), %rax
        	\\ movq  %rax, 0x08(%r10)
			:
			:
	);
}

pub fn pack(user_data: anytype) u256 {
	staticAssert(@sizeOf(@TypeOf(user_data)) <= 32);
	
	var payload: u256 = 0;
	
	var dst: []u8 = undefined;
	dst.ptr = @ptrCast(&payload);
	dst.len = @sizeOf(@TypeOf(user_data));
	
	var src: []u8 = undefined;
	src.ptr = @constCast(@ptrCast(&user_data));
	src.len = @sizeOf(@TypeOf(user_data));
	
	@memcpy(dst, src);
	
	return payload;
}

pub fn getUserData(comptime T: type) *T {
	return asm volatile (
			// retrieve header
        	\\ movq %gs:(0x30), %r10
        	\\ movq 0x08(%r10), %rax
        	\\ leaq -8*4(%rax), %rax
			// return Header::p_user_data
			\\ movq 8*1(%rax), %rax
			: [ret] "={rax}" (-> *T)
			:
	);
}

pub fn getThreadId() u64 {
	return asm volatile (
			// retrieve header
        	\\ movq %gs:(0x30), %r10
        	\\ movq 0x08(%r10), %rax
        	\\ leaq -8*4(%rax), %rax
			// return Header::thread_id
			\\ movq 8*3(%rax), %rax
			: [ret] "={rax}" (-> u64)
			:
	);
}

fn assert(x: bool) void {
    if (!x) {
        @panic("assert failed!");
    }
}

fn staticAssert(comptime x: bool) void {
    if (!x) {
        @compileError("static assert failed!");
    }
}

comptime {
	// TODO: test other offsets, cpu arch and os
	staticAssert(@sizeOf(Header) == 8*4);
	staticAssert(@sizeOf(Context) == 8*34);
}

const WINAPI: std.builtin.CallingConvention = if (native_arch == .x86) .Stdcall else .C;
// const WINAPI: std.builtin.CallingConvention = .C;

// https://learn.microsoft.com/en-us/windows/win32/winprog/windows-data-types
const HANDLE = ?*anyopaque;
const SIZE_T = u64;
const LPVOID = ?*anyopaque;
const WORD = u16;
const DWORD = u32;
const LPDWORD = ?*u32;
const DWORD_PTR = u64;
const BOOL = i32;
const INFINITE: u32 = 0xffffffff;

// https://learn.microsoft.com/en-us/previous-versions/windows/desktop/legacy/ms686736(v=vs.85)
const LPTHREAD_START_ROUTINE = *const fn (lpParameter: LPVOID) callconv(WINAPI) DWORD;

// https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/ns-sysinfoapi-system_info
const SYSTEM_INFO = extern struct {
    anon1: extern union {
        dwOemId: DWORD,
        anon2: extern struct {
            wProcessorArchitecture: WORD,
            wReserved: WORD,
        },
    },
    dwPageSize: DWORD,
    lpMinimumApplicationAddress: LPVOID,
    lpMaximumApplicationAddress: LPVOID,
    dwActiveProcessorMask: DWORD_PTR,
    dwNumberOfProcessors: DWORD,
    dwProcessorType: DWORD,
    dwAllocationGranularity: DWORD,
    wProcessorLevel: WORD,
    wProcessorRevision: WORD,
};

// https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-getsysteminfo
extern "kernel32" fn GetSystemInfo(lpSystemInfo: *SYSTEM_INFO) callconv(WINAPI) void;

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

