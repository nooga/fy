const std = @import("std");

const Ops = enum(u32) {
    PUSHX0 = 0xf81f0fe0, // str x0, [sp, #-16]!
    PUSHX1 = 0xf81f0fe1, // str x1, [sp, #-16]!
    POPX0 = 0xf84107e0, // ldr x0, [sp], #16
    POPX1 = 0xf84107e1, // ldr x1, [sp], #16
    CALL = 0xd63f0280, // blr x20
    CALLSLOT = 0xffffffff, // not a real instruction, used to emit a constant
};

fn binOp(comptime op: u32, comptime swap: bool) []const u32 {
    var p1 = Ops.POPX0;
    var p2 = Ops.POPX1;
    if (swap) {
        p1 = Ops.POPX1;
        p2 = Ops.POPX0;
    }
    return &[_]u32{
        @intFromEnum(p1),
        @intFromEnum(p2),
        op,
        @intFromEnum(Ops.PUSHX0),
    };
}

const words = std.ComptimeStringMap([]const u32, .{
    // a b -- a+b
    .{ "+", binOp(0x8b010000, false) }, // add x0, x0, x1
    // a b -- a-b
    .{ "-", binOp(0xcb010000, true) }, // sub x0, x1, x0
    // a b -- a*b
    .{ "*", binOp(0x9b017c00, false) }, // mul x0, x0, x1
    // a b -- a/b
    .{ "/", binOp(0x9ac10c00, true) }, // sdiv x0, x1, x0
    // a -- a a
    .{ "dup", &[_]u32{
        @intFromEnum(Ops.POPX0),
        @intFromEnum(Ops.PUSHX0),
        @intFromEnum(Ops.PUSHX0),
    } },
    // a b -- b a
    .{ "swap", &[_]u32{
        @intFromEnum(Ops.POPX0),
        @intFromEnum(Ops.POPX1),
        @intFromEnum(Ops.PUSHX0),
        @intFromEnum(Ops.PUSHX1),
    } },
    // a --
    .{ "drop", &[_]u32{
        @intFromEnum(Ops.POPX0),
    } },
    // a b -- a b a
    .{ "over", &[_]u32{
        @intFromEnum(Ops.POPX0),
        @intFromEnum(Ops.POPX1),
        @intFromEnum(Ops.PUSHX1),
        @intFromEnum(Ops.PUSHX0),
        @intFromEnum(Ops.PUSHX1),
    } },
    // a b -- b
    .{ "nip", &[_]u32{
        @intFromEnum(Ops.POPX0),
        @intFromEnum(Ops.POPX1),
        @intFromEnum(Ops.PUSHX0),
    } },
    // a b -- b a b
    .{ "tuck", &[_]u32{
        @intFromEnum(Ops.POPX0),
        @intFromEnum(Ops.POPX1),
        @intFromEnum(Ops.PUSHX0),
        @intFromEnum(Ops.PUSHX1),
        @intFromEnum(Ops.PUSHX0),
    } },
});

var dynWords: std.StringHashMap([]const u32) = std.StringHashMap([]const u32).init(std.heap.page_allocator);

fn findWord(word: []const u8) ?[]const u32 {
    return words.get(word) orelse dynWords.get(word);
}

// parser
const Parser = struct {
    code: []const u8,
    pos: usize,

    const Token = union(enum) {
        Number: i64,
        Word: []const u8,
    };

    fn init(code: []const u8) Parser {
        return Parser{
            .code = code,
            .pos = 0,
        };
    }

    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    fn isWhitespace(c: u8) bool {
        return c == ' ' or c == '\n' or c == '\r' or c == '\t';
    }

    fn nextToken(self: *Parser) ?Token {
        while (self.pos < self.code.len and isWhitespace(self.code[self.pos])) {
            self.pos += 1;
        }
        if (self.pos >= self.code.len) {
            return null;
        }
        var c = self.code[self.pos];
        const start = self.pos;
        if (isDigit(c)) {
            while (self.pos < self.code.len and isDigit(self.code[self.pos])) {
                self.pos += 1;
            }
            return Token{ .Number = std.fmt.parseInt(i64, self.code[start..self.pos], 10) catch 2137 };
        }
        while (self.pos < self.code.len and !isWhitespace(self.code[self.pos])) {
            self.pos += 1;
        }
        return Token{ .Word = self.code[start..self.pos] };
    }
};

