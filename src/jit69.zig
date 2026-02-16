const std = @import("std");
const builtin = @import("builtin");
const is_darwin = builtin.os.tag == .macos;

extern fn __clear_cache(start: usize, end: usize) callconv(.C) void;

pub fn main() !void {
    if (is_darwin) {
        try runDarwin();
    } else {
        try runGeneric();
    }
}

fn runDarwin() !void {
    const c = @cImport({
        @cInclude("sys/mman.h");
        @cInclude("pthread.h");
    });

    const page = std.mem.page_size;
    std.debug.print("darwin: page={d}\n", .{page});
    if (@hasDecl(c, "pthread_jit_write_protect_supported_np")) {
        _ = c.pthread_jit_write_protect_supported_np();
        std.debug.print("pthread_jit_write_protect_supported_np: present\n", .{});
    } else {
        std.debug.print("pthread_jit_write_protect_supported_np: not present\n", .{});
    }
    // Try two patterns: (A) map RX then toggle-write, (B) map RW then toggle-exec
    const code = [_]u32{ 0xD28008A0, 0xD65F03C0 };

    // Pattern B first: RW, write, toggle to exec
    {
        const raw_b = c.mmap(null, page, c.PROT_READ | c.PROT_WRITE, c.MAP_PRIVATE | c.MAP_ANON | c.MAP_JIT, -1, 0);
        if (raw_b != c.MAP_FAILED) {
            const p_any_b: ?*anyopaque = @ptrCast(raw_b);
            const mem_page_b: [*]align(std.mem.page_size) u8 = @alignCast(@ptrCast(p_any_b));
            var buf_b: []align(std.mem.page_size) u8 = mem_page_b[0..page];
            std.debug.print("mapped: ptr=0x{x} len={d} (RW, MAP_JIT)\n", .{ @intFromPtr(buf_b.ptr), buf_b.len });
            @memcpy(buf_b[0 .. code.len * @sizeOf(u32)], std.mem.sliceAsBytes(code[0..]));
            _ = c.pthread_jit_write_protect_np(1);
            std.debug.print("jit_write_protect_np(1)\n", .{});
            // Attempt to flip to RX explicitly
            _ = c.mprotect(buf_b.ptr, buf_b.len, c.PROT_READ | c.PROT_EXEC);
            __clear_cache(@intFromPtr(buf_b.ptr), @intFromPtr(buf_b.ptr) + code.len * @sizeOf(u32));
            const FnB = *const fn () callconv(.C) i64;
            const fun_b: FnB = @alignCast(@ptrCast(buf_b.ptr));
            const res_b = fun_b();
            std.debug.print("B: {d}\n", .{res_b});
            _ = c.munmap(buf_b.ptr, buf_b.len);
            return;
        }
    }

    // Pattern A: RX, toggle to write, write, toggle to exec
    {
        const raw = c.mmap(null, page, c.PROT_READ | c.PROT_EXEC, c.MAP_PRIVATE | c.MAP_ANON | c.MAP_JIT, -1, 0);
        if (raw == c.MAP_FAILED) return error.OutOfMemory;
        const ptr_any: ?*anyopaque = @ptrCast(raw);
        const mem_page: [*]align(std.mem.page_size) u8 = @alignCast(@ptrCast(ptr_any));
        var buf: []align(std.mem.page_size) u8 = mem_page[0..page];
        std.debug.print("mapped: ptr=0x{x} len={d} (RX, MAP_JIT)\n", .{ @intFromPtr(buf.ptr), buf.len });
        _ = c.pthread_jit_write_protect_np(0);
        std.debug.print("jit_write_protect_np(0)\n", .{});
        @memcpy(buf[0 .. code.len * @sizeOf(u32)], std.mem.sliceAsBytes(code[0..]));
        _ = c.pthread_jit_write_protect_np(1);
        std.debug.print("jit_write_protect_np(1)\n", .{});
        __clear_cache(@intFromPtr(buf.ptr), @intFromPtr(buf.ptr) + code.len * @sizeOf(u32));
        const Fn = *const fn () callconv(.C) i64;
        const fun: Fn = @alignCast(@ptrCast(buf.ptr));
        const res = fun();
        std.debug.print("A: {d}\n", .{res});
        _ = c.munmap(buf.ptr, buf.len);
    }
}

fn runGeneric() !void {
    const page = std.mem.page_size;
    const mem = try std.posix.mmap(null, page, std.posix.PROT.READ | std.posix.PROT.WRITE, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0);
    defer std.posix.munmap(mem);

    const code = [_]u32{
        0xD28008A0, // movz x0, #69
        0xD65F03C0, // ret
    };
    @memcpy(mem[0 .. code.len * @sizeOf(u32)], std.mem.sliceAsBytes(code[0..]));
    try std.posix.mprotect(mem, std.posix.PROT.READ | std.posix.PROT.EXEC);
    __clear_cache(@intFromPtr(mem.ptr), @intFromPtr(mem.ptr) + code.len * @sizeOf(u32));

    const Fn = *const fn () callconv(.C) i64;
    const fun: Fn = @alignCast(@ptrCast(mem.ptr));
    const res = fun();
    std.debug.print("{d}\n", .{res});
}
