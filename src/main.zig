const std = @import("std");
const builtin = @import("builtin");
const darwin = builtin.os.tag == .macos;
const darwin_c = if (darwin) @cImport({
    @cInclude("sys/mman.h");
    @cInclude("pthread.h");
}) else struct {};
const posix_dl = @cImport({
    @cInclude("dlfcn.h");
});
const c_std = @cImport({
    @cInclude("stdlib.h");
});
const Editor = @import("zigline").Editor;
const Asm = @import("asm.zig");
const Args = @import("args.zig");

extern fn __clear_cache(start: usize, end: usize) callconv(.C) void;

/// Prints a hexdump of the given slice.
/// @param mem the slice to print
/// @param len the length of the slice
fn debugSlice(mem: []u8, len: usize) void {
    // hexdump the image in 4 byte chunks
    var i: usize = 0;

    // print header with offsets
    std.debug.print("     ", .{});
    while (i < 64) {
        std.debug.print("{x:0>2}       ", .{i});
        i += 4;
    }
    i = 0;

    std.debug.print("\n000  ", .{});
    while (i < len) {
        std.debug.print("{} ", .{std.fmt.fmtSliceHexLower(mem[i .. i + 4])});
        // add a newline every 16 bytes
        i += 4;
        if (i % 64 == 0) {
            std.debug.print("\n{x:0>3}  ", .{i});
        }
    }
    std.debug.print("\n", .{});
}

inline fn outPrint(comptime fmt: []const u8, args: anytype) void {
    if (builtin.is_test) {
        std.debug.print(fmt, args);
    } else {
        std.io.getStdOut().writer().print(fmt, args) catch std.debug.print(fmt, args);
    }
}