// compiler
const Compiler = struct {
    parser: *Parser,
    code: std.ArrayList(u32),
    prev: u32 = 0,

    fn init(parser: *Parser) Compiler {
        return Compiler{
            .code = std.ArrayList(u32).init(std.heap.page_allocator),
            .parser = parser,
        };
    }

    fn emit(self: *Compiler, instr: u32) !void {
        if (self.prev == @intFromEnum(Ops.PUSHX0) and instr == @intFromEnum(Ops.POPX0)) {
            _ = self.code.pop();
            if (self.code.items.len == 0) {
                self.prev = 0;
            } else {
                self.prev = self.code.getLast();
            }
            return;
        }
        try self.code.append(instr);
        self.prev = instr;
    }

    fn emitWord(self: *Compiler, word: []const u32) !void {
        var i: usize = 0;
        std.debug.print("emitWord: {x}\n", .{word});
        while (true) {
            const instr = word[i];
            std.debug.print("emit {x}\n", .{instr});
            if (instr == @intFromEnum(Ops.CALLSLOT)) {
                const lo: u64 = word[i + 1];
                const hi: u64 = word[i + 2];
                const fun: u64 = lo | (hi << 32);
                std.debug.print("emit call to {x}\n", .{fun});
                try self.emitNumber(fun, 20);
                try self.emitCall(20);
                i += 3;
            } else {
                try self.emit(instr);
                i += 1;
            }
            if (i >= word.len) {
                break;
            }
        }
    }

    fn emitPush(self: *Compiler) !void {
        // str x0, [sp, #-16]!
        try self.emit(@intFromEnum(Ops.PUSHX0));
    }

    fn emitPop(self: *Compiler) !void {
        // ldr x0, [sp], #16
        try self.emit(@intFromEnum(Ops.POPX0));
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

    fn emitCall(self: *Compiler, r: u5) !void {
        try self.emit(0xd63f0000 | @as(u32, @intCast(r)) << 5);
    }

    fn compileToken(self: *Compiler, token: Parser.Token) !void {
        switch (token) {
            .Number => {
                const n = @as(u64, @bitCast(token.Number));
                try self.emitNumber(n, 0);
                try self.emitPush();
            },
            .Word => {
                std.debug.print("compiling {s}\n", .{token.Word});
                const word = findWord(token.Word);
                if (word) |w| {
                    std.debug.print("src: {x}\n", .{w});
                    try self.emitWord(w);
                } else {
                    std.debug.print("unknown word: {s}\n", .{token.Word});
                    return;
                }
            },
        }
    }

    fn enter(self: *Compiler) !void {
        // stp x29, x30, [sp, #0x10]!
        try self.emit(0xa9bf7bfd);
        // mov x29, sp
        try self.emit(0x910003fd);
    }

    fn leave(self: *Compiler) !void {
        // mov sp, x29
        try self.emit(0x910003bf);
        // ldp x29, x30, [sp], #0x10
        try self.emit(0xa8c17bfd);
        // ret
        try self.emit(0xd65f03c0);
    }

    fn compile(self: *Compiler) ![]u32 {
        try self.enter();

        var token = self.parser.nextToken();
        while (token != null) : (token = self.parser.nextToken()) {
            try self.compileToken(token.?);
        }

        try self.emitPop();
        try self.leave();

        return self.code.toOwnedSlice();
    }
};

fn jitRun(code: []u32) !i64 {
    // allocate executable memory with mmap
    var mem = try std.os.mmap(null, std.mem.page_size, std.os.PROT.READ | std.os.PROT.WRITE, std.os.MAP.PRIVATE | std.os.MAP.ANONYMOUS, -1, 0);

    std.debug.print("code at: {*}\n", .{mem.ptr});

    // copy code to the new memory
    @memcpy(mem[0 .. code.len * @sizeOf(u32)], std.mem.sliceAsBytes(code));

    // set the protection to read and execute only
    try std.os.mprotect(mem, std.os.PROT.READ | std.os.PROT.EXEC);

    // cast the memory to a function pointer and call
    var fun: *const fn () i64 = @ptrCast(mem);
    return fun();
}

fn run(src: []const u8) !i64 {
    var parser = Parser.init(src);
    var compiler = Compiler.init(&parser);
    var code = compiler.compile();
    if (code) |c| {
        _ = try std.io.getStdOut().write(std.mem.sliceAsBytes(c));
        const x = try jitRun(c);
        std.debug.print("result: {d}\n", .{x});
        return x;
    } else |err| {
        std.debug.print("error: {any}\n", .{err});
        return err;
    }
}

fn call10(fun: *const fn (i64) void) []const u32 {
    const f: u64 = @intFromPtr(fun);
    std.debug.print("call10: {x}\n", .{f});
    var buffer = std.ArrayList(u32).init(std.heap.page_allocator);
    const lo: u32 = @truncate(f);
    const hi: u32 = @truncate((f >> 32));

    buffer.append(@intFromEnum(Ops.POPX0)) catch unreachable;
    buffer.append(@intFromEnum(Ops.CALLSLOT)) catch unreachable;
    buffer.append(lo) catch unreachable;
    buffer.append(hi) catch unreachable;
    return buffer.toOwnedSlice() catch unreachable;
}

const Builtins = struct {
    fn print(a: i64) void {
        std.debug.print("{d}", .{a});
    }
};

pub fn main() !void {
    try dynWords.put(".", call10(&Builtins.print));
    _ = try run("2 10 .");
    return;
}
