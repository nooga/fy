const std = @import("std");

const Value = i64;

const Ops = enum(u32) {
    PUSHX0 = 0xf81f0fe0, // str x0, [sp, #-16]!
    PUSHX1 = 0xf81f0fe1, // str x1, [sp, #-16]!
    POPX0 = 0xf84107e0, // ldr x0, [sp], #16
    POPX1 = 0xf84107e1, // ldr x1, [sp], #16
    CALL = 0xd63f0280, // blr x20
    CALLSLOT = 0xffffffff, // not a real instruction, used to emit a constant
};

const Word = struct {
    code: []const u32, //machine code
    c: usize, //consumes
    p: usize, //produces
    callSlot: ?*const void,
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
        code[i] = @intFromEnum(Ops.POPX0) | @as(u32, @intCast(i));
    }

    // call the function and push the result
    if (returnCount == 1) {
        code[codeLen - 2] = @intFromEnum(Ops.CALLSLOT);
        code[codeLen - 1] = @intFromEnum(Ops.PUSHX0);
    } else {
        code[codeLen - 1] = @intFromEnum(Ops.CALLSLOT);
    }

    return Word{
        .code = &code,
        .c = paramCount,
        .p = returnCount,
        .callSlot = @ptrCast(&fun),
    };
}

fn binOp(comptime op: u32, comptime swap: bool) Word {
    var p1 = Ops.POPX0;
    var p2 = Ops.POPX1;
    if (swap) {
        p1 = Ops.POPX1;
        p2 = Ops.POPX0;
    }
    const code = &[_]u32{
        @intFromEnum(p1),
        @intFromEnum(p2),
        op,
        @intFromEnum(Ops.PUSHX0),
    };
    return Word{
        .code = code,
        .c = 2,
        .p = 1,
        .callSlot = null,
    };
}

fn cmpOp(comptime op: u32) Word {
    return inlineWord(&[_]u32{
        @intFromEnum(Ops.POPX1),
        @intFromEnum(Ops.POPX0),
        0xeb01001f,
        op,
        0xd2800000,
        0x14000002,
        0xd2800020,
        @intFromEnum(Ops.PUSHX0),
    }, 2, 1);
}

fn inlineWord(comptime code: []const u32, comptime c: usize, comptime p: usize) Word {
    return Word{
        .code = code,
        .c = c,
        .p = p,
        .callSlot = null,
    };
}

const Builtins = struct {
    fn print(a: Value) void {
        std.debug.print("{d}\n", .{a});
    }
    fn spy(a: Value) Value {
        std.debug.print("spy: {d}\n", .{a});
        return a;
    }
};

const words = std.ComptimeStringMap(Word, .{
    // a b -- a+b
    .{ "+", binOp(0x8b010000, false) }, // add x0, x0, x1
    // a b -- a-b
    .{ "-", binOp(0xcb010000, true) }, // sub x0, x1, x0
    // a b -- a*b
    .{ "*", binOp(0x9b017c00, false) }, // mul x0, x0, x1
    // a b -- a/b
    .{ "/", binOp(0x9ac10c00, true) }, // sdiv x0, x1, x0
    .{ "=", cmpOp(0x54000060) },
    .{ "!=", cmpOp(0x54000061) },
    .{ ">", cmpOp(0x5400006c) },
    .{ "<", cmpOp(0x5400006b) },
    .{ ">=", cmpOp(0x5400006a) },
    .{ "<=", cmpOp(0x5400006d) },
    // a -- a a
    .{ "dup", inlineWord(&[_]u32{
        @intFromEnum(Ops.POPX0),
        @intFromEnum(Ops.PUSHX0),
        @intFromEnum(Ops.PUSHX0),
    }, 1, 2) },
    // a b -- b a
    .{ "swap", inlineWord(&[_]u32{
        @intFromEnum(Ops.POPX0),
        @intFromEnum(Ops.POPX1),
        @intFromEnum(Ops.PUSHX0),
        @intFromEnum(Ops.PUSHX1),
    }, 2, 2) },
    // a --
    .{ "drop", inlineWord(&[_]u32{
        @intFromEnum(Ops.POPX0),
    }, 1, 0) },
    // a b -- a b a
    .{ "over", inlineWord(&[_]u32{
        @intFromEnum(Ops.POPX0),
        @intFromEnum(Ops.POPX1),
        @intFromEnum(Ops.PUSHX1),
        @intFromEnum(Ops.PUSHX0),
        @intFromEnum(Ops.PUSHX1),
    }, 2, 3) },
    // a b -- b
    .{ "nip", inlineWord(&[_]u32{
        @intFromEnum(Ops.POPX0),
        @intFromEnum(Ops.POPX1),
        @intFromEnum(Ops.PUSHX0),
    }, 2, 1) },
    // a b -- b a b
    .{ "tuck", inlineWord(&[_]u32{
        @intFromEnum(Ops.POPX0),
        @intFromEnum(Ops.POPX1),
        @intFromEnum(Ops.PUSHX0),
        @intFromEnum(Ops.PUSHX1),
        @intFromEnum(Ops.PUSHX0),
    }, 2, 3) },
    .{ ".", fnToWord(Builtins.print) },
    .{ "spy", fnToWord(Builtins.spy) },
});

fn findWord(word: []const u8) ?Word {
    return words.get(word);
}

// parser
const Parser = struct {
    code: []const u8,
    pos: usize,

    const Token = union(enum) {
        Number: Value,
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
            return Token{ .Number = std.fmt.parseInt(Value, self.code[start..self.pos], 10) catch 2137 };
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

    fn emitWord(self: *Compiler, word: Word) !void {
        var i: usize = 0;
        std.debug.print("emitWord: {}\n", .{word});
        while (true) {
            const instr = word.code[i];
            std.debug.print("emit {x}\n", .{instr});
            if (instr == @intFromEnum(Ops.CALLSLOT)) {
                const fun: u64 = @intFromPtr(word.callSlot);
                std.debug.print("emit call to {x}\n", .{fun});
                try self.emitNumber(fun, 20);
                try self.emitCall(20);
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
                    std.debug.print("src: {}\n", .{w});
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

fn jitRun(code: []u32) !Value {
    // allocate executable memory with mmap
    var mem = try std.os.mmap(null, std.mem.page_size, std.os.PROT.READ | std.os.PROT.WRITE, std.os.MAP.PRIVATE | std.os.MAP.ANONYMOUS, -1, 0);

    std.debug.print("code at: {*}\n", .{mem.ptr});

    // copy code to the new memory
    @memcpy(mem[0 .. code.len * @sizeOf(u32)], std.mem.sliceAsBytes(code));

    // set the protection to read and execute only
    try std.os.mprotect(mem, std.os.PROT.READ | std.os.PROT.EXEC);

    // cast the memory to a function pointer and call
    var fun: *const fn () Value = @ptrCast(mem);
    return fun();
}

fn run(src: []const u8) !Value {
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

fn call10(fun: *const fn (Value) void) []const u32 {
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

pub fn main() !void {
    //_ = try run("10 dup * 300 + 4 6 * 4 - +");
    //_ = try run("69 spy");
    _ = try run("69 69 <=");

    return;
}