const Fy = struct {
    fyalloc: std.mem.Allocator,
    userWords: std.StringHashMap(Word),
    importedFiles: std.StringHashMap(void),
    data_stack_mem: ?[*]align(std.mem.page_size) u8 = null,
    data_stack_top: usize = 0, // x21/x22 init value = top of usable region
    tramp_stack_mem: ?[*]align(std.mem.page_size) u8 = null,
    tramp_stack_top: usize = 0,
    image: Image,
    heap: Heap,

    const version = "v0.0.1";
    const DATA_STACK_PAGES = 8; // 32KB usable = 4096 values
    const TRAMP_STACK_PAGES = 1; // 4KB usable = 512 values

    // Tagged value encoding:
    // - Integers: stored as raw i64 (even values have TAG_INT=0 in LSB)
    // - Heap refs: ((id + HEAP_BASE) << 1) | TAG_STR, always odd and >= 2^41
    // Odd integers below 2^41 are safely distinguished from heap refs by the
    // HEAP_BASE threshold check in isStr(). Collision is impossible for any
    // integer below 2^40 (~1 trillion), which covers all practical use cases.
    const TAG_INT = 0;
    const TAG_STR = 1;
    const TAG_MASK = 1;
    const TAG_BITS = 1;
    const HEAP_BASE: u64 = 1 << 40;
    const Value = i64;

    fn makeInt(n: i64) Value {
        return n;
    }

    fn makeStr(id: usize) Value {
        // Encode heap object id with high bias, reserving low TAG_BITS as tag
        const tagged: u64 = ((@as(u64, @intCast(id)) + HEAP_BASE) << TAG_BITS) | TAG_STR;
        return @as(Value, @bitCast(tagged));
    }

    fn isInt(v: Value) bool {
        return !isStr(v);
    }

    fn isStr(v: Value) bool {
        if ((v & TAG_MASK) != TAG_STR) return false;
        const raw: u64 = @bitCast(v);
        return (raw >> TAG_BITS) >= HEAP_BASE;
    }

    fn getInt(v: Value) i64 {
        std.debug.assert(isInt(v));
        return v;
    }

    fn getStrId(v: Value) usize {
        std.debug.assert(isStr(v));
        const raw: u64 = @bitCast(v);
        const biased = (raw >> TAG_BITS) - HEAP_BASE;
        return @intCast(biased);
    }

    fn makeFloat(f: f64) Value {
        return @bitCast(f);
    }

    fn getFloat(v: Value) f64 {
        return @bitCast(v);
    }

    fn init(allocator: std.mem.Allocator) Fy {
        const image = Image.init() catch @panic("failed to allocate image");
        var fy = Fy{
            .userWords = std.StringHashMap(Word).init(allocator),
            .importedFiles = std.StringHashMap(void).init(allocator),
            .fyalloc = allocator,
            .image = image,
            .heap = Heap.init(allocator),
        };
        fy.initStacks();
        return fy;
    }

    fn deinit(self: *Fy) void {
        self.image.deinit();
        self.heap.deinit();
        deinitUserWords(self);
        self.deinitImportedFiles();
        self.deinitStacks();
        // Reset cached adapter pointers — they point into our (now-freed) image
        Builtins.adapt1 = null;
        Builtins.adapt2 = null;
    }

    fn initStacks(self: *Fy) void {
        const page = std.mem.page_size;
        // Data stack: [guard page][usable pages][guard page]
        {
            const usable = DATA_STACK_PAGES * page;
            const total = usable + 2 * page;
            if (darwin) {
                const raw = darwin_c.mmap(null, total, darwin_c.PROT_NONE, darwin_c.MAP_PRIVATE | darwin_c.MAP_ANON, -1, 0);
                if (raw == darwin_c.MAP_FAILED) @panic("failed to allocate data stack");
                const ptr: [*]align(page) u8 = @alignCast(@ptrCast(raw));
                if (darwin_c.mprotect(@ptrCast(ptr + page), usable, darwin_c.PROT_READ | darwin_c.PROT_WRITE) != 0)
                    @panic("failed to protect data stack");
                self.data_stack_mem = ptr;
                self.data_stack_top = @intFromPtr(ptr) + page + usable;
            } else {
                const flags: std.posix.MAP = .{ .TYPE = .PRIVATE, .ANONYMOUS = true };
                const mem = std.posix.mmap(null, total, std.posix.PROT.NONE, flags, -1, 0) catch
                    @panic("failed to allocate data stack");
                const usable_ptr: [*]align(page) u8 = @alignCast(mem.ptr + page);
                const usable_slice: []align(page) u8 = usable_ptr[0..usable];
                std.posix.mprotect(usable_slice, .{ .READ = true, .WRITE = true }) catch
                    @panic("failed to protect data stack");
                self.data_stack_mem = mem.ptr;
                self.data_stack_top = @intFromPtr(mem.ptr) + page + usable;
            }
        }
        // Tramp stack: [guard page][usable pages][guard page]
        {
            const usable = TRAMP_STACK_PAGES * page;
            const total = usable + 2 * page;
            if (darwin) {
                const raw = darwin_c.mmap(null, total, darwin_c.PROT_NONE, darwin_c.MAP_PRIVATE | darwin_c.MAP_ANON, -1, 0);
                if (raw == darwin_c.MAP_FAILED) @panic("failed to allocate tramp stack");
                const ptr: [*]align(page) u8 = @alignCast(@ptrCast(raw));
                if (darwin_c.mprotect(@ptrCast(ptr + page), usable, darwin_c.PROT_READ | darwin_c.PROT_WRITE) != 0)
                    @panic("failed to protect tramp stack");
                self.tramp_stack_mem = ptr;
                self.tramp_stack_top = @intFromPtr(ptr) + page + usable;
            } else {
                const flags: std.posix.MAP = .{ .TYPE = .PRIVATE, .ANONYMOUS = true };
                const mem = std.posix.mmap(null, total, std.posix.PROT.NONE, flags, -1, 0) catch
                    @panic("failed to allocate tramp stack");
                const usable_ptr: [*]align(page) u8 = @alignCast(mem.ptr + page);
                const usable_slice: []align(page) u8 = usable_ptr[0..usable];
                std.posix.mprotect(usable_slice, .{ .READ = true, .WRITE = true }) catch
                    @panic("failed to protect tramp stack");
                self.tramp_stack_mem = mem.ptr;
                self.tramp_stack_top = @intFromPtr(mem.ptr) + page + usable;
            }
        }
    }

    fn deinitStacks(self: *Fy) void {
        const page = std.mem.page_size;
        if (self.data_stack_mem) |ptr| {
            const total = DATA_STACK_PAGES * page + 2 * page;
            if (darwin) {
                _ = darwin_c.munmap(ptr, total);
            } else {
                const slice: []align(page) u8 = @alignCast(ptr[0..total]);
                std.posix.munmap(slice);
            }
        }
        if (self.tramp_stack_mem) |ptr| {
            const total = TRAMP_STACK_PAGES * page + 2 * page;
            if (darwin) {
                _ = darwin_c.munmap(ptr, total);
            } else {
                const slice: []align(page) u8 = @alignCast(ptr[0..total]);
                std.posix.munmap(slice);
            }
        }
    }

    fn deinitUserWords(self: *Fy) void {
        var keys = self.userWords.keyIterator();
        while (keys.next()) |k| {
            if (self.userWords.getPtr(k.*)) |v| {
                self.fyalloc.free(v.code);
                self.fyalloc.free(k.*);
            }
        }
        self.userWords.deinit();
    }

    fn deinitImportedFiles(self: *Fy) void {
        var keys = self.importedFiles.keyIterator();
        while (keys.next()) |k| {
            self.fyalloc.free(k.*);
        }
        self.importedFiles.deinit();
    }

    // Render a Value to any writer in a human-friendly way.
    fn writeValue(self: *Fy, writer: anytype, v: Value) !void {
        if (isStr(v)) {
            if (self.heap.typeOf(v)) |t| switch (t) {
                .String => {
                    const s = self.heap.getString(v);
                    try writer.print("\"{s}\"", .{s});
                },
                .Quote => try self.writeQuote(writer, v),
            } else {
                try writer.print("<invalid heap>", .{});
            }
            return;
        }
        // Everything that isn't a heap ref is an integer (raw i64)
        try writer.print("{d}", .{v});
    }

    // Render a Quote value as [ ... ] recursively.
    fn writeQuote(self: *Fy, writer: anytype, qv: Value) !void {
        const q = self.heap.getQuote(qv);
        try writer.print("[", .{});
        var first = true;
        for (q.items.items) |it| {
            if (!first) try writer.print(" ", .{});
            first = false;
            switch (it) {
                .Number => |n| try writer.print("{d}", .{n}),
                .Float => |f| try writer.print("{d}", .{f}),
                .Word => |w| try writer.print("{s}", .{w}),
                .String => |s| try writer.print("\"{s}\"", .{s}),
                .Quote => |nested| try self.writeQuote(writer, nested),
            }
        }
        try writer.print("]", .{});
    }

    // Unified heap for strings and quotes with lazy JIT cache
    const Heap = struct {
        const ObjType = enum { String, Quote };

        const Item = union(enum) {
            Number: i64,
            Float: f64,
            Word: []u8,
            String: []u8,
            Quote: Value, // nested quote as heap ref
        };

        const QuoteObj = struct {
            items: std.ArrayList(Item),
            // Immutable lexical locals declared in [ | a b | ... ]
            locals_names: std.ArrayList([]u8),
            cached_ptr: ?usize = null,
        };

        const Entry = union(enum) {
            String: []u8,
            Quote: QuoteObj,
            Free: usize, // next free slot index (maxInt = end of list)
        };

        allocator: std.mem.Allocator,
        entries: std.ArrayList(Entry),
        free_head: ?usize = null,
        roots: std.AutoHashMap(usize, void),

        fn init(allocator: std.mem.Allocator) Heap {
            return Heap{
                .allocator = allocator,
                .entries = std.ArrayList(Entry).init(allocator),
                .roots = std.AutoHashMap(usize, void).init(allocator),
            };
        }

        fn addRoot(self: *Heap, id: usize) void {
            self.roots.put(id, {}) catch {};
        }

        fn allocSlot(self: *Heap, entry: Entry) !usize {
            if (self.free_head) |id| {
                self.free_head = switch (self.entries.items[id]) {
                    .Free => |next| if (next == std.math.maxInt(usize)) null else next,
                    else => unreachable,
                };
                self.entries.items[id] = entry;
                return id;
            }
            try self.entries.append(entry);
            return self.entries.items.len - 1;
        }

        fn freeEntry(self: *Heap, id: usize) void {
            switch (self.entries.items[id]) {
                .String => |str| self.allocator.free(str),
                .Quote => |*q| {
                    for (q.items.items) |it| switch (it) {
                        .Word => |w| self.allocator.free(w),
                        .String => |s| self.allocator.free(s),
                        else => {},
                    };
                    for (q.locals_names.items) |nm| self.allocator.free(nm);
                    q.locals_names.deinit();
                    q.items.deinit();
                },
                .Free => return,
            }
            self.entries.items[id] = Entry{ .Free = self.free_head orelse std.math.maxInt(usize) };
            self.free_head = id;
        }

        fn markReachable(self: *Heap, marked: *std.AutoHashMap(usize, void), id: usize) void {
            if (id >= self.entries.items.len) return;
            if (marked.contains(id)) return;
            marked.put(id, {}) catch return;
            switch (self.entries.items[id]) {
                .Quote => |q| {
                    for (q.items.items) |it| switch (it) {
                        .Quote => |qv| {
                            if (Fy.isStr(qv)) {
                                self.markReachable(marked, Fy.getStrId(qv));
                            }
                        },
                        else => {},
                    };
                },
                else => {},
            }
        }

        fn gc(self: *Heap, stack_ptr: usize, stack_base: usize) void {
            var marked = std.AutoHashMap(usize, void).init(self.allocator);
            defer marked.deinit();
            // Mark phase: walk data stack from current ptr to base
            var addr = stack_ptr;
            while (addr < stack_base) : (addr += @sizeOf(Value)) {
                const v: Value = @as(*const Value, @alignCast(@ptrCast(@as([*]const u8, @ptrFromInt(addr))))).*;
                if (Fy.isStr(v)) {
                    self.markReachable(&marked, Fy.getStrId(v));
                }
            }
            // Mark roots (compiler-created literals embedded in JIT code)
            var root_iter = self.roots.keyIterator();
            while (root_iter.next()) |root_id| {
                self.markReachable(&marked, root_id.*);
            }
            // Sweep phase: free all unmarked live entries
            for (self.entries.items, 0..) |*e, i| {
                switch (e.*) {
                    .Free => continue,
                    else => {
                        if (!marked.contains(i)) {
                            self.freeEntry(i);
                        }
                    },
                }
            }
        }

        fn deinit(self: *Heap) void {
            for (self.entries.items) |*e| {
                switch (e.*) {
                    .String => |str| self.allocator.free(str),
                    .Quote => |*q| {
                        for (q.items.items) |it| switch (it) {
                            .Word => |w| self.allocator.free(w),
                            .String => |s| self.allocator.free(s),
                            else => {},
                        };
                        for (q.locals_names.items) |nm| self.allocator.free(nm);
                        q.locals_names.deinit();
                        q.items.deinit();
                    },
                    .Free => {},
                }
            }
            self.entries.deinit();
            self.roots.deinit();
        }

        fn typeOf(self: *Heap, v: Value) ?ObjType {
            if (!Fy.isStr(v)) return null;
            const id = Fy.getStrId(v);
            if (id >= self.entries.items.len) return null;
            return switch (self.entries.items[id]) {
                .String => ObjType.String,
                .Quote => ObjType.Quote,
                .Free => null,
            };
        }

        fn storeString(self: *Heap, str: []const u8) !Value {
            const buf = try self.allocator.alloc(u8, str.len);
            @memcpy(buf, str);
            const id = try self.allocSlot(Entry{ .String = buf });
            return Fy.makeStr(id);
        }

        fn getString(self: *Heap, v: Value) []const u8 {
            std.debug.assert(Fy.isStr(v));
            const id = Fy.getStrId(v);
            if (id >= self.entries.items.len) return "<invalid string>";
            return switch (self.entries.items[id]) {
                .String => |s| s,
                else => "<non-string>",
            };
        }

        fn concat(self: *Heap, a: Value, b: Value) !Value {
            const sa = self.getString(a);
            const sb = self.getString(b);
            const newLen = sa.len + sb.len;
            var out = try self.allocator.alloc(u8, newLen);
            @memcpy(out[0..sa.len], sa);
            @memcpy(out[sa.len..], sb);
            const id = try self.allocSlot(Entry{ .String = out });
            return Fy.makeStr(id);
        }

        fn length(self: *Heap, v: Value) Value {
            const s = self.getString(v);
            return Fy.makeInt(@as(i64, @intCast(s.len)));
        }

        fn storeQuote(self: *Heap, items: std.ArrayList(Item)) !Value {
            const q = QuoteObj{ .items = items, .locals_names = std.ArrayList([]u8).init(self.allocator), .cached_ptr = null };
            const id = try self.allocSlot(Entry{ .Quote = q });
            return Fy.makeStr(id);
        }

        fn getQuote(self: *Heap, v: Value) *QuoteObj {
            std.debug.assert(Fy.isStr(v));
            const id = Fy.getStrId(v);
            return switch (self.entries.items[id]) {
                .Quote => |*q| q,
                else => @panic("expected quote object"),
            };
        }
    };

    const Word = struct {
        code: []const u32, //machine code (for builtins/inline words)
        c: usize, //consumes
        p: usize, //produces
        callSlot0: ?*const anyopaque = null,
        callSlot3: ?*const anyopaque = null,
        image_addr: ?usize = null, // entry point in JIT image for BL-callable words

        const DEFINE = ":";
        const END = ";";
        const QUOTE_OPEN = "[";
        const QUOTE_END = "]";
    };

    fn fnToWord(comptime fun: anytype) Word {
        const T = @TypeOf(fun);
        const typeinfo = @typeInfo(T).Fn;
        const paramCount = typeinfo.params.len;
        var returnCount = 0;
        for (0..paramCount) |i| {
            if (typeinfo.params[i].type.? != Value) {
                @compileError("fnToWord: param {} must be Value");
            }
        }
        if (typeinfo.return_type) |rt| {
            if (rt != Value and rt != void) {
                @compileError("fnToWord: return type must be Value or void");
            }
            if (rt == Value) {
                returnCount = 1;
            }
        }

        // 1 for call slot, 1 for each param, 1 for each return value
        const codeLen: usize = 1 + paramCount + returnCount;

        var code = [1]u32{undefined} ** codeLen;

        // pop all params
        for (0..paramCount) |i| {
            // TODO set some limit on the number of params, this is dictated by the number of registers
            if (i > 8) {
                @compileError("fnToWord: too many params");
            }
            code[i] = Asm.@".pop Xn"(i);
        }

        // call the function and push the result
        if (returnCount == 1) {
            code[codeLen - 2] = Asm.CALLSLOT;
            code[codeLen - 1] = Asm.@".push x0";
        } else {
            code[codeLen - 1] = Asm.CALLSLOT;
        }

        const constCode = code[0..].*;
        return Word{
            .code = &constCode,
            .c = paramCount,
            .p = returnCount,
            .callSlot0 = &fun,
        };
    }

    fn binOp(comptime op: u32, comptime swap: bool) Word {
        var p1 = Asm.@".pop x0, x1";
        if (swap) {
            p1 = Asm.@".pop x1, x0";
        }
        const code = &[_]u32{
            p1,
            op,
            Asm.@".push x0",
        };
        return Word{
            .code = code,
            .c = 2,
            .p = 1,
        };
    }

    fn cmpOp(comptime op: u32) Word {
        return inlineWord(&[_]u32{
            Asm.@".pop x0, x1",
            Asm.@"cmp x0, x1",
            op,
            Asm.@"mov x0, #0",
            Asm.@"b 2",
            Asm.@"mov x0, #1",
            Asm.@".push x0",
        }, 2, 1);
    }

    fn inlineWord(comptime code: []const u32, comptime c: usize, comptime p: usize) Word {
        return Word{
            .code = code,
            .c = c,
            .p = p,
        };
    }

    const Builtins = struct {
        // Quote concatenation: (... a b -- q)
        fn quoteConcat(b: Value, a: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            // Ensure both are quotes
            if (!isStr(a) or !isStr(b)) @panic("cat expects quotes");
            if (fy.heap.typeOf(a) orelse Heap.ObjType.String != .Quote) @panic("cat expects quote A");
            if (fy.heap.typeOf(b) orelse Heap.ObjType.String != .Quote) @panic("cat expects quote B");
            const qa = fy.heap.getQuote(a);
            const qb = fy.heap.getQuote(b);
            var items = std.ArrayList(Heap.Item).init(fy.fyalloc);
            items.ensureTotalCapacity(qa.items.items.len + qb.items.items.len) catch @panic("oom");
            // copy items from qa
            for (qa.items.items) |it| switch (it) {
                .Number => |n| items.append(Heap.Item{ .Number = n }) catch @panic("oom"),
                .Float => |f| items.append(Heap.Item{ .Float = f }) catch @panic("oom"),
                .Word => |w| items.append(Heap.Item{ .Word = fy.fyalloc.dupe(u8, w) catch @panic("oom") }) catch @panic("oom"),
                .String => |s| items.append(Heap.Item{ .String = fy.fyalloc.dupe(u8, s) catch @panic("oom") }) catch @panic("oom"),
                .Quote => |qv| items.append(Heap.Item{ .Quote = qv }) catch @panic("oom"),
            };
            // copy items from qb
            for (qb.items.items) |it2| switch (it2) {
                .Number => |n| items.append(Heap.Item{ .Number = n }) catch @panic("oom"),
                .Float => |f| items.append(Heap.Item{ .Float = f }) catch @panic("oom"),
                .Word => |w| items.append(Heap.Item{ .Word = fy.fyalloc.dupe(u8, w) catch @panic("oom") }) catch @panic("oom"),
                .String => |s| items.append(Heap.Item{ .String = fy.fyalloc.dupe(u8, s) catch @panic("oom") }) catch @panic("oom"),
                .Quote => |qv| items.append(Heap.Item{ .Quote = qv }) catch @panic("oom"),
            };
            return fy.heap.storeQuote(items) catch @panic("heap store failed");
        }

        // Quote length: (q -- n)
        fn quoteLen(q: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (!isStr(q) or (fy.heap.typeOf(q) orelse Heap.ObjType.String) != .Quote) @panic("qlen expects quote");
            const qq = fy.heap.getQuote(q);
            return makeInt(@as(i64, @intCast(qq.items.items.len)));
        }

        // Quote empty? (q -- 1|0)
        fn quoteEmpty(q: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (!isStr(q) or (fy.heap.typeOf(q) orelse Heap.ObjType.String) != .Quote) @panic("qempty? expects quote");
            const qq = fy.heap.getQuote(q);
            return makeInt(@as(i64, @intFromBool(qq.items.items.len == 0)));
        }

        fn itemToValue(fy: *Fy, it: Heap.Item) Value {
            return switch (it) {
                .Number => |n| makeInt(n),
                .Float => |f| makeFloat(f),
                .String => |s| fy.heap.storeString(s) catch @panic("store string failed"),
                .Quote => |qv| qv,
                .Word => |w| blk: {
                    // Wrap single word into a one-item quote
                    var items = std.ArrayList(Heap.Item).init(fy.fyalloc);
                    items.append(Heap.Item{ .Word = fy.fyalloc.dupe(u8, w) catch @panic("oom") }) catch @panic("oom");
                    break :blk fy.heap.storeQuote(items) catch @panic("store quote failed");
                },
            };
        }

        // qhead: (q -- head)
        fn quoteHead(q: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (!isStr(q) or (fy.heap.typeOf(q) orelse Heap.ObjType.String) != .Quote) @panic("qhead expects quote");
            const qq = fy.heap.getQuote(q);
            if (qq.items.items.len == 0) @panic("qhead of empty quote");
            return itemToValue(fy, qq.items.items[0]);
        }

        // qtail: (q -- tail)
        fn quoteTail(q: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (!isStr(q) or (fy.heap.typeOf(q) orelse Heap.ObjType.String) != .Quote) @panic("qtail expects quote");
            const qq = fy.heap.getQuote(q);
            if (qq.items.items.len == 0) return q; // tail of empty is empty
            var items = std.ArrayList(Heap.Item).init(fy.fyalloc);
            items.ensureTotalCapacity(qq.items.items.len - 1) catch @panic("oom");
            for (qq.items.items[1..]) |it| switch (it) {
                .Number => |n| items.append(Heap.Item{ .Number = n }) catch @panic("oom"),
                .Float => |f| items.append(Heap.Item{ .Float = f }) catch @panic("oom"),
                .Word => |w| items.append(Heap.Item{ .Word = fy.fyalloc.dupe(u8, w) catch @panic("oom") }) catch @panic("oom"),
                .String => |s| items.append(Heap.Item{ .String = fy.fyalloc.dupe(u8, s) catch @panic("oom") }) catch @panic("oom"),
                .Quote => |qv| items.append(Heap.Item{ .Quote = qv }) catch @panic("oom"),
            };
            return fy.heap.storeQuote(items) catch @panic("heap store failed");
        }

        // qpush: (q x -- q') append element x to quote q
        fn quotePush(x: Value, q: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (!isStr(q) or (fy.heap.typeOf(q) orelse Heap.ObjType.String) != .Quote) @panic("qpush expects quote");
            const qq = fy.heap.getQuote(q);
            var items = std.ArrayList(Heap.Item).init(fy.fyalloc);
            items.ensureTotalCapacity(qq.items.items.len + 1) catch @panic("oom");
            for (qq.items.items) |it| switch (it) {
                .Number => |n| items.append(Heap.Item{ .Number = n }) catch @panic("oom"),
                .Float => |f| items.append(Heap.Item{ .Float = f }) catch @panic("oom"),
                .Word => |w| items.append(Heap.Item{ .Word = fy.fyalloc.dupe(u8, w) catch @panic("oom") }) catch @panic("oom"),
                .String => |s| items.append(Heap.Item{ .String = fy.fyalloc.dupe(u8, s) catch @panic("oom") }) catch @panic("oom"),
                .Quote => |qv| items.append(Heap.Item{ .Quote = qv }) catch @panic("oom"),
            };
            // Append x
            if (isInt(x)) {
                items.append(Heap.Item{ .Number = getInt(x) }) catch @panic("oom");
            } else {
                if (fy.heap.typeOf(x)) |t| switch (t) {
                    .String => {
                        const s = fy.heap.getString(x);
                        items.append(Heap.Item{ .String = fy.fyalloc.dupe(u8, s) catch @panic("oom") }) catch @panic("oom");
                    },
                    .Quote => {
                        items.append(Heap.Item{ .Quote = x }) catch @panic("oom");
                    },
                } else @panic("qpush: invalid heap value");
            }
            return fy.heap.storeQuote(items) catch @panic("heap store failed");
        }

        // qnil: ( -- q) create empty quote
        fn quoteNil() Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            const items = std.ArrayList(Heap.Item).init(fy.fyalloc);
            return fy.heap.storeQuote(items) catch @panic("heap store failed");
        }
        fn print(a: Value) void {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (isStr(a)) {
                if (fy.heap.typeOf(a)) |t| switch (t) {
                    .String => {
                        const s = fy.heap.getString(a);
                        outPrint("\"{s}\"\n", .{s});
                        return;
                    },
                    .Quote => {
                        // Pretty-print quote contents
                        const stdout = std.io.getStdOut().writer();
                        fy.writeQuote(stdout, a) catch {
                            outPrint("<quote>\n", .{});
                            return;
                        };
                        outPrint("\n", .{});
                        return;
                    },
                } else {}
                return;
            }
            // Everything that isn't a heap ref is an integer
            outPrint("{d}\n", .{a});
        }

        fn printHex(a: Value) void {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (isInt(a)) {
                outPrint("0x{x}\n", .{@as(u64, @bitCast(a))});
                return;
            }
            if (isStr(a)) {
                if (fy.heap.typeOf(a)) |t| switch (t) {
                    .String => {
                        const s = fy.heap.getString(a);
                        outPrint("\"{s}\"\n", .{s});
                        return;
                    },
                    .Quote => {
                        const stdout = std.io.getStdOut().writer();
                        fy.writeQuote(stdout, a) catch {
                            outPrint("<quote>\n", .{});
                            return;
                        };
                        outPrint("\n", .{});
                        return;
                    },
                } else {}
            }
            outPrint("{x}\n", .{a});
        }

        fn printNewline() void {
            outPrint("\n", .{});
        }

        fn printChar(a: Value) void {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (isStr(a)) {
                if (fy.heap.typeOf(a)) |t| switch (t) {
                    .String => {
                        const s = fy.heap.getString(a);
                        if (s.len > 0) {
                            outPrint("{c}", .{s[0]});
                        } else {
                            outPrint("<empty string>", .{});
                        }
                        return;
                    },
                    .Quote => {
                        outPrint("<quote>", .{});
                        return;
                    },
                } else {}
            }
            const i: i64 = a;
            outPrint("{c}", .{@as(u8, @intCast(i))});
        }

        fn spy(a: Value) Value {
            print(a);
            return a;
        }

        fn spyStack(base: Value, end: Value) void {
            const p: [*]Value = @ptrFromInt(@as(usize, @intCast(getInt(base))));
            const l: usize = @intCast(getInt(end - base));
            const len: usize = l / @sizeOf(Value);
            const s: []Value = p[0..len];
            outPrint("--| ", .{});
            for (2..len + 1) |v| {
                outPrint("{} ", .{s[len - v]});
            }
            outPrint("\n", .{});
        }

        fn collectGarbage(stack_ptr_raw: Value, stack_base_raw: Value) void {
            const fy_inst = @as(*Fy, @ptrFromInt(fyPtr));
            const stack_ptr: usize = @as(usize, @intCast(getInt(stack_ptr_raw)));
            const stack_base: usize = @as(usize, @intCast(getInt(stack_base_raw)));
            fy_inst.heap.gc(stack_ptr, stack_base);
        }

        fn doIf(f: Value, pred: Value) void {
            if (pred == 0) return;
            const callable = resolveCallable(f);
            if (isInt(callable)) {
                const ptr: usize = @intCast(callable);
                if (ptr == 0) return;
                const fun: *const fn () Value = @ptrFromInt(ptr);
                _ = fun();
            }
        }

        // Keep a pointer to the Fy instance for string operations
        var fyPtr: usize = 0;

        fn allocCStr(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
            var buf = try allocator.alloc(u8, bytes.len + 1);
            @memcpy(buf[0..bytes.len], bytes);
            buf[bytes.len] = 0;
            return buf;
        }

        // IO: slurp (path -- string)
        fn slurp(path: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (!isStr(path) or (fy.heap.typeOf(path) orelse Heap.ObjType.String) != .String) @panic("slurp expects string path");
            const p = fy.heap.getString(path);
            const data = std.fs.cwd().readFileAlloc(fy.fyalloc, p, std.math.maxInt(usize)) catch @panic("slurp failed");
            // Store as fy string (copies into heap-managed storage)
            const v = fy.heap.storeString(data) catch @panic("heap store failed");
            // Free the temporary buffer allocated by readFileAlloc
            fy.fyalloc.free(data);
            return v;
        }

        // IO: spit (string path -- 0)
        fn spit(path: Value, content: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (!isStr(path) or (fy.heap.typeOf(path) orelse Heap.ObjType.String) != .String) @panic("spit expects string path");
            const p = fy.heap.getString(path);
            var file = std.fs.cwd().createFile(p, .{}) catch @panic("spit: open failed");
            defer file.close();
            if (isStr(content)) {
                if ((fy.heap.typeOf(content) orelse Heap.ObjType.String) != .String) @panic("spit expects string content");
                const s = fy.heap.getString(content);
                _ = file.writeAll(s) catch @panic("spit: write failed");
            } else {
                @panic("spit expects string content");
            }
            return makeInt(0);
        }

        // IO: readln (-- string)
        fn readln() Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            var reader = std.io.getStdIn().reader();
            var buf = reader.readUntilDelimiterAlloc(fy.fyalloc, '\n', 64 * 1024) catch |e| switch (e) {
                error.EndOfStream => fy.fyalloc.alloc(u8, 0) catch @panic("oom"),
                else => @panic("readln failed"),
            };
            // Strip trailing CR if present
            if (buf.len > 0 and buf[buf.len - 1] == '\r') buf = buf[0 .. buf.len - 1];
            const v = fy.heap.storeString(buf) catch @panic("heap store failed");
            fy.fyalloc.free(buf);
            return v;
        }

        // FFI: dl-open (path -- handle)
        fn dlOpen(path: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (!isStr(path) or (fy.heap.typeOf(path) orelse Heap.ObjType.String) != .String) @panic("dl-open expects string path");
            const p = fy.heap.getString(path);
            const cbuf = allocCStr(fy.fyalloc, p) catch @panic("oom");
            defer fy.fyalloc.free(cbuf);
            const handle = posix_dl.dlopen(@ptrCast(cbuf.ptr), posix_dl.RTLD_NOW);
            if (handle == null) {
                const err = posix_dl.dlerror();
                if (err != null) {
                    const msg: [*:0]const u8 = @ptrCast(err);
                    std.debug.print("dl-open error: {s}\n", .{msg});
                }
                return makeInt(0);
            }
            const addr: usize = @intFromPtr(handle);
            return makeInt(@as(i64, @intCast(addr)));
        }

        // FFI: dl-sym (handle symbol -- fptr)
        fn dlSym(sym: Value, handle_v: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (!isInt(handle_v)) @panic("dl-sym expects handle int");
            if (!isStr(sym) or (fy.heap.typeOf(sym) orelse Heap.ObjType.String) != .String) @panic("dl-sym expects string symbol");
            const h: usize = @intCast(getInt(handle_v));
            const p: ?*anyopaque = @ptrFromInt(h);
            const s = fy.heap.getString(sym);
            const cs = allocCStr(fy.fyalloc, s) catch @panic("oom");
            defer fy.fyalloc.free(cs);
            const f = posix_dl.dlsym(p, @ptrCast(cs.ptr));
            if (f == null) return makeInt(0);
            const addr: usize = @intFromPtr(f);
            return makeInt(@as(i64, @intCast(addr)));
        }

        // FFI: dl-close (handle -- 0)
        fn dlClose(handle_v: Value) Value {
            if (!isInt(handle_v)) @panic("dl-close expects handle int");
            const h: usize = @intCast(getInt(handle_v));
            const p: ?*anyopaque = @ptrFromInt(h);
            _ = posix_dl.dlclose(p);
            return makeInt(0);
        }

        // FFI helper: cstr-new (string -- ptr)
        // Allocates with libc malloc so it can be freed by cstr-free.
        fn cstrNew(sv: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (!isStr(sv) or (fy.heap.typeOf(sv) orelse Heap.ObjType.String) != .String) @panic("cstr-new expects string");
            const s = fy.heap.getString(sv);
            const n: usize = s.len + 1;
            const mem = c_std.malloc(n);
            if (mem == null) @panic("cstr-new: malloc failed");
            const p: [*]u8 = @ptrCast(mem);
            @memcpy(p[0..s.len], s);
            p[s.len] = 0;
            return makeInt(@as(i64, @intCast(@intFromPtr(p))));
        }

        // FFI helper: cstr-free (ptr -- 0)
        fn cstrFree(ptr_v: Value) Value {
            if (!isInt(ptr_v)) @panic("cstr-free expects integer pointer");
            const up: usize = @intCast(getInt(ptr_v));
            const mem: ?*anyopaque = @ptrFromInt(up);
            c_std.free(mem);
            return makeInt(0);
        }

        // with-cstr: (string callable -- result)
        // Allocates C string, calls C-style function pointer (usize)->usize with arg ptr, frees, returns result.
        fn withCstr(callable: Value, sv: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (!isStr(sv) or (fy.heap.typeOf(sv) orelse Heap.ObjType.String) != .String) @panic("with-cstr expects string");
            const s = fy.heap.getString(sv);
            const n: usize = s.len + 1;
            const mem = c_std.malloc(n);
            if (mem == null) @panic("with-cstr: malloc failed");
            const p: [*]u8 = @ptrCast(mem);
            @memcpy(p[0..s.len], s);
            p[s.len] = 0;

            const fptr_val = resolveCallable(callable);
            if (!isInt(fptr_val)) {
                c_std.free(mem);
                @panic("with-cstr: callable did not resolve to pointer");
            }
            const fptr: usize = @intCast(getInt(fptr_val));
            const Fun = *const fn (usize) usize;
            const fun: Fun = @ptrFromInt(fptr);
            const res = fun(@intFromPtr(p));
            c_std.free(mem);
            return makeInt(@as(i64, @intCast(res)));
        }

        // with-cstr-f: (string fptr quote -- result)
        // Like with-cstr-q but supplies both ptr and fptr to the quote running on an isolated trampoline stack.
        fn withCstrF(quote: Value, fptr_val: Value, sv: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (!isStr(sv) or (fy.heap.typeOf(sv) orelse Heap.ObjType.String) != .String) @panic("with-cstr-f expects string");
            if (!isInt(fptr_val)) @panic("with-cstr-f expects integer function pointer");
            const s = fy.heap.getString(sv);
            const n: usize = s.len + 1;
            const mem = c_std.malloc(n);
            if (mem == null) @panic("with-cstr-f: malloc failed");
            const p: [*]u8 = @ptrCast(mem);
            @memcpy(p[0..s.len], s);
            p[s.len] = 0;

            const qptr_val = resolveCallable(quote);
            if (!isInt(qptr_val)) {
                c_std.free(mem);
                @panic("with-cstr-f: quote did not resolve to pointer");
            }
            const qptr: usize = @intCast(getInt(qptr_val));
            const fptr: usize = @intCast(getInt(fptr_val));
            const adapt = getAdapt2(fy);

            const tramp_end_aligned: usize = fy.tramp_stack_top;
            const base_val: Value = @bitCast(@as(i64, @intCast(tramp_end_aligned)));
            const end_val: Value = base_val;
            const head_val: Value = makeInt(@as(i64, @intCast(@intFromPtr(p)))); // ptr as head (top)
            const acc_val: Value = makeInt(@as(i64, @intCast(fptr))); // fptr as acc (below)

            const out = adapt(qptr, base_val, end_val, head_val, acc_val);
            c_std.free(mem);
            return out;
        }

        // with-cstr-q: (string quote -- result)
        // Executes a quote with an isolated trampoline data stack like map/reduce do,
        // pushing the C string pointer as the only data input. The quote body is free to
        // use ccall1 expecting (fptr ptr) on the stack if it duplicates fptr inside the quote.
        // To support the common pattern [ ccall1 ] for C functions, we supply (ptr,fptr) on the
        // trampoline stack by passing fptr as the "acc" parameter to adapt2 while the head is ptr.
        fn withCstrQ(quote: Value, sv: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (!isStr(sv) or (fy.heap.typeOf(sv) orelse Heap.ObjType.String) != .String) @panic("with-cstr-q expects string");
            const s = fy.heap.getString(sv);
            const n: usize = s.len + 1;
            const mem = c_std.malloc(n);
            if (mem == null) @panic("with-cstr-q: malloc failed");
            const p: [*]u8 = @ptrCast(mem);
            @memcpy(p[0..s.len], s);
            p[s.len] = 0;

            const fptr_val = resolveCallable(quote);
            if (!isInt(fptr_val)) {
                c_std.free(mem);
                @panic("with-cstr-q: quote did not resolve to pointer");
            }
            const fptr: usize = @intCast(getInt(fptr_val));
            const adapt = getAdapt2(fy);

            const tramp_end_aligned: usize = fy.tramp_stack_top;
            const base_val: Value = @bitCast(@as(i64, @intCast(tramp_end_aligned)));
            const end_val: Value = base_val;
            const head_val: Value = makeInt(@as(i64, @intCast(@intFromPtr(p))));
            const acc_val: Value = makeInt(@as(i64, @intCast(fptr)));

            const out = adapt(fptr, base_val, end_val, head_val, acc_val);
            c_std.free(mem);
            return out;
        }

        // PAC-safe 1-arg call: (... fptr a -- ret)
        fn ccall1pac(a: Value, fptr: Value) Value {
            // Note: parameter order maps to stack top first; expects a above fptr
            if ((fptr & TAG_MASK) != TAG_INT) @panic("ccall1pac expects integer function pointer");
            if ((a & TAG_MASK) != TAG_INT) @panic("ccall1pac expects integer/pointer argument");
            const faddr: usize = @intCast(getInt(fptr));
            const arg0: usize = @intCast(getInt(a));
            const Fun = *const fn (usize) usize;
            const fun: Fun = @ptrFromInt(faddr);
            const res = fun(arg0);
            return makeInt(@as(i64, @intCast(res)));
        }

        // String concatenation (stack order: ... a b -> concat(a,b))
        // Due to calling convention, x0 holds top-of-stack (b) and x1 holds next (a)
        fn strConcat(b: Value, a: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            return fy.heap.concat(a, b) catch @panic("String concatenation failed");
        }

        // String length
        fn strLen(a: Value) Value {
            if (!isStr(a)) {
                @panic("Expected string for length");
            }
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            return fy.heap.length(a);
        }

        // Type checking
        fn isString(a: Value) Value {
            if (!isStr(a)) return makeInt(0);
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            const t = fy.heap.typeOf(a) orelse return makeInt(0);
            return makeInt(@as(i64, @intFromBool(t == .String)));
        }

        fn isInteger(a: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (!isStr(a)) return makeInt(1);
            const t = fy.heap.typeOf(a);
            return makeInt(@as(i64, @intFromBool(t == null)));
        }

        // Float builtins — floats are f64 bitcast into i64 Value
        fn floatAdd(b: Value, a: Value) Value {
            return makeFloat(getFloat(a) + getFloat(b));
        }
        fn floatSub(b: Value, a: Value) Value {
            return makeFloat(getFloat(a) - getFloat(b));
        }
        fn floatMul(b: Value, a: Value) Value {
            return makeFloat(getFloat(a) * getFloat(b));
        }
        fn floatDiv(b: Value, a: Value) Value {
            return makeFloat(getFloat(a) / getFloat(b));
        }
        fn floatLt(b: Value, a: Value) Value {
            return makeInt(@as(i64, @intFromBool(getFloat(a) < getFloat(b))));
        }
        fn floatGt(b: Value, a: Value) Value {
            return makeInt(@as(i64, @intFromBool(getFloat(a) > getFloat(b))));
        }
        fn floatEq(b: Value, a: Value) Value {
            return makeInt(@as(i64, @intFromBool(getFloat(a) == getFloat(b))));
        }
        fn intToFloat(a: Value) Value {
            return makeFloat(@as(f64, @floatFromInt(getInt(a))));
        }
        fn floatToInt(a: Value) Value {
            return makeInt(@as(i64, @intFromFloat(getFloat(a))));
        }
        fn floatPrint(a: Value) void {
            const f = getFloat(a);
            if (f == @trunc(f) and !std.math.isNan(f) and !std.math.isInf(f)) {
                outPrint("{d}.0\n", .{@as(i64, @intFromFloat(f))});
            } else {
                outPrint("{d}\n", .{f});
            }
        }
        fn floatNeg(a: Value) Value {
            return makeFloat(-getFloat(a));
        }

        // Resolve a callable: if int pointer, return as-is; if quote, JIT and cache
        fn resolveCallable(v: Value) Value {
            if (isInt(v)) return v;
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (fy.heap.typeOf(v)) |t| switch (t) {
                .String => return v,
                .Quote => {
                    var q = fy.heap.getQuote(v);
                    if (q.cached_ptr) |p| return makeInt(@as(i64, @intCast(p)));
                    const code = fy.compileQuote(q) catch @panic("compile quote failed");
                    const ptr: usize = @intFromPtr((fy.jit(code) catch @panic("jit failed")).call);
                    q.cached_ptr = ptr;
                    return makeInt(@as(i64, @intCast(ptr)));
                },
            } else return v;
        }

        // Adapters: self-contained trampolines that save/restore x21/x22
        // and set up their own data stack from base/end parameters.
        var adapt1: ?*const fn (usize, Value, Value, Value) Value = null;
        var adapt2: ?*const fn (usize, Value, Value, Value, Value) Value = null;

        fn getAdapt1(fy: *Fy) *const fn (usize, Value, Value, Value) Value {
            if (adapt1) |t| return t;
            const code = &[_]u32{
                // x0=fptr, x1=base, x2=end, x3=a
                Asm.@"stp x29, x30, [sp, #0x10]!",
                Asm.@"stp x21, x22, [sp, #0x10]!",
                Asm.@"mov x21, x1",
                Asm.@"mov x22, x2",
                Asm.@"mov x16, x0",
                // seed guard slot so depth = 0 on empty stack
                Asm.@"mov x0, #0",
                Asm.@".push x0",
                Asm.@"mov x0, x3",
                Asm.@".push x0",
                Asm.@"blr Xn"(16),
                Asm.@".pop x0",
                // Optionally clean guard slot if still present (value 0)
                Asm.@".pop x1",
                Asm.@"cbnz Xn, offset"(1, 2),
                Asm.@"b offset"(2),
                Asm.@".push x1",
                Asm.@"ldp x21, x22, [sp], #0x10",
                Asm.@"ldp x29, x30, [sp], #0x10",
                Asm.ret,
            };
            const buf = fy.fyalloc.dupe(u32, code[0..]) catch @panic("oom adapt1");
            const fnptr = fy.jit(buf) catch @panic("jit adapt1 failed");
            const addr: usize = @intFromPtr(fnptr.call);
            const typed: *const fn (usize, Value, Value, Value) Value = @ptrFromInt(addr);
            adapt1 = typed;
            return typed;
        }

        fn getAdapt2(fy: *Fy) *const fn (usize, Value, Value, Value, Value) Value {
            if (adapt2) |t| return t;
            const code = &[_]u32{
                // x0=fptr, x1=base, x2=end, x3=head, x4=acc
                Asm.@"stp x29, x30, [sp, #0x10]!",
                Asm.@"stp x21, x22, [sp, #0x10]!",
                Asm.@"mov x21, x1",
                Asm.@"mov x22, x2",
                Asm.@"mov x16, x0",
                // seed guard slot so depth = 0 on empty stack
                Asm.@"mov x0, #0",
                Asm.@".push x0",
                Asm.@"mov x0, x4",
                Asm.@".push x0",
                Asm.@"mov x0, x3",
                Asm.@".push x0",
                Asm.@"blr Xn"(16),
                Asm.@".pop x0",
                // Optionally clean guard slot if still present (value 0)
                Asm.@".pop x1",
                Asm.@"cbnz Xn, offset"(1, 2),
                Asm.@"b offset"(2),
                Asm.@".push x1",
                Asm.@"ldp x21, x22, [sp], #0x10",
                Asm.@"ldp x29, x30, [sp], #0x10",
                Asm.ret,
            };
            const buf = fy.fyalloc.dupe(u32, code[0..]) catch @panic("oom adapt2");
            const fnptr = fy.jit(buf) catch @panic("jit adapt2 failed");
            const addr: usize = @intFromPtr(fnptr.call);
            const typed: *const fn (usize, Value, Value, Value, Value) Value = @ptrFromInt(addr);
            adapt2 = typed;
            return typed;
        }

        // Adapter pointer helpers were used by a legacy ASM map loop and are removed.

        // General map: list f -- list' using adapter to call any callable (word or quote)
        fn bmap(f: Value, list: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (!isStr(list) or (fy.heap.typeOf(list) orelse Heap.ObjType.String) != .Quote) @panic("map expects quote");
            const fptr_val = resolveCallable(f);
            if (!isInt(fptr_val)) @panic("map expects callable");
            const fptr: usize = @intCast(getInt(fptr_val));
            const adapt = getAdapt1(fy);
            var items = std.ArrayList(Heap.Item).init(fy.fyalloc);
            const q = fy.heap.getQuote(list);
            for (q.items.items) |it| {
                // Debug hook (set FY_DEBUG_ADAPTER=1 to enable)
                if (std.posix.getenvZ("FY_DEBUG_ADAPTER")) |_| {
                    std.debug.print("[bmap] it={any}\n", .{it});
                }
                const arg = itemToValue(fy, it);
                // Use isolated trampoline stack (aligned) for safety
                const tramp_end_aligned: usize = fy.tramp_stack_top;
                const base_val: Value = @bitCast(@as(i64, @intCast(tramp_end_aligned)));
                const end_val: Value = base_val;
                if (std.posix.getenvZ("FY_DEBUG_ADAPTER")) |_| {
                    std.debug.print("[bmap] fptr=0x{x} base=0x{x} end=0x{x} arg={any}\n", .{ fptr, tramp_end_aligned, tramp_end_aligned, arg });
                }
                const mapped = adapt(fptr, base_val, end_val, arg);
                if (std.posix.getenvZ("FY_DEBUG_ADAPTER")) |_| {
                    std.debug.print("[bmap] -> mapped={any}\n", .{mapped});
                }
                if (isStr(mapped)) {
                    if (fy.heap.typeOf(mapped)) |t| switch (t) {
                        .String => {
                            const s = fy.heap.getString(mapped);
                            items.append(Heap.Item{ .String = fy.fyalloc.dupe(u8, s) catch @panic("oom") }) catch @panic("oom");
                        },
                        .Quote => items.append(Heap.Item{ .Quote = mapped }) catch @panic("oom"),
                    } else @panic("map: invalid heap value");
                } else {
                    const n: i64 = mapped; // treat any non-heap value as integer payload
                    items.append(Heap.Item{ .Number = n }) catch @panic("oom");
                }
            }
            return fy.heap.storeQuote(items) catch @panic("heap store failed");
        }

        // General reduce: acc list f -- result using adapter to call any callable
        fn breduce(f: Value, list: Value, acc0: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            if (!isStr(list) or (fy.heap.typeOf(list) orelse Heap.ObjType.String) != .Quote) @panic("reduce expects quote");
            const fptr_val = resolveCallable(f);
            if (!isInt(fptr_val)) @panic("reduce expects callable");
            const fptr: usize = @intCast(getInt(fptr_val));
            const adapt = getAdapt2(fy);
            var acc = acc0;
            const q = fy.heap.getQuote(list);
            for (q.items.items) |it| {
                if (std.posix.getenvZ("FY_DEBUG_ADAPTER")) |_| {
                    std.debug.print("[breduce] it={any} acc={any}\n", .{ it, acc });
                }
                const head = itemToValue(fy, it);
                const tramp_end_aligned: usize = fy.tramp_stack_top;
                const base_val: Value = @bitCast(@as(i64, @intCast(tramp_end_aligned)));
                const end_val: Value = base_val;
                if (std.posix.getenvZ("FY_DEBUG_ADAPTER")) |_| {
                    std.debug.print("[breduce] fptr=0x{x} base=0x{x} end=0x{x} head={any} acc={any}\n", .{ fptr, tramp_end_aligned, tramp_end_aligned, head, acc });
                }
                acc = adapt(fptr, base_val, end_val, head, acc);
                if (std.posix.getenvZ("FY_DEBUG_ADAPTER")) |_| {
                    std.debug.print("[breduce] -> acc'={any}\n", .{acc});
                }
            }
            return acc;
        }
    };

    const words = std.StaticStringMap(Word).initComptime(.{
        // a b -- a+b
        .{ "+", binOp(Asm.@"add x0, x0, x1", false) },
        // a b -- a-b
        .{ "-", binOp(Asm.@"sub x0, x1, x0", true) },
        // a b -- a-b
        .{ "!-", binOp(Asm.@"sub x0, x1, x0", false) },
        // a b -- a*b
        .{ "*", binOp(Asm.@"mul x0, x0, x1", false) },
        // a b -- a&b
        .{ "&", binOp(Asm.@"and x0, x0, x1", false) },
        // a b -- a|b
        .{ "or", binOp(Asm.@"orr x0, x0, x1", false) },
        // a b -- a^b
        .{ "xor", binOp(Asm.@"eor x0, x0, x1", false) },
        // a b -- a<<b
        .{ "<<", binOp(Asm.@"lsl x0, x1, x0", false) },
        // a b -- a>>b
        .{ ">>", binOp(Asm.@"lsr x0, x1, x0", false) },
        // a b -- a/b
        .{ "/", binOp(Asm.@"sdiv x0, x1, x0", true) },
        .{ "=", cmpOp(Asm.@"beq #2") },
        .{ "!=", cmpOp(Asm.@"bne #2") },
        .{ ">", cmpOp(Asm.@"blt #2") },
        .{ "<", cmpOp(Asm.@"bgt #2") },
        .{ ">=", cmpOp(Asm.@"ble #2") },
        .{ "<=", cmpOp(Asm.@"bge #2") },
        // a -- a a
        .{ "dup", inlineWord(&[_]u32{ Asm.@".pop x0", Asm.@".push x0", Asm.@".push x0" }, 1, 2) },
        // a b -- a b a b
        .{ "dup2", inlineWord(&[_]u32{ Asm.@".pop x0, x1", Asm.@".push x1, x0", Asm.@".push x1, x0" }, 2, 4) },
        // a b -- b a
        .{ "swap", inlineWord(&[_]u32{ Asm.@".pop x0, x1", Asm.@".push x0, x1" }, 2, 2) },
        // a --
        .{ "drop", inlineWord(&[_]u32{Asm.@".pop x0"}, 1, 0) },
        // a b --
        .{ "drop2", inlineWord(&[_]u32{Asm.@".pop x0, x1"}, 2, 0) },
        // a b -- a b a
        .{ "over", inlineWord(&[_]u32{ Asm.@".pop x0, x1", Asm.@".push x1, x0", Asm.@".push x1" }, 2, 3) },
        // c d a b -- c d a b c d
        .{ "over2", inlineWord(&[_]u32{
            Asm.@".pop x0, x1",
            Asm.@".pop x2, x3",
            Asm.@".push x2, x3",
            Asm.@".push x1, x0",
            Asm.@".push x2, x3",
        }, 4, 6) },
        // a b -- b
        .{ "nip", inlineWord(&[_]u32{ Asm.@".pop x0, x1", Asm.@".push x0" }, 2, 1) },
        // a b -- b a b
        .{ "tuck", inlineWord(&[_]u32{ Asm.@".pop x0, x1", Asm.@".push x0, x1", Asm.@".push x0" }, 2, 3) },
        // a b c -- b c a
        .{
            "rot", inlineWord(&[_]u32{
                Asm.@".pop x0", // pop c
                Asm.@".pop x1", // pop b
                Asm.@".pop Xn"(2), // pop a using the helper function
                Asm.@".push x1", // push b
                Asm.@".push x0", // push c
                Asm.@".push Xn"(2), // push a
            }, 3, 3),
        },
        // a b c -- c a b
        .{
            "-rot", inlineWord(&[_]u32{
                Asm.@".pop x0", // pop c
                Asm.@".pop x1", // pop b
                Asm.@".pop Xn"(2), // pop a
                Asm.@".push x0", // push c
                Asm.@".push Xn"(2), // push a
                Asm.@".push x1", // push b
            }, 3, 3),
        },
        // -- a
        .{ "depth", inlineWord(&[_]u32{ Asm.@"sub x0, x22, x21", Asm.@"asr x0, x0, #3", Asm.@"sub x0, x0, #1", Asm.@".push x0" }, 0, 1) },
        // Retain stack (return stack) operations
        // x -- (to retain)
        .{ ">r", inlineWord(&[_]u32{ Asm.@".pop x0", Asm.@".rpush x0" }, 1, 0) },
        // -- x (from retain)
        .{ "r>", inlineWord(&[_]u32{ Asm.@".rpop x0", Asm.@".push x0" }, 0, 1) },
        // -- x (copy from retain without popping)
        .{ "r@", inlineWord(&[_]u32{ Asm.@".rpop x0", Asm.@".rpush x0", Asm.@".push x0" }, 0, 1) },
        // x f -- x
        .{
            "dip", .{
                .code = &[_]u32{
                    Asm.@".pop x0, x1", // x0=function, x1=value
                    Asm.@".rpush x1", // save value before calling resolver (which may clobber x1)
                    Asm.CALLSLOT, // resolve function/quote in x0
                    Asm.@"blr Xn"(0), // call resolved pointer
                    Asm.@".rpop x1", // restore saved value
                    Asm.@".push x1",
                },
                .c = 2,
                .p = 1,
                .callSlot0 = &Builtins.resolveCallable,
            },
        },
        // a --
        .{ ".", fnToWord(Builtins.print) },
        // --
        .{ ".nl", fnToWord(Builtins.printNewline) },
        // a --
        .{ ".c", fnToWord(Builtins.printChar) },
        // a --
        .{ ".hex", fnToWord(Builtins.printHex) },
        // a -- a
        .{ "spy", fnToWord(Builtins.spy) },
        // --
        .{ ".dbg", .{
            .code = &[_]u32{ Asm.@"mov x0, x21", Asm.@"mov x1, x22", Asm.CALLSLOT },
            .c = 0,
            .p = 0,
            .callSlot0 = &Builtins.spyStack,
        } },
        // -- (trigger garbage collection)
        .{ "gc", .{
            .code = &[_]u32{ Asm.@"mov x0, x21", Asm.@"mov x1, x22", Asm.CALLSLOT },
            .c = 0,
            .p = 0,
            .callSlot0 = &Builtins.collectGarbage,
        } },
        // a -- a + 1
        .{ "1+", inlineWord(&[_]u32{ Asm.@".pop x0", Asm.@"add x0, x0, #1", Asm.@".push x0" }, 1, 1) },
        // a -- a - 1
        .{ "1-", inlineWord(&[_]u32{ Asm.@".pop x0", Asm.@"sub x0, x0, #1", Asm.@".push x0" }, 1, 1) },
        // f -- !f (boolean not)
        .{ "not", inlineWord(&[_]u32{
            Asm.@".pop x0",
            Asm.@"cbz Xn, offset"(0, 2),
            Asm.@"mov x0, #0",
            Asm.@"b offset"(1),
            Asm.@"mov x0, #1",
            Asm.@".push x0",
        }, 1, 1) },
        // ... f -- f(...)
        .{ "do", .{ .code = &[_]u32{ Asm.@".pop x0", Asm.CALLSLOT, Asm.@"blr Xn"(0) }, .c = 0, .p = 0, .callSlot0 = &Builtins.resolveCallable } },
        // ... ft -- ft(...) | ...
        .{ "do?", fnToWord(Builtins.doIf) },
        // ... c ft ff -- ft(...) | ff(...)
        .{ "ifte", .{ .code = &[_]u32{
            Asm.@".pop x1, x0",
            Asm.@".pop Xn"(2),
            Asm.@"cmp x2, #0",
            Asm.@"csel x0, x0, x1, ne",
            Asm.CALLSLOT,
            Asm.@"blr Xn"(0),
        }, .c = 0, .p = 1, .callSlot0 = &Builtins.resolveCallable } },
        // ... n f -- ...
        .{
            "dotimes", .{
                .code = &[_]u32{
                    Asm.@".pop x0", // function (or quote)
                    Asm.CALLSLOT, // resolve to pointer in x0
                    Asm.@"mov x1, x0", // keep pointer in x1
                    Asm.@".pop x0", // counter in x0
                    Asm.@"cbz Xn, offset"(0, 9), // if zero, jump to end
                    // loop start
                    Asm.@".rpush x0", // save counter
                    Asm.@".rpush x1", // save func ptr
                    Asm.@"blr Xn"(1), // call func in x1
                    Asm.@".rpop x1", // restore func ptr
                    Asm.@".rpop x0", // restore counter
                    // Decrement counter and loop
                    Asm.@"sub x0, x0, #1",
                    Asm.@"cbz Xn, offset"(0, 2), // if zero, skip branch
                    Asm.@"b offset"(-8), // back to loop start
                },
                .c = 2,
                .p = 0,
                .callSlot0 = &Builtins.resolveCallable,
            },
        },
        // ... f -- ...
        // repeat the quote until the top of the stack is 0
        .{
            "repeat", .{
                .code = &[_]u32{
                    Asm.@".pop x0", // pop quote
                    Asm.CALLSLOT, // resolve to pointer
                    Asm.@".rpush x0", // save pointer on return stack
                    // loop start: peek predicate (pop+push to preserve)
                    Asm.@".pop x1",
                    Asm.@".push x1",
                    Asm.@"cbz Xn, offset"(1, 5), // if zero -> exit at final rpop
                    // call quote
                    Asm.@".rpop x0",
                    Asm.@".rpush x0",
                    Asm.@"blr x0",
                    Asm.@"b offset"(-6), // back to peek predicate (to pop x1)
                    // exit path
                    Asm.@".rpop x0", // discard saved pointer
                },
                .c = 1,
                .p = 0,
                .callSlot0 = &Builtins.resolveCallable,
            },
        },
        // recur --
        .{ "recur", inlineWord(&[_]u32{Asm.RECUR}, 0, 0) },
        // String operations
        .{ "s.", fnToWord(Builtins.print) }, // Print string or number
        .{ "s+", fnToWord(Builtins.strConcat) }, // Concatenate strings
        // Quote operations
        .{ "cat", fnToWord(Builtins.quoteConcat) }, // Concatenate two quotes
        .{ "qcat", fnToWord(Builtins.quoteConcat) }, // Alias for clarity
        .{ "qlen", fnToWord(Builtins.quoteLen) },
        .{ "qempty?", fnToWord(Builtins.quoteEmpty) },
        .{ "qhead", fnToWord(Builtins.quoteHead) },
        .{ "qtail", fnToWord(Builtins.quoteTail) },
        .{ "qpush", fnToWord(Builtins.quotePush) },
        .{ "qnil", fnToWord(Builtins.quoteNil) },

        // Reduce: acc list f -- result (Zig builtin)
        .{ "reduce", .{ .code = &[_]u32{ Asm.@".pop x0", Asm.@".pop x1", Asm.@".pop x2", Asm.CALLSLOT3, Asm.@".push x0" }, .c = 3, .p = 1, .callSlot3 = &Builtins.breduce } },

        // Old ASM-loop version of map removed in favor of Zig builtin bmap.
        // Map: list f -- list' (Zig builtin)
        .{ "map", fnToWord(Builtins.bmap) },
        .{ "slen", fnToWord(Builtins.strLen) }, // String length
        .{ "string?", fnToWord(Builtins.isString) }, // Check if value is string
        .{ "int?", fnToWord(Builtins.isInteger) }, // Check if value is integer

        // Float arithmetic and conversion
        .{ "f+", fnToWord(Builtins.floatAdd) },
        .{ "f-", fnToWord(Builtins.floatSub) },
        .{ "f*", fnToWord(Builtins.floatMul) },
        .{ "f/", fnToWord(Builtins.floatDiv) },
        .{ "f<", fnToWord(Builtins.floatLt) },
        .{ "f>", fnToWord(Builtins.floatGt) },
        .{ "f=", fnToWord(Builtins.floatEq) },
        .{ "fneg", fnToWord(Builtins.floatNeg) },
        .{ "i>f", fnToWord(Builtins.intToFloat) },
        .{ "f>i", fnToWord(Builtins.floatToInt) },
        .{ "f.", fnToWord(Builtins.floatPrint) },

        // IO
        .{ "slurp", fnToWord(Builtins.slurp) }, // (path -- string)
        .{ "spit", fnToWord(Builtins.spit) }, // (string path -- 0)
        .{ "readln", fnToWord(Builtins.readln) }, // (-- string)

        // FFI: dlopen/dlsym/dlclose
        .{ "dl-open", fnToWord(Builtins.dlOpen) }, // (path -- handle)
        .{ "dl-sym", fnToWord(Builtins.dlSym) }, // (handle symbol -- fptr)
        .{ "dl-close", fnToWord(Builtins.dlClose) }, // (handle -- 0)
        .{ "cstr-new", fnToWord(Builtins.cstrNew) }, // (string -- ptr)
        .{ "cstr-free", fnToWord(Builtins.cstrFree) }, // (ptr -- 0)
        .{ "with-cstr", fnToWord(Builtins.withCstr) }, // (string callable -- result)
        .{ "with-cstr-q", fnToWord(Builtins.withCstrQ) }, // (string quote -- result)
        .{ "with-cstr-f", fnToWord(Builtins.withCstrF) }, // (string fptr quote -- result)

        // FFI: generic calls with 0..3 args; expects stack: fptr [a [b [c]]]
        .{
            "ccall0", inlineWord(&[_]u32{
                Asm.@".pop Xn"(16), // fptr -> x16
                Asm.@"blr Xn"(16), // call
                Asm.@".push x0", // return value
            }, 1, 1),
        },
        .{
            "ccall1", inlineWord(&[_]u32{
                Asm.@".pop x0", // a
                Asm.@".pop Xn"(16), // fptr
                Asm.@"blr Xn"(16),
                Asm.@".push x0",
            }, 2, 1),
        },
        // PAC-safe variant implemented in Zig to leverage compiler-emitted authenticated branch
        .{ "ccall1pac", fnToWord(Builtins.ccall1pac) },
        .{
            "ccall2", inlineWord(&[_]u32{
                Asm.@".pop x1, x0", // x0=a (NOS), x1=b (TOS)
                Asm.@".pop Xn"(16), // fptr
                Asm.@"blr Xn"(16),
                Asm.@".push x0",
            }, 3, 1),
        },
        .{
            "ccall3", inlineWord(&[_]u32{
                Asm.@".pop x0, x1", // c, b
                Asm.@".pop Xn"(2), // a -> x2
                Asm.@".push Xn"(2), // a
                Asm.@".push x1", // b
                Asm.@".push x0", // c
                Asm.@".pop Xn"(2), // x2 = c
                Asm.@".pop x1, x0", // x1=b, x0=a
                Asm.@".pop Xn"(16), // fptr
                Asm.@"blr Xn"(16),
                Asm.@".push x0",
            }, 4, 1),
        },

        // Alias: n q times → n q dotimes
        .{ "times", inlineWord(&[_]u32{ Asm.@".pop x0", Asm.@".pop x1", Asm.@".push x1", Asm.@".push x0", Asm.@".pop x1", Asm.@".pop x0" }, 2, 0) },
    });

    fn findWord(self: *Fy, word: []const u8) ?Word {
        return self.userWords.get(word) orelse words.get(word);
    }

    // parseromptime c: usize, comptime p: usize
    const Parser = struct {
        code: []const u8,
        pos: usize,
        autoclose: bool,

        const Token = union(enum) {
            Number: i64,
            Float: f64,
            Word: []const u8,
            String: []const u8,
        };

        fn init(code: []const u8) Parser {
            return Parser{
                .code = code,
                .pos = 0,
                .autoclose = false,
            };
        }

        fn isDigit(c: u8) bool {
            return c >= '0' and c <= '9';
        }

        fn isWhitespace(c: u8) bool {
            return c == ' ' or c == '\n' or c == '\r' or c == '\t';
        }

        fn nextToken(self: *Parser) Compiler.Error!?Token {
            while (self.pos < self.code.len and isWhitespace(self.code[self.pos])) {
                if (self.autoclose) {
                    self.autoclose = false;
                    return Token{ .Word = Word.QUOTE_END };
                }
                self.pos += 1;
            }
            if (self.pos >= self.code.len) {
                return null;
            }
            var c = self.code[self.pos];
            const start = self.pos;
            if (c == '(') {
                self.pos += 1;
                var depth: usize = 1;
                while (self.pos < self.code.len and depth > 0) {
                    switch (self.code[self.pos]) {
                        '(' => depth += 1,
                        ')' => depth -= 1,
                        else => {},
                    }
                    self.pos += 1;
                }
                if (depth != 0) {
                    return Compiler.Error.UnbalancedParentheses;
                }
                return self.nextToken();
            }
            if (c == '\'') {
                self.pos += 1;
                if (self.pos >= self.code.len) {
                    return Compiler.Error.UnexpectedEndOfInput;
                }
                c = self.code[self.pos];
                const charValue = @as(i64, c);
                self.pos += 1;
                return Token{ .Number = charValue };
            }
            if (c == ':') {
                if (self.pos + 1 < self.code.len and self.code[self.pos + 1] == ':') {
                    self.pos += 2;
                    return Token{ .Word = "::" };
                }
                self.pos += 1;
                return Token{ .Word = Word.DEFINE };
            }
            if (c == ';') {
                self.pos += 1;
                return Token{ .Word = Word.END };
            }
            if (c == '\\') {
                self.pos += 1;
                self.autoclose = true;
                return Token{ .Word = Word.QUOTE_OPEN };
            }
            if (c == '[') {
                self.pos += 1;
                return Token{ .Word = Word.QUOTE_OPEN };
            }
            if (c == ']') {
                self.pos += 1;
                return Token{ .Word = Word.QUOTE_END };
            }
            if (c == '"') {
                self.pos += 1;
                const strStart = self.pos;
                while (self.pos < self.code.len and self.code[self.pos] != '"') {
                    if (self.code[self.pos] == '\\') {
                        self.pos += 1;
                    }
                    self.pos += 1;
                }
                if (self.pos >= self.code.len) {
                    return Compiler.Error.UnterminatedString;
                }
                const strEnd = self.pos;
                self.pos += 1;
                return Token{ .String = self.code[strStart..strEnd] };
            }
            if (isDigit(c) or c == '-') {
                var negative = false;
                var number = true;
                if (c == '-') {
                    negative = true;
                    self.pos += 1;
                    if (self.pos >= self.code.len or !isDigit(self.code[self.pos])) {
                        number = false;
                    }
                }

                if (number) {
                    while (self.pos < self.code.len and isDigit(self.code[self.pos])) {
                        self.pos += 1;
                    }
                    // Check for decimal point → float literal
                    if (self.pos < self.code.len and self.code[self.pos] == '.' and
                        self.pos + 1 < self.code.len and isDigit(self.code[self.pos + 1]))
                    {
                        self.pos += 1; // skip '.'
                        while (self.pos < self.code.len and isDigit(self.code[self.pos])) {
                            self.pos += 1;
                        }
                        const fval = std.fmt.parseFloat(f64, self.code[start..self.pos]) catch 0.0;
                        return Token{ .Float = fval };
                    }
                    const value = std.fmt.parseInt(i64, self.code[start..self.pos], 10) catch 2137;
                    return Token{ .Number = value };
                }
            }
            while (self.pos < self.code.len and !isWhitespace(self.code[self.pos]) and self.code[self.pos] != ';' and self.code[self.pos] != ']') {
                self.pos += 1;
            }

            return Token{ .Word = self.code[start..self.pos] };
        }

        /// Read next whitespace-delimited token as raw text, bypassing number/punctuation parsing.
        /// Used by sig: which needs to read signatures like "4:v", ":v", "iif4:v" verbatim.
        fn nextRawWord(self: *Parser) ?[]const u8 {
            while (self.pos < self.code.len and isWhitespace(self.code[self.pos])) {
                self.pos += 1;
            }
            if (self.pos >= self.code.len) return null;
            const start = self.pos;
            while (self.pos < self.code.len and !isWhitespace(self.code[self.pos]) and self.code[self.pos] != ';' and self.code[self.pos] != ']') {
                self.pos += 1;
            }
            return self.code[start..self.pos];
        }
    };

    // compiler
    const Compiler = struct {
        parser: *Parser,
        code: std.ArrayList(u32),
        relocations: std.ArrayList(Relocation),
        prev: u32 = 0,
        fy: *Fy,
        // Name of the word currently being defined (for self-recursion)
        currentDef: ?[]const u8 = null,
        // Base directory for resolving relative paths in include/import
        base_dir: ?[]const u8 = null,
        // Namespace prefix for import (e.g., "raylib:" → all defs become "raylib:word")
        namespace: ?[]const u8 = null,

        const Relocation = struct {
            code_offset: usize, // index into code[] where BL placeholder lives
            target_addr: usize, // absolute byte address in image (or SELF_CALL)
        };
        const SELF_CALL: usize = std.math.maxInt(usize);

        const Error = error{
            ExpectedWord,
            UnexpectedEndOfInput,
            UnknownWord,
            OutOfMemory,
            UnbalancedParentheses,
            UnterminatedString,
        };

        // Helper function to handle string escapes
        fn unescapeString(allocator: std.mem.Allocator, escaped: []const u8) ![]u8 {
            const len = escaped.len;
            var result = try allocator.alloc(u8, len); // Allocate max possible size
            var i: usize = 0;
            var j: usize = 0;

            while (i < len) {
                if (escaped[i] == '\\' and i + 1 < len) {
                    i += 1;
                    switch (escaped[i]) {
                        'n' => result[j] = '\n',
                        'r' => result[j] = '\r',
                        't' => result[j] = '\t',
                        '\\' => result[j] = '\\',
                        '"' => result[j] = '"',
                        '0' => result[j] = 0,
                        else => result[j] = escaped[i],
                    }
                } else {
                    result[j] = escaped[i];
                }
                i += 1;
                j += 1;
            }

            // Shrink to actual size
            return allocator.realloc(result, j);
        }

        fn init(fy: *Fy, parser: *Parser) Compiler {
            return Compiler{
                .code = std.ArrayList(u32).init(fy.fyalloc),
                .relocations = std.ArrayList(Relocation).init(fy.fyalloc),
                .parser = parser,
                .fy = fy,
                .currentDef = null,
            };
        }

        fn deinit(self: *Compiler) void {
            self.code.deinit();
            self.relocations.deinit();
        }

        fn emit(self: *Compiler, instr: u32) !void {
            try self.code.append(instr);
            self.prev = instr;
        }

        fn emitWord(self: *Compiler, word: Word) !void {
            // User words compiled into image: emit BL relocation instead of inlining
            if (word.image_addr) |addr| {
                try self.emitBL(addr);
                return;
            }
            // Builtins: inline the code as before
            var i: usize = 0;
            const pos = self.code.items.len;
            while (true) {
                const instr = word.code[i];
                if (instr == Asm.CALLSLOT or instr == Asm.CALLSLOT0) {
                    const fun: u64 = @intFromPtr(word.callSlot0);
                    try self.emitPtr(fun, Asm.REGCALL);
                    try self.emitCall(Asm.REGCALL);
                    i += 1;
                } else if (instr == Asm.CALLSLOT3) {
                    const fun: u64 = @intFromPtr(word.callSlot3);
                    try self.emitPtr(fun, Asm.REGCALL);
                    try self.emitCall(Asm.REGCALL);
                    i += 1;
                } else if (instr == Asm.RECUR) {
                    try self.emitJump(pos);
                    i += 1;
                } else {
                    try self.emit(instr);
                    i += 1;
                }
                if (i >= word.code.len) {
                    break;
                }
            }
        }

        fn emitJump(self: *Compiler, target: usize) !void {
            const pos = self.code.items.len;
            try self.emit(Asm.@"b offset"(@intCast(target - pos)));
        }

        fn emitPush(self: *Compiler) !void {
            try self.emit(Asm.@".push x0");
        }

        fn emitPop(self: *Compiler) !void {
            try self.emit(Asm.@".pop x0");
        }

        fn seg16(x: u64, shift: u6) u32 {
            return @as(u32, @truncate(x >> shift)) & 0xffff;
        }

        fn emitNumber(self: *Compiler, n: u64, r: u5) !void {
            const rr: u32 = r;
            // movz x0, #token.Number
            try self.emit(0xd2800000 | rr | seg16(n, 0) << 5);
            if (n > 0xffff) {
                // movk x0, #token.Number, lsl #16
                try self.emit(0xf2a00000 | rr | seg16(n, 16) << 5);
            }
            if (n > 0xffffffff) {
                // movk x0, #token.Number, lsl #32
                try self.emit(0xf2c00000 | rr | seg16(n, 32) << 5);
            }
            if (n > 0xffffffffffff) {
                // movk x0, #token.Number, lsl #48
                try self.emit(0xf2e00000 | rr | seg16(n, 48) << 5);
            }
        }

        // Emit a fixed-length 64-bit pointer into register r
        fn emitPtr(self: *Compiler, ptr: u64, r: u5) !void {
            const rr: u32 = r;
            try self.emit(0xd2800000 | rr | seg16(ptr, 0) << 5);
            try self.emit(0xf2a00000 | rr | seg16(ptr, 16) << 5);
            try self.emit(0xf2c00000 | rr | seg16(ptr, 32) << 5);
            try self.emit(0xf2e00000 | rr | seg16(ptr, 48) << 5);
        }

        fn emitCall(self: *Compiler, r: u5) !void {
            try self.emit(Asm.@"blr Xn"(r));
        }

        /// Emit a BL placeholder and record a relocation for later patching.
        fn emitBL(self: *Compiler, target_addr: usize) !void {
            try self.relocations.append(.{
                .code_offset = self.code.items.len,
                .target_addr = target_addr,
            });
            try self.emit(0x00000000); // placeholder, patched by resolveRelocations
        }

        /// Patch all BL placeholders with correct PC-relative offsets.
        /// link_base is the absolute byte address where code[0] will be placed in the image.
        fn resolveRelocations(self: *Compiler, link_base: usize, code: []u32) void {
            for (self.relocations.items) |rel| {
                const target = if (rel.target_addr == SELF_CALL) link_base else rel.target_addr;
                const instr_addr = link_base + rel.code_offset * 4;
                const offset_bytes: i64 = @as(i64, @intCast(target)) - @as(i64, @intCast(instr_addr));
                const offset_words: i26 = @intCast(@divExact(offset_bytes, 4));
                code[rel.code_offset] = Asm.@"bl offset"(offset_words);
            }
        }

        fn compileToken(self: *Compiler, token: Parser.Token) Error!void {
            switch (token) {
                .Number => |n| {
                    try self.emitNumber(@as(u64, @bitCast(Fy.makeInt(n))), 0);
                    try self.emitPush();
                },
                .Float => |f| {
                    try self.emitNumber(@as(u64, @bitCast(Fy.makeFloat(f))), 0);
                    try self.emitPush();
                },
                .Word => |w| {
                    // Namespace-aware lookup: if compiling inside a namespace,
                    // try "ns:word" first (for intra-module references), then bare "word"
                    const word = if (self.namespace) |ns| blk: {
                        const prefixed = self.fy.fyalloc.alloc(u8, ns.len + w.len) catch return Error.OutOfMemory;
                        defer self.fy.fyalloc.free(prefixed);
                        @memcpy(prefixed[0..ns.len], ns);
                        @memcpy(prefixed[ns.len..], w);
                        break :blk self.fy.findWord(prefixed) orelse self.fy.findWord(w);
                    } else self.fy.findWord(w);
                    if (word) |w_val| {
                        try self.emitWord(w_val);
                    } else {
                        std.debug.print("Unknown word: {s}\n", .{w});
                        return Error.UnknownWord;
                    }
                },
                .String => |s| {
                    // Handle string escapes
                    const unescaped = unescapeString(self.fy.fyalloc, s) catch |err| {
                        std.debug.print("String unescape error: {}\n", .{err});
                        return Error.OutOfMemory;
                    };
                    defer self.fy.fyalloc.free(unescaped);

                    // Store the string in the heap and root it (survives gc)
                    const strValue = try self.fy.heap.storeString(unescaped);
                    self.fy.heap.addRoot(Fy.getStrId(strValue));
                    try self.emitNumber(@as(u64, @bitCast(strValue)), 0); // Put string value in x0
                    try self.emitPush(); // Push result
                },
            }
        }

        fn declareWord(self: *Compiler, name: []const u8) !void {
            if (self.fy.userWords.getPtr(name)) |_| {
                return;
            } else {
                var key: []u8 = undefined;
                key = try self.fy.fyalloc.dupe(u8, name);
                try self.fy.userWords.put(key, Word{
                    .code = &[_]u32{},
                    .c = 0,
                    .p = 0,
                });
            }
        }

        fn defineWord(self: *Compiler, name: []const u8, code: []u32) !void {
            if (self.fy.userWords.getPtr(name)) |word| {
                // Free existing code if there is any
                if (word.code.len > 0) {
                    self.fy.fyalloc.free(word.code);
                }
                // Make a copy of the code
                const codeCopy = try self.fy.fyalloc.dupe(u32, code);
                word.code = codeCopy;
            }
        }

        const Wrap = enum {
            None,
            Quote,
            Function,
            SessionRet, // preserve x21/x22 across calls; return top-of-stack and pop it
            UserWord, // save/restore x29/x30 only; data stack (x21/x22) is shared
        };

        // Recursively parse a quote and store it on the heap, supporting arbitrary nesting
        fn parseQuoteToHeap(self: *Compiler) Error!Value {
            var items = std.ArrayList(Fy.Heap.Item).init(self.fy.fyalloc);
            var items_ok = false;
            errdefer {
                if (!items_ok) {
                    // Free any duped words/strings we stashed into items on failure
                    for (items.items) |it| switch (it) {
                        .Word => |w| self.fy.fyalloc.free(w),
                        .String => |s| self.fy.fyalloc.free(s),
                        else => {},
                    };
                    items.deinit();
                }
            }
            var locals: ?std.ArrayList([]u8) = null;
            var first = true;
            while (true) {
                const t = (try self.parser.nextToken()) orelse return Error.UnexpectedEndOfInput;
                switch (t) {
                    .Word => |w2| {
                        if (std.mem.eql(u8, w2, Word.QUOTE_END)) break;
                        if (std.mem.eql(u8, w2, Word.QUOTE_OPEN)) {
                            const nested = try self.parseQuoteToHeap();
                            try items.append(Fy.Heap.Item{ .Quote = nested });
                        } else if (first and std.mem.eql(u8, w2, "|")) {
                            // Begin locals header
                            first = false;
                            var names = std.ArrayList([]u8).init(self.fy.fyalloc);
                            var names_ok = false;
                            errdefer {
                                if (!names_ok) {
                                    for (names.items) |nm| self.fy.fyalloc.free(nm);
                                    names.deinit();
                                }
                            }
                            while (true) {
                                const t2 = (try self.parser.nextToken()) orelse return Error.UnexpectedEndOfInput;
                                switch (t2) {
                                    .Word => |wname| {
                                        if (std.mem.eql(u8, wname, "|")) {
                                            locals = names;
                                            names_ok = true;
                                            break;
                                        }
                                        const nm = try self.fy.fyalloc.dupe(u8, wname);
                                        try names.append(nm);
                                    },
                                    else => return Error.ExpectedWord,
                                }
                            }
                        } else {
                            first = false;
                            const dup_w2 = try self.fy.fyalloc.dupe(u8, w2);
                            try items.append(Fy.Heap.Item{ .Word = dup_w2 });
                        }
                    },
                    .Number => |n| {
                        first = false;
                        try items.append(Fy.Heap.Item{ .Number = n });
                    },
                    .Float => |f| {
                        first = false;
                        try items.append(Fy.Heap.Item{ .Float = f });
                    },
                    .String => |s| {
                        first = false;
                        const dup_s = try self.fy.fyalloc.dupe(u8, s);
                        try items.append(Fy.Heap.Item{ .String = dup_s });
                    },
                }
            }
            const qv = try self.fy.heap.storeQuote(items);
            self.fy.heap.addRoot(Fy.getStrId(qv));
            items_ok = true;
            if (locals) |names| {
                const q = self.fy.heap.getQuote(qv);
                q.locals_names = names;
            }
            return qv;
        }

        /// Compile-time `sig:` word: emits inline ARM64 code to marshal args and call a C function.
        /// Syntax: `sig: <arg-types>:<return-type>`
        /// Arg chars: i=int(x reg), f=float32(s reg), d=float64(d reg), 4=4-byte struct(x reg), p=pointer(x reg)
        /// Return chars: v=void(push 0), i=int(push x0), f=float32, d=float64
        fn compileSigCall(self: *Compiler) Error!void {
            // Read signature as raw text to avoid tokenizer interpreting digits/colons
            const sig = self.parser.nextRawWord() orelse return Error.UnexpectedEndOfInput;

            // Split signature on ':'
            var args_part: []const u8 = "";
            var ret_part: []const u8 = "i"; // default: integer return
            for (sig, 0..) |ch, idx| {
                if (ch == ':') {
                    args_part = sig[0..idx];
                    ret_part = sig[idx + 1 ..];
                    break;
                }
            }

            const n_args = args_part.len;
            if (n_args > 7) return Error.OutOfMemory; // max 7 args (temp regs x9-x15)

            // Phase 1: Pop fptr (TOS) into x16, then pop args into temp registers
            // This convention means fptr is on top of args on the stack,
            // which is natural for word definitions: `lib "fn" dl-sym sig: ...`
            try self.emit(Asm.@".pop Xn"(16)); // fptr (TOS)
            // Pop args in reverse order into temp registers x9..x(9+n_args-1)
            var i: usize = n_args;
            while (i > 0) {
                i -= 1;
                const temp_reg: u5 = @intCast(9 + i); // x9, x10, x11, ...
                try self.emit(Asm.@".pop Xn"(temp_reg));
            }

            // Phase 2: Route each temp register to the correct target register
            var int_reg: u5 = 0; // x0, x1, x2, ...
            var float_reg: u5 = 0; // d0/s0, d1/s1, ...
            for (args_part, 0..) |arg_type, arg_idx| {
                const temp_reg: u5 = @intCast(9 + arg_idx);
                switch (arg_type) {
                    'i', '4', 'p' => {
                        // Integer/pointer/4-byte struct → next x register
                        try self.emit(Asm.@"mov Xd, Xn"(int_reg, temp_reg));
                        int_reg += 1;
                    },
                    'f' => {
                        // Float32: value on stack is f64 bits in i64.
                        // Move to d register, then convert d→s for C ABI.
                        try self.emit(Asm.@"fmov Dd, Xn"(float_reg, temp_reg));
                        try self.emit(Asm.@"fcvt Sd, Dn"(float_reg, float_reg));
                        float_reg += 1;
                    },
                    'd' => {
                        // Float64: value on stack is f64 bits in i64. Move to d register.
                        try self.emit(Asm.@"fmov Dd, Xn"(float_reg, temp_reg));
                        float_reg += 1;
                    },
                    else => return Error.UnknownWord, // unknown type char
                }
            }

            // Phase 3: Call
            try self.emit(Asm.@"blr Xn"(16));

            // Phase 4: Handle return value
            if (ret_part.len == 0 or ret_part[0] == 'v') {
                // Void return — push 0
                try self.emit(Asm.@"mov x0, #0");
                try self.emitPush();
            } else if (ret_part[0] == 'i' or ret_part[0] == 'p') {
                // Integer return — x0 already has the value
                try self.emitPush();
            } else if (ret_part[0] == 'f') {
                // Float32 return — s0 has result, convert to f64, move to x0
                try self.emit(Asm.@"fcvt Dd, Sn"(0, 0));
                try self.emit(Asm.@"fmov Xd, Dn"(0, 0));
                try self.emitPush();
            } else if (ret_part[0] == 'd') {
                // Float64 return — d0 has result, move to x0
                try self.emit(Asm.@"fmov Xd, Dn"(0, 0));
                try self.emitPush();
            } else {
                return Error.UnknownWord;
            }
        }

        /// Resolve a file path relative to the current compiler's base_dir.
        /// Returns allocated path that caller must free.
        fn resolveFilePath(self: *Compiler, raw_path: []const u8) ![]u8 {
            // If path is absolute, use as-is
            if (raw_path.len > 0 and raw_path[0] == '/') {
                return self.fy.fyalloc.dupe(u8, raw_path);
            }
            // Resolve relative to base_dir (directory of the importing file)
            if (self.base_dir) |bd| {
                const result = try self.fy.fyalloc.alloc(u8, bd.len + 1 + raw_path.len);
                @memcpy(result[0..bd.len], bd);
                result[bd.len] = '/';
                @memcpy(result[bd.len + 1 ..], raw_path);
                return result;
            }
            // No base_dir — use path as-is (relative to cwd)
            return self.fy.fyalloc.dupe(u8, raw_path);
        }

        /// Get directory part of a path (everything before the last '/')
        fn dirName(path: []const u8) ?[]const u8 {
            var i = path.len;
            while (i > 0) {
                i -= 1;
                if (path[i] == '/') return path[0..i];
            }
            return null;
        }

        /// Load and compile a file, applying an optional namespace prefix to definitions.
        fn compileFile(self: *Compiler, file_path: []const u8, namespace: ?[]const u8) Error!void {
            // Check if already imported (dedup guard)
            if (self.fy.importedFiles.get(file_path) != null) return;

            // Mark as imported
            const key = self.fy.fyalloc.dupe(u8, file_path) catch return Error.OutOfMemory;
            self.fy.importedFiles.put(key, {}) catch return Error.OutOfMemory;

            // Read file
            const file = std.fs.cwd().openFile(file_path, .{}) catch {
                std.debug.print("Cannot open file: {s}\n", .{file_path});
                return Error.UnknownWord;
            };
            defer file.close();
            const stat = file.stat() catch return Error.OutOfMemory;
            const src = file.reader().readAllAlloc(self.fy.fyalloc, stat.size) catch return Error.OutOfMemory;
            defer self.fy.fyalloc.free(src);

            // Skip shebang
            var clean_src = src;
            if (src.len > 2 and src[0] == '#' and src[1] == '!') {
                var i: usize = 2;
                while (i < src.len and src[i] != '\n') i += 1;
                clean_src = src[i..];
            }

            // Compile with a sub-compiler sharing the same Fy
            var parser = Parser.init(clean_src);
            var compiler = Compiler.init(self.fy, &parser);
            compiler.base_dir = dirName(file_path);
            compiler.namespace = namespace;
            defer compiler.deinit();

            // Compile the file body — definitions go into fy.userWords
            // We compile as .None (no function wrapping) so only definitions matter
            const code = compiler.compile(.None) catch |err| {
                std.debug.print("Error compiling {s}: {}\n", .{ file_path, err });
                return err;
            };
            // Free the generated code — we only care about side-effects (word definitions)
            self.fy.fyalloc.free(code);
        }

        /// `include "path.fy"` — textual inclusion, no namespace
        fn compileInclude(self: *Compiler) Error!void {
            const tok = try self.parser.nextToken();
            const path = switch (tok orelse return Error.UnexpectedEndOfInput) {
                .String => |s| s,
                else => return Error.ExpectedWord,
            };
            const resolved = self.resolveFilePath(path) catch return Error.OutOfMemory;
            defer self.fy.fyalloc.free(resolved);
            try self.compileFile(resolved, null);
        }

        /// `import "name"` — namespaced inclusion (definitions become basename:word)
        fn compileImport(self: *Compiler) Error!void {
            const tok = try self.parser.nextToken();
            const name = switch (tok orelse return Error.UnexpectedEndOfInput) {
                .String => |s| s,
                else => return Error.ExpectedWord,
            };

            // Extract basename for namespace (strip directory and .fy extension)
            var base = name;
            // Strip directory
            if (std.mem.lastIndexOfScalar(u8, base, '/')) |idx| {
                base = base[idx + 1 ..];
            }
            // Strip .fy extension if present
            if (std.mem.endsWith(u8, base, ".fy")) {
                base = base[0 .. base.len - 3];
            }

            // Build namespace prefix "basename:"
            const ns = self.fy.fyalloc.alloc(u8, base.len + 1) catch return Error.OutOfMemory;
            defer self.fy.fyalloc.free(ns);
            @memcpy(ns[0..base.len], base);
            ns[base.len] = ':';

            // Resolve file path: append ".fy" if not already present
            const file_path = if (std.mem.endsWith(u8, name, ".fy"))
                (self.fy.fyalloc.dupe(u8, name) catch return Error.OutOfMemory)
            else blk: {
                const fy_ext = self.fy.fyalloc.alloc(u8, name.len + 3) catch return Error.OutOfMemory;
                @memcpy(fy_ext[0..name.len], name);
                @memcpy(fy_ext[name.len..], ".fy");
                break :blk fy_ext;
            };
            defer self.fy.fyalloc.free(file_path);

            const resolved = self.resolveFilePath(file_path) catch return Error.OutOfMemory;
            defer self.fy.fyalloc.free(resolved);
            try self.compileFile(resolved, ns);
        }

        /// `constant name body ;` — evaluate body once, bake result as a literal-push word.
        /// Example: `constant libsys "/usr/lib/libSystem.B.dylib" dl-open ;`
        fn compileConstant(self: *Compiler) Error!void {
            const name_tok = try self.parser.nextToken();
            const cname = switch (name_tok orelse return Error.UnexpectedEndOfInput) {
                .Word => |w| w,
                else => return Error.ExpectedWord,
            };

            // Compile the body (terminated by ;) as a full Function so it can execute standalone
            var body_compiler = Compiler.init(self.fy, self.parser);
            body_compiler.namespace = self.namespace;
            defer body_compiler.deinit();
            const body_code = try body_compiler.compile(.Function);

            // Resolve relocations (body might call user words like dl-open)
            const link_base = @intFromPtr(self.fy.image.mem.ptr) + self.fy.image.end;
            body_compiler.resolveRelocations(link_base, body_code);

            // Link body into executable memory and call it
            const body_exe = self.fy.image.link(body_code);
            self.fy.fyalloc.free(body_code);
            Builtins.fyPtr = @intFromPtr(self.fy);
            const body_fn: *const fn () Value = @alignCast(@ptrCast(body_exe));
            const value: u64 = @bitCast(body_fn());

            // Build a tiny word that just pushes this literal value
            var val_compiler = Compiler.init(self.fy, self.parser); // parser unused
            defer val_compiler.deinit();
            try val_compiler.enterPersist();
            try val_compiler.emitNumber(value, 0);
            try val_compiler.emitPush();
            try val_compiler.leavePersist();
            const val_code = try val_compiler.code.toOwnedSlice();
            const val_exe = self.fy.image.link(val_code);
            const entry_addr = @intFromPtr(val_exe.ptr);
            self.fy.fyalloc.free(val_code);

            // Register the word (with namespace prefix if applicable)
            const final_name = if (self.namespace) |ns| blk: {
                const prefixed = self.fy.fyalloc.alloc(u8, ns.len + cname.len) catch return Error.OutOfMemory;
                @memcpy(prefixed[0..ns.len], ns);
                @memcpy(prefixed[ns.len..], cname);
                break :blk prefixed;
            } else null;
            const reg_name = final_name orelse cname;
            try self.declareWord(reg_name);
            if (self.fy.userWords.getPtr(reg_name)) |word| {
                word.image_addr = entry_addr;
            }
            if (final_name) |fn_| self.fy.fyalloc.free(fn_);
        }

        fn compileDefinition(self: *Compiler) Error!void {
            const name = try self.parser.nextToken();
            if (name) |n| {
                switch (n) {
                    .Word => |w| {
                        var compiler = Compiler.init(self.fy, self.parser);
                        defer compiler.deinit();

                        // Inherit namespace for intra-module word resolution
                        compiler.namespace = self.namespace;

                        // enable self-references during compilation
                        compiler.currentDef = w;

                        // Compile with UserWord wrap: stp x29,x30 / body / ldp x29,x30 / ret
                        const code = try compiler.compile(.UserWord);

                        // Resolve BL relocations knowing where this code will land
                        const link_base = @intFromPtr(self.fy.image.mem.ptr) + self.fy.image.end;
                        compiler.resolveRelocations(link_base, code);

                        // Link into JIT image
                        const entry = self.fy.image.link(code);
                        const entry_addr = @intFromPtr(entry.ptr);
                        self.fy.fyalloc.free(code);

                        // Apply namespace prefix for import (e.g., "raylib:" → "raylib:word")
                        const final_name = if (self.namespace) |ns| blk: {
                            const prefixed = self.fy.fyalloc.alloc(u8, ns.len + w.len) catch return Error.OutOfMemory;
                            @memcpy(prefixed[0..ns.len], ns);
                            @memcpy(prefixed[ns.len..], w);
                            break :blk prefixed;
                        } else null;
                        const reg_name = final_name orelse w;

                        // Declare word AFTER successful compilation (fixes ghost word bug)
                        try self.declareWord(reg_name);
                        if (self.fy.userWords.getPtr(reg_name)) |word| {
                            word.image_addr = entry_addr;
                        }
                        // Free the prefixed name if we allocated one (declareWord dupes it)
                        if (final_name) |fn_| self.fy.fyalloc.free(fn_);
                    },
                    else => {
                        return Error.ExpectedWord;
                    },
                }
            } else {
                return Error.UnexpectedEndOfInput;
            }
        }

        // removed old compileQuote (quotes are now heap objects)

        fn enter(self: *Compiler) !void {
            // Save frame pointer and link register
            try self.emit(Asm.@"stp x29, x30, [sp, #0x10]!");
            // Save callee-saved x21/x22 we use for data stack base/top
            try self.emit(Asm.@"stp x21, x22, [sp, #0x10]!");
            //try self.emit(Asm.@"mov x29, sp");

        }

        fn leave(self: *Compiler) !void {
            //try self.emit(Asm.@"mov sp, x29");
            // Restore callee-saved x21/x22
            try self.emit(Asm.@"ldp x21, x22, [sp], #0x10");
            // Restore frame pointer and link register
            try self.emit(Asm.@"ldp x29, x30, [sp], #0x10");
            try self.emit(Asm.ret);
        }

        fn enterPersist(self: *Compiler) !void {
            // Only save frame pointer/link register; preserve x21/x22 across calls
            try self.emit(Asm.@"stp x29, x30, [sp, #0x10]!");
        }

        fn leavePersist(self: *Compiler) !void {
            try self.emit(Asm.@"ldp x29, x30, [sp], #0x10");
            try self.emit(Asm.ret);
        }

        fn compile(self: *Compiler, wrap: Wrap) Error![]u32 {
            switch (wrap) {
                .None => {},
                .Quote => {
                    // Quotes share the data stack — only save LR/FP
                    try self.enterPersist();
                },
                .Function => {
                    try self.enter();
                    const stack_end = self.fy.data_stack_top;
                    try self.emitNumber(stack_end, 21);
                    try self.emitNumber(stack_end, 22);
                    try self.emitNumber(0, 0);
                    try self.emitPush();
                },
                .SessionRet => {
                    // Preserve x21/x22; no reinit; no guard push
                    try self.enterPersist();
                },
                .UserWord => {
                    // Save only LR/FP; data stack (x21/x22) is shared with caller
                    try self.enterPersist();
                },
            }
            var token = try self.parser.nextToken();
            while (token != null) : (token = try self.parser.nextToken()) {
                switch (token.?) {
                    .Word => |w| {
                        if (std.mem.eql(u8, w, Word.END) or std.mem.eql(u8, w, Word.QUOTE_END)) {
                            break;
                        }
                        if (std.mem.eql(u8, w, Word.DEFINE)) {
                            try self.compileDefinition();
                            continue;
                        }
                        if (std.mem.eql(u8, w, "::")) {
                            try self.compileConstant();
                            continue;
                        }
                        // Self-recursion: emit BL back to own entry point
                        if (self.currentDef) |def_name| {
                            if (std.mem.eql(u8, w, def_name)) {
                                try self.emitBL(SELF_CALL);
                                continue;
                            }
                        }
                        if (std.mem.eql(u8, w, Word.QUOTE_OPEN)) {
                            const qv = try self.parseQuoteToHeap();
                            try self.emitNumber(@as(u64, @bitCast(qv)), 0);
                            try self.emitPush();
                            continue;
                        }
                        if (std.mem.eql(u8, w, "sig:")) {
                            try self.compileSigCall();
                            continue;
                        }
                        if (std.mem.eql(u8, w, "include")) {
                            try self.compileInclude();
                            continue;
                        }
                        if (std.mem.eql(u8, w, "import")) {
                            try self.compileImport();
                            continue;
                        }
                    },
                    else => {},
                }
                try self.compileToken(token.?);
            }
            switch (wrap) {
                .None => {},
                .Quote => {
                    try self.leavePersist();
                },
                .Function => {
                    try self.emitPop();
                    try self.leave();
                },
                .SessionRet => {
                    // Return top-of-stack but preserve the rest of the stack across calls
                    try self.emitPop();
                    try self.leavePersist();
                },
                .UserWord => {
                    try self.leavePersist();
                },
            }
            return self.code.toOwnedSlice();
        }

        fn compileFn(self: *Compiler) ![]u32 {
            return self.compile(.Function);
        }
    };

    // const TableEntry = struct {
    //     length: usize,
    // };

    const Image = struct {
        mem: []align(std.mem.page_size) u8, // full reserved range
        committed: usize, // bytes that are usable (multiple of page_size)
        end: usize, // write cursor (bytes written so far)

        // Reserve 64MB of virtual address space. Only committed pages use physical memory.
        const RESERVE_SIZE: usize = 64 * 1024 * 1024;

        fn init() !Image {
            if (darwin) {
                // Map full range as RW + MAP_JIT. macOS demand-pages so no physical
                // memory is committed until touched. The base address is stable forever.
                const raw = darwin_c.mmap(null, RESERVE_SIZE, darwin_c.PROT_READ | darwin_c.PROT_WRITE, darwin_c.MAP_PRIVATE | darwin_c.MAP_ANON | darwin_c.MAP_JIT, -1, 0);
                if (raw == darwin_c.MAP_FAILED) return error.OutOfMemory;
                const ptr_any: ?*anyopaque = @ptrCast(raw);
                const ptr_page: [*]align(std.mem.page_size) u8 = @alignCast(@ptrCast(ptr_any));
                const mem: []align(std.mem.page_size) u8 = ptr_page[0..RESERVE_SIZE];
                return Image{ .mem = mem, .committed = RESERVE_SIZE, .end = 0 };
            }
            const flags: std.posix.MAP = .{ .TYPE = .PRIVATE, .ANONYMOUS = true };
            const mem = try std.posix.mmap(null, RESERVE_SIZE, std.posix.PROT.NONE, flags, -1, 0);
            // Commit the first page as RW
            const first_page: []align(std.mem.page_size) u8 = mem[0..std.mem.page_size];
            try std.posix.mprotect(first_page, std.posix.PROT.READ | std.posix.PROT.WRITE);
            return Image{
                .mem = mem,
                .committed = std.mem.page_size,
                .end = 0,
            };
        }

        fn deinit(self: *Image) void {
            if (darwin) {
                _ = darwin_c.munmap(self.mem.ptr, RESERVE_SIZE);
            } else {
                std.posix.munmap(self.mem);
            }
        }

        // Commit one more page within the reserved range. Base address never changes.
        fn grow(self: *Image) !void {
            if (self.committed >= RESERVE_SIZE) return error.OutOfMemory;
            if (darwin) {
                const next: ?*anyopaque = @ptrCast(self.mem.ptr + self.committed);
                if (darwin_c.mprotect(next, std.mem.page_size, darwin_c.PROT_READ | darwin_c.PROT_WRITE) != 0)
                    return error.OutOfMemory;
            } else {
                const next_ptr: [*]align(std.mem.page_size) u8 = @alignCast(self.mem.ptr + self.committed);
                const next_page: []align(std.mem.page_size) u8 = next_ptr[0..std.mem.page_size];
                try std.posix.mprotect(next_page, std.posix.PROT.READ | std.posix.PROT.WRITE);
            }
            self.committed += std.mem.page_size;
        }

        fn protect(self: *Image, executable: bool) !void {
            if (darwin) return; // No-op; use pthread_jit_write_protect_np
            const committed_slice: []align(std.mem.page_size) u8 = @alignCast(self.mem[0..self.committed]);
            if (executable) {
                try std.posix.mprotect(committed_slice, std.posix.PROT.READ | std.posix.PROT.EXEC);
            } else {
                try std.posix.mprotect(committed_slice, std.posix.PROT.READ | std.posix.PROT.WRITE);
            }
        }

        fn link(self: *Image, code: []u32) []u8 {
            const len: usize = code.len * @sizeOf(u32);
            // Grow until we have enough committed space
            while (self.end + len > self.committed) {
                self.grow() catch @panic("failed to grow image");
            }
            if (!darwin) {
                self.protect(false) catch @panic("failed to set image writable");
            }
            const new = self.end;
            self.end += len;
            if (darwin) {
                // Ensure RW for write, then switch to RX for execute
                _ = darwin_c.pthread_jit_write_protect_np(0);
                _ = darwin_c.mprotect(self.mem.ptr, self.committed, darwin_c.PROT_READ | darwin_c.PROT_WRITE);
                @memcpy(self.mem[new..self.end], std.mem.sliceAsBytes(code));
                _ = darwin_c.pthread_jit_write_protect_np(1);
                _ = darwin_c.mprotect(self.mem.ptr, self.committed, darwin_c.PROT_READ | darwin_c.PROT_EXEC);
            } else {
                @memcpy(self.mem[new..self.end], std.mem.sliceAsBytes(code));
                self.protect(true) catch @panic("failed to set image executable");
            }
            __clear_cache(@intFromPtr(self.mem.ptr), @intFromPtr(self.mem.ptr) + self.end);
            return self.mem[new..self.end];
        }

        fn reset(self: *Image) void {
            self.end = 0;
        }
    };

    const Fn = struct {
        call: *const fn () Value,
    };

    fn jit(self: *Fy, code: []u32) !Fn {
        const executable: []u8 = self.image.link(code);
        // free the original code buffer as we already have machine code in executable memory
        self.fyalloc.free(code);
        // cast the memory to a function pointer and call
        const fun: *const fn () Value = @alignCast(@ptrCast(executable));
        return Fn{ .call = fun };
    }

    fn compileQuote(self: *Fy, q: *Heap.QuoteObj) ![]u32 {
        var dummy = Parser.init("");
        var c = Compiler.init(self, &dummy);
        defer c.deinit();
        // Quotes share the data stack with their caller — only save LR/FP, not x21/x22
        try c.enterPersist();
        const locals_len: usize = q.locals_names.items.len;
        var frame_size: usize = 0;
        if (locals_len > 0) {
            frame_size = locals_len * @sizeOf(Value);
            frame_size = (frame_size + 15) & ~@as(usize, 15);
            try c.emit(Asm.sub_sp_imm(@intCast(frame_size)));
            var i: isize = @intCast(locals_len);
            while (i > 0) : (i -= 1) {
                try c.emit(Asm.@".pop x0");
                const idx: usize = @intCast(i - 1);
                const off: u32 = @intCast(idx * @sizeOf(Value));
                try c.emit(Asm.str_sp_x0(off));
            }
        }
        for (q.items.items) |it| switch (it) {
            .Number => |n| {
                try c.emitNumber(@as(u64, @bitCast(makeInt(n))), 0);
                try c.emitPush();
            },
            .Float => |f| {
                try c.emitNumber(@as(u64, @bitCast(makeFloat(f))), 0);
                try c.emitPush();
            },
            .Word => |w| {
                var is_local = false;
                var li: usize = 0;
                while (li < q.locals_names.items.len) : (li += 1) {
                    if (std.mem.eql(u8, q.locals_names.items[li], w)) {
                        is_local = true;
                        break;
                    }
                }
                if (is_local) {
                    const off: u32 = @intCast(li * @sizeOf(Value));
                    try c.emit(Asm.ldr_sp_x0(off));
                    try c.emitPush();
                } else {
                    if (self.findWord(w)) |wd| try c.emitWord(wd) else return Compiler.Error.UnknownWord;
                }
            },
            .String => |s| {
                const v = try self.heap.storeString(s);
                self.heap.addRoot(Fy.getStrId(v));
                try c.emitNumber(@as(u64, @bitCast(v)), 0);
                try c.emitPush();
            },
            .Quote => |qv| {
                try c.emitNumber(@as(u64, @bitCast(qv)), 0);
                try c.emitPush();
            },
        };
        if (frame_size > 0) {
            try c.emit(Asm.add_sp_imm(@intCast(frame_size)));
        }
        try c.leavePersist();
        const code = try c.code.toOwnedSlice();
        // Resolve BL relocations for any user word calls within the quote
        const link_base = @intFromPtr(self.image.mem.ptr) + self.image.end;
        c.resolveRelocations(link_base, code);
        return code;
    }

    fn runWithBaseDir(self: *Fy, src: []const u8, base_dir: ?[]const u8) !Fy.Value {
        // Set fyPtr for Builtins to access heap
        Builtins.fyPtr = @intFromPtr(self);

        var parser = Fy.Parser.init(src);
        var compiler = Fy.Compiler.init(self, &parser);
        compiler.base_dir = base_dir;
        defer compiler.deinit();
        const code = compiler.compileFn();

        if (code) |c| {
            // Resolve BL relocations for user word calls in the main program
            const link_base = @intFromPtr(self.image.mem.ptr) + self.image.end;
            compiler.resolveRelocations(link_base, c);
            var compiled = try self.jit(c);
            const x = compiled.call();
            //self.image.reset();
            return x;
        } else |err| {
            return err;
        }
    }

    fn run(self: *Fy, src: []const u8) !Fy.Value {
        return self.runWithBaseDir(src, null);
    }

    fn initVmStack(self: *Fy) void {
        var dummy = Parser.init("");
        var c = Compiler.init(self, &dummy);
        defer c.deinit();
        c.enterPersist() catch @panic("enterPersist failed");
        const stack_end = self.data_stack_top;
        c.emitNumber(stack_end, 21) catch @panic("emitNumber x21 failed");
        c.emitNumber(stack_end, 22) catch @panic("emitNumber x22 failed");
        c.emitNumber(0, 0) catch @panic("emitNumber 0 failed");
        c.emitPush() catch @panic("emitPush failed");
        c.leavePersist() catch @panic("leavePersist failed");
        const code = c.code.toOwnedSlice() catch @panic("own code failed");
        var f = self.jit(code) catch @panic("jit initVmStack failed");
        _ = f.call();
    }

    fn debugDump(self: *Fy) void {
        // show userWords
        var keys = self.userWords.keyIterator();
        std.debug.print("user words: ", .{});
        while (keys.next()) |k| {
            std.debug.print("{s} ", .{k.*});
        }
        std.debug.print("\n", .{});
    }
};

pub fn repl(allocator: std.mem.Allocator, fy: *Fy) !void {
    const stdout = std.io.getStdOut().writer();
    var editor = Editor.init(allocator, .{});
    defer editor.deinit();

    var handler: struct {
        editor: *Editor,
        pub fn paste(self: *@This(), text: []const u32) void {
            self.editor.insertUtf32(text);
        }
    } = .{ .editor = &editor };
    editor.setHandler(&handler);

    try stdout.print("fy! {s}\n", .{Fy.version});
    // Initialize persistent VM data stack once for this REPL session
    fy.initVmStack();

    while (true) {
        const line: []const u8 = editor.getLine("fy> ") catch |err| switch (err) {
            error.Eof => break,
            else => return err,
        };
        defer allocator.free(line);
        try editor.addToHistory(line);
        if (line.len == 0) {
            allocator.free(line);
            continue;
        }
        // Compile this line to preserve stack across prompts and return top-of-stack
        var parser2 = Fy.Parser.init(line);
        var compiler2 = Fy.Compiler.init(fy, &parser2);
        const code = compiler2.compile(.SessionRet) catch |err| {
            compiler2.deinit();
            try stdout.print("error: {}\n", .{err});
            continue;
        };
        // Resolve BL relocations for user word calls in REPL input
        const link_base = @intFromPtr(fy.image.mem.ptr) + fy.image.end;
        compiler2.resolveRelocations(link_base, code);
        var compiled = fy.jit(code) catch |err| {
            compiler2.deinit();
            try stdout.print("error: {}\n", .{err});
            continue;
        };
        compiler2.deinit();
        const r = compiled.call();
        try stdout.print("    ", .{});
        try fy.writeValue(stdout, r);
        try stdout.print("\n", .{});
    }
    return;
}

pub fn runFile(allocator: std.mem.Allocator, fy: *Fy, path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    const fileSize = stat.size;
    const src = try file.reader().readAllAlloc(allocator, fileSize);
    var cleanSrc = src;
    // get rid of shebang from src if present
    if (src.len > 2 and src[0] == '#' and src[1] == '!') {
        var i: usize = 2;
        while (i < src.len and src[i] != '\n') {
            i += 1;
        }
        cleanSrc = src[i..];
    }
    // Extract directory of the file for include/import resolution
    const base_dir = Fy.Compiler.dirName(path);
    const result = fy.runWithBaseDir(cleanSrc, base_dir);
    allocator.free(src);
    if (result) |_| {
        //std.debug.print("{d}\n", .{r});
    } else |err| {
        std.debug.print("error: {}\n", .{err});
    }
}

pub fn dumpImage(fy: *Fy) !void {
    const path = "fy.out";
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    _ = try file.write(fy.image.mem[0..fy.image.end]);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

    var argIt = try std.process.ArgIterator.initWithAllocator(allocator);
    _ = argIt.skip(); // skip the program name
    var parsedArgs = try Args.parseArgs(allocator, &argIt);
    defer {
        parsedArgs.deinit();
        argIt.deinit();
    }

    if (parsedArgs.help) {
        std.debug.print("Usage: fy [options] [files]\n", .{});
        std.debug.print("Options:\n", .{});
        std.debug.print("  -e, --eval <expr>  Evaluate expr\n", .{});
        std.debug.print("  -r, --repl         Launch interactive REPL\n", .{});
        std.debug.print("  -i, --image        Dump executable memory image to fy.out\n", .{});
        std.debug.print("  -v, --version      Display version and exit\n", .{});
        std.debug.print("  -h, --help         Display this help and exit\n", .{});
        return;
    }

    if (parsedArgs.version) {
        std.debug.print("fy {s}\n", .{Fy.version});
        return;
    }

    if (parsedArgs.eval == null and parsedArgs.files == 0) {
        parsedArgs.repl = true;
    }

    var fy = Fy.init(allocator);
    defer {
        fy.deinit();
    }

    if (parsedArgs.files > 0) {
        for (parsedArgs.other_args.items) |file| {
            //std.debug.print("file: {s}\n", .{file});
            try runFile(allocator, &fy, file);
        }
    }

    if (parsedArgs.eval) |e| {
        const result = fy.run(e);
        if (result) |r| {
            const stdout = std.io.getStdOut().writer();
            try fy.writeValue(stdout, r);
            try stdout.print("\n", .{});
        } else |err| {
            std.debug.print("error: {}\n", .{err});
        }
    }

    if (parsedArgs.repl) {
        //std.debug.print("repl\n", .{});
        return repl(allocator, &fy);
    }

    if (parsedArgs.image) {
        try dumpImage(&fy);
    }
    return;
}

// Tests below

const TestCase = struct {
    input: []const u8,
    expected: Fy.Value,

    fn run(self: *const TestCase, fy: *Fy) !void {
        std.debug.print("\nfy> {s}\n", .{self.input});
        const input = self.input;
        const result = try fy.run(input);
        std.debug.print("exp {any}\n    {any}\n", .{ self.expected, result });
        try std.testing.expectEqual(self.expected, result);
    }
};

fn runCases(fy: *Fy, testCases: []const TestCase) !void {
    for (testCases) |testCase| {
        try testCase.run(fy);
    }
}

test "Basic expressions and built-in words" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();

    try runCases(&fy, &[_]TestCase{
        .{ .input = "", .expected = Fy.makeInt(0) }, //
        .{ .input = "1", .expected = Fy.makeInt(1) },
        .{ .input = "-1", .expected = Fy.makeInt(-1) },
        .{ .input = "1 2", .expected = Fy.makeInt(2) },
        .{ .input = "1 2 +", .expected = Fy.makeInt(3) },
        .{ .input = "10 -10 +", .expected = Fy.makeInt(0) },
        .{ .input = "-5 0 - 6 +", .expected = Fy.makeInt(1) },
        .{ .input = "1 2 -", .expected = Fy.makeInt(-1) },
        .{ .input = "1 2 !-", .expected = Fy.makeInt(1) },
        .{ .input = "2 2 *", .expected = Fy.makeInt(4) },
        .{ .input = "12 3 /", .expected = Fy.makeInt(4) },
        .{ .input = "12 5 &", .expected = Fy.makeInt(4) },
        .{ .input = "1 2 =", .expected = Fy.makeInt(0) },
        .{ .input = "1 1 =", .expected = Fy.makeInt(1) },
        .{ .input = "1 2 !=", .expected = Fy.makeInt(1) },
        .{ .input = "1 1 !=", .expected = Fy.makeInt(0) },
        .{ .input = "1 2 >", .expected = Fy.makeInt(0) },
        .{ .input = "2 1 >", .expected = Fy.makeInt(1) },
        .{ .input = "1 2 <", .expected = Fy.makeInt(1) },
        .{ .input = "2 1 <", .expected = Fy.makeInt(0) },
        .{ .input = "1 2 >=", .expected = Fy.makeInt(0) },
        .{ .input = "2 1 >=", .expected = Fy.makeInt(1) },
        .{ .input = "2 2 >=", .expected = Fy.makeInt(1) },
        .{ .input = "1 2 <=", .expected = Fy.makeInt(1) },
        .{ .input = "2 1 <=", .expected = Fy.makeInt(0) },
        .{ .input = "2 2 <=", .expected = Fy.makeInt(1) },
        .{ .input = "2 dup", .expected = Fy.makeInt(2) },
        .{ .input = "2 3 swap", .expected = Fy.makeInt(2) },
        .{ .input = "2 3 over", .expected = Fy.makeInt(2) },
        .{ .input = "2 3 4 5 over2", .expected = Fy.makeInt(3) },
        .{ .input = "2 3 nip", .expected = Fy.makeInt(3) },
        .{ .input = "2 3 tuck", .expected = Fy.makeInt(3) },
        .{ .input = "2 3 drop", .expected = Fy.makeInt(2) },
        .{ .input = "2 1+ 4 1- =", .expected = Fy.makeInt(1) },
        .{ .input = "depth", .expected = Fy.makeInt(0) },
        .{ .input = "5 6 7 8 depth", .expected = Fy.makeInt(4) },
        .{ .input = "1 2 3 rot", .expected = Fy.makeInt(1) },
        .{ .input = "1 2 3 -rot", .expected = Fy.makeInt(2) },
        .{ .input = "1 2 3 4 drop2", .expected = Fy.makeInt(2) },
        .{ .input = "3 2 dup2 * rot * +", .expected = Fy.makeInt(20) },
    });
}

test "User defined words" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();

    try runCases(&fy, &[_]TestCase{
        .{ .input = ": sqr dup * ;", .expected = Fy.makeInt(0) },
        .{ .input = "2 sqr", .expected = Fy.makeInt(4) },
        .{ .input = ":sqr dup *; 2 sqr", .expected = Fy.makeInt(4) },
        .{ .input = ": sqr dup * ; 2 sqr", .expected = Fy.makeInt(4) },
        .{ .input = ":a 1; a a +", .expected = Fy.makeInt(2) },
        .{ .input = ": a 2 +; :b 3 +; 1 a b 6 =", .expected = Fy.makeInt(1) },
        .{ .input = "1 a b", .expected = Fy.makeInt(6) },
        .{ .input = "2 dup :dup *; dup", .expected = Fy.makeInt(4) }, // warning: this breaks dup in this Fy instance forever
    });
}

test "Quotes" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();

    try runCases(&fy, &[_]TestCase{
        .{
            .input = "2 [dup +] do", //
            .expected = Fy.makeInt(4),
        },
        .{ .input = "[dup +] 3 swap do", .expected = Fy.makeInt(6) },
        .{ .input = ":dup+ [dup +]; 5 dup+ do", .expected = Fy.makeInt(10) },
        .{ .input = "10 dup+ do", .expected = Fy.makeInt(20) },
        .{ .input = "2 3 over over < [*] do?", .expected = Fy.makeInt(6) },
        .{ .input = "[2 *] 1 [1 +] do swap do", .expected = Fy.makeInt(4) },
        .{ .input = "2 3 \\* do", .expected = Fy.makeInt(6) },
        .{ .input = "2 2 3 \\* dip -", .expected = Fy.makeInt(1) },
        // locals basics
        .{ .input = "41 [ | x | x 1+] do", .expected = Fy.makeInt(42) },
        .{ .input = "10 20 [ | a b | a b + ] do", .expected = Fy.makeInt(30) },
        // header with zero locals is allowed and does nothing
        .{ .input = "7 [ | | 1+ ] do", .expected = Fy.makeInt(8) },
    });
}

test "Conditional do?/ifte and do variants" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();

    std.debug.print("[tests] do?/ifte/do variants\n", .{});

    try runCases(&fy, &[_]TestCase{
        // do? with quote: true executes, false skips
        .{ .input = "5 1 [1+] do?", .expected = Fy.makeInt(6) },
        .{ .input = "5 0 [1+] do?", .expected = Fy.makeInt(5) },

        // do? with single-word quote via backslash
        .{ .input = "5 1 \\1+ do?", .expected = Fy.makeInt(6) },
        .{ .input = "5 0 \\1+ do?", .expected = Fy.makeInt(5) },

        // do executes both a bracketed quote and a backslashed single-word quote
        .{ .input = "5 [1+] do", .expected = Fy.makeInt(6) },
        .{ .input = "5 \\1+ do", .expected = Fy.makeInt(6) },
        // empty quote is a no-op
        .{ .input = "5 [] do", .expected = Fy.makeInt(5) },

        // ifte with quotes: choose true/false branch by predicate
        .{ .input = "10 1 [1+] [1-] ifte", .expected = Fy.makeInt(11) },
        .{ .input = "10 0 [1+] [1-] ifte", .expected = Fy.makeInt(9) },

        // ifte with single-word quotes via backslash
        .{ .input = "10 1 \\1+ \\1- ifte", .expected = Fy.makeInt(11) },
        .{ .input = "10 0 \\1+ \\1- ifte", .expected = Fy.makeInt(9) },
        // locals + ifte interaction
        .{ .input = "3 1 [ | n | n 1+ ] [ | n | n 1- ] ifte", .expected = Fy.makeInt(4) },
    });
}

test "Quotes - list manipulation and caching" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();

    try runCases(&fy, &[_]TestCase{
        // push a quote, duplicate/drop leaves a quote object; verify it's not a string
        .{ .input = "[1 2 +] dup drop string?", .expected = Fy.makeInt(0) },
        // nested quotes executed via outer 'do'
        .{ .input = "[[dup +] do] 2 swap do", .expected = Fy.makeInt(4) },
        // times (alias) and retain ops
        .{ .input = "2 [1 +] times", .expected = Fy.makeInt(0) },
        .{ .input = "42 >r r@ r>", .expected = Fy.makeInt(42) },
        // quote concat and call (compose [1 +] twice)
        .{ .input = "2 [1 +] dup cat do", .expected = Fy.makeInt(4) },
    });
}

test "Loops - dotimes and repeat" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();

    try runCases(&fy, &[_]TestCase{
        // dotimes: starting from 0, apply [1+] three times -> 3
        .{ .input = "0 3 [1+] dotimes", .expected = Fy.makeInt(3) },
        // repeat: count down to zero with [1- dup], drop the duplicate -> 0
        .{ .input = "3 [1- dup] repeat drop", .expected = Fy.makeInt(0) },
    });
}

test "Print functions compile" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();

    try runCases(&fy, &[_]TestCase{
        .{ .input = "1 .", .expected = Fy.makeInt(0) },
        .{ .input = "1 .hex", .expected = Fy.makeInt(0) },
        .{ .input = "1 . .nl 2 .", .expected = Fy.makeInt(0) },
        .{ .input = "65 .c .nl", .expected = Fy.makeInt(0) },
        .{ .input = "1 spy", .expected = Fy.makeInt(1) },
    });
}

test "Comments are ignored" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();

    try runCases(&fy, &[_]TestCase{
        .{ .input = "( Comment before code ) 1 2 +", .expected = Fy.makeInt(3) },
        .{ .input = "1 2 + ( Comment ) ( Another comment )", .expected = Fy.makeInt(3) },
        .{ .input = "1 2 + ( Comment ) ( Another comment )", .expected = Fy.makeInt(3) },
        .{ .input = "(Comment before code) 1 2 +", .expected = Fy.makeInt(3) },
        .{ .input = "1 2 + ( Co(mm)ent ) (Another comment )", .expected = Fy.makeInt(3) },
        .{ .input = "1 ( Comment) 2 +", .expected = Fy.makeInt(3) },
    });
}

test "Character literals" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();

    try runCases(&fy, &[_]TestCase{
        .{ .input = "'a", .expected = Fy.makeInt('a') },
        .{ .input = "'b 'c +", .expected = Fy.makeInt('b' + 'c') },
        .{ .input = "'0 '9 +", .expected = Fy.makeInt('0' + '9') },
        .{ .input = "'x 'y swap", .expected = Fy.makeInt('x') },
        .{ .input = "'z 1 +", .expected = Fy.makeInt('z' + 1) },
        .{ .input = "'a 'a =", .expected = Fy.makeInt(1) },
        .{ .input = "'a 'b !=", .expected = Fy.makeInt(1) },
        .{ .input = "'m 'n >", .expected = Fy.makeInt(0) },
        .{ .input = "'p 'o <", .expected = Fy.makeInt(0) },
        .{ .input = "' ' drop", .expected = Fy.makeInt(' ') },
        .{ .input = "'a'b swap", .expected = Fy.makeInt('a') },
    });
}

test "String operations" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();

    // Helper function to debug string operations
    const debugString = (struct {
        fn check(f: *Fy, v: Fy.Value, label: []const u8) void {
            _ = label;
            if (Fy.isStr(v) and (f.heap.typeOf(v) orelse .String) == .String) {
                _ = Fy.getStrId(v);
                _ = f.heap.getString(v);
            }
        }
    }).check;

    // Run a single test case to debug string operations
    {
        const input = "\"hello\"";
        const result = try fy.run(input);
        debugString(&fy, result, "String 1");
    }
    {
        const input = "\"world\"";
        const result = try fy.run(input);
        debugString(&fy, result, "String 2");
    }
    {
        const input = "\"hello\" \"world\" s+";
        const result = try fy.run(input);
        debugString(&fy, result, "Concatenated");
    }
    {
        const input = "\"hello\" \"world\" s+ slen";
        const result = try fy.run(input);
        _ = result;
    }

    try runCases(&fy, &[_]TestCase{
        .{ .input = "\"hello\" string?", .expected = Fy.makeInt(1) },
        .{ .input = "\"hello\" slen", .expected = Fy.makeInt(5) },
        .{ .input = "\"hello\" \"world\" s+ string?", .expected = Fy.makeInt(1) },
        .{ .input = "\"hello\" \"world\" s+ slen", .expected = Fy.makeInt(10) },
        .{ .input = "\"hello\" string?", .expected = Fy.makeInt(1) },
        .{ .input = "123 string?", .expected = Fy.makeInt(0) },
        .{ .input = "\"hello\" int?", .expected = Fy.makeInt(0) },
        .{ .input = "123 int?", .expected = Fy.makeInt(1) },
    });
}

test "Recursion - self and nested" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();

    try runCases(&fy, &[_]TestCase{
        // factorial using self-recursion inside quotes
        .{ .input = ": fact dup 1 <= [drop 1] [dup 1- fact *] ifte; 5 fact", .expected = Fy.makeInt(120) },
        // sum down to 0 using nested recursion via a quoted call
        .{ .input = ": sumdown dup 0 <= [drop 0] [dup 1- [sumdown] do +] ifte; 4 sumdown", .expected = Fy.makeInt(10) },
    });
}

test "Recursion - mutual (even/odd)" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();

    try runCases(&fy, &[_]TestCase{
        .{ .input = ": even dup 0 = [drop 1] [1- odd] ifte ; : odd dup 0 = [drop 0] [1- even] ifte ; 10 even", .expected = Fy.makeInt(1) },
        .{ .input = "11 even", .expected = Fy.makeInt(0) },
        .{ .input = "0 odd", .expected = Fy.makeInt(0) },
    });
}

test "Map and reduce" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();
    Fy.Builtins.fyPtr = @intFromPtr(&fy);

    try runCases(&fy, &[_]TestCase{
        // map applies function to each element
        .{ .input = "[1 2 3] [1+] map qhead", .expected = Fy.makeInt(2) },
        // reduce folds a list
        .{ .input = "0 [1 2 3] [+] reduce", .expected = Fy.makeInt(6) },
        // map with locals
        .{ .input = "[10 20 30] [ | n | n 1+ ] map qhead", .expected = Fy.makeInt(11) },
    });
}

test "Adapter basic calls" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();
    Fy.Builtins.fyPtr = @intFromPtr(&fy);

    // Build quote [1+] — parseQuoteToHeap expects opening [ already consumed
    var p1 = Fy.Parser.init("1+ ]");
    var c1 = Fy.Compiler.init(&fy, &p1);
    defer c1.deinit();
    const q_inc = try c1.parseQuoteToHeap();
    const f_inc_val = Fy.Builtins.resolveCallable(q_inc);
    try std.testing.expect(Fy.isInt(f_inc_val));
    const f_inc: usize = @intCast(Fy.getInt(f_inc_val));

    // Adapters set up their own x21/x22 from base/end params — no initVmStack needed
    const a1 = Fy.Builtins.getAdapt1(&fy);
    const tramp_end_aligned: usize = fy.tramp_stack_top;
    const base_val: Fy.Value = @bitCast(@as(i64, @intCast(tramp_end_aligned)));
    const end_val: Fy.Value = base_val;
    const r1 = a1(f_inc, base_val, end_val, Fy.makeInt(41));
    try std.testing.expectEqual(Fy.makeInt(42), r1);

    // Build quote [+]
    var p2 = Fy.Parser.init("+ ]");
    var c2 = Fy.Compiler.init(&fy, &p2);
    defer c2.deinit();
    const q_plus = try c2.parseQuoteToHeap();
    const f_plus_val = Fy.Builtins.resolveCallable(q_plus);
    try std.testing.expect(Fy.isInt(f_plus_val));
    const f_plus: usize = @intCast(Fy.getInt(f_plus_val));

    const a2 = Fy.Builtins.getAdapt2(&fy);
    const r2 = a2(f_plus, base_val, end_val, Fy.makeInt(2), Fy.makeInt(5));
    try std.testing.expectEqual(Fy.makeInt(7), r2);

    // Parse a quote with locals to ensure no crash
    var p3 = Fy.Parser.init("| n | n 1+ ]");
    var c3 = Fy.Compiler.init(&fy, &p3);
    defer c3.deinit();
    const q_inc2 = try c3.parseQuoteToHeap();
    const f_inc2_val = Fy.Builtins.resolveCallable(q_inc2);
    try std.testing.expect(Fy.isInt(f_inc2_val));
}
