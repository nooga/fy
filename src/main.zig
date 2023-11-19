const std = @import("std");

extern fn __clear_cache(start: usize, end: usize) callconv(.C) void;

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

const Fy = struct {
    fyalloc: std.mem.Allocator,
    userWords: std.StringHashMap(Word),
    dataStack: [DATASTACKSIZE]u64 = undefined,
    image: Image,

    const version = "v0.0.0";
    const DATASTACKSIZE = 512;

    fn init(allocator: std.mem.Allocator) Fy {
        const image = Image.init() catch @panic("failed to allocate image");
        return Fy{
            .userWords = std.StringHashMap(Word).init(allocator),
            .fyalloc = allocator,
            .image = image,
        };
    }

    fn deinit(self: *Fy) void {
        self.image.deinit();
        deinitUserWords(self);
        return;
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
        return;
    }

    const Value = i64;

    const Asm = struct {
        const @"str x0, [sp, #-16]!" = 0xf81f0fe0;
        const @"str x1, [sp, #-16]!" = 0xf81f0fe1;
        const @"ldr x0, [sp], #16" = 0xf84107e0;
        const @"ldr x1, [sp], #16" = 0xf84107e1;
        const @"stp x29, x30, [sp, #0x10]!" = 0xa9bf7bfd;
        const @"ldp x29, x30, [sp], #0x10" = 0xa8c17bfd;

        const @"str x0, [x21, #-8]!" = 0xf81f8ea0;
        const @"str x1, [x21, #-8]!" = 0xf81f8ea1;

        const @"ldr x0, [x21], #8" = 0xf84086a0;
        const @"ldr x1, [x21], #8" = 0xf84086a1;

        const @"mov x29, sp" = 0x910003fd;
        const @"mov sp, x29" = 0x910003bf;

        const @"mov x0, #0" = 0xd2800000;
        const @"mov x0, #1" = 0xd2800020;

        const @"add x0, x0, x1" = 0x8b010000;
        const @"sub x0, x1, x0" = 0xcb010000;
        const @"mul x0, x0, x1" = 0x9b017c00;
        const @"sdiv x0, x1, x0" = 0x9ac10c00;

        const @"cmp x0, x1" = 0xeb01001f;

        const @"b 2" = 0x14000002;

        const @"beq #2" = 0x54000060;
        const @"bne #2" = 0x54000061;
        const @"bgt #2" = 0x5400006c;
        const @"blt #2" = 0x5400006b;
        const @"bge #2" = 0x5400006a;
        const @"ble #2" = 0x5400006d;

        const @"blr x0" = 0xd63f0000;

        const ret = 0xd65f03c0;

        // pseudo instructions

        // call slot is used to indicate where to put the function call address and is replaced with the actual address
        const CALLSLOT = 0xffffffff;

        const @".push x0" = @"str x0, [x21, #-8]!"; //@"str x0, [sp, #-16]!";
        const @".push x1" = @"str x1, [x21, #-8]!"; //@"str x1, [sp, #-16]!";
        const @".pop x0" = @"ldr x0, [x21], #8"; //@"ldr x0, [sp], #16";
        const @".pop x1" = @"ldr x1, [x21], #8"; //@"ldr x1, [sp], #16";

        // register used to store call address: x20
        const REGCALL = 20;

        // helpers
        fn @"blr Xn"(n: u5) u32 {
            return @"blr x0" | @as(u32, @intCast(n)) << 5;
        }

        fn @".pop xn"(n: usize) u32 {
            return @".pop x0" + @as(u32, @intCast(n));
        }
    };

    const Word = struct {
        code: []const u32, //machine code
        c: usize, //consumes
        p: usize, //produces
        callSlot: ?*const void,

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
            code[i] = Asm.@".pop xn"(i);
        }

        // call the function and push the result
        if (returnCount == 1) {
            code[codeLen - 2] = Asm.CALLSLOT;
            code[codeLen - 1] = Asm.@".push x0";
        } else {
            code[codeLen - 1] = Asm.CALLSLOT;
        }

        return Word{
            .code = &code,
            .c = paramCount,
            .p = returnCount,
            .callSlot = @ptrCast(&fun),
        };
    }

    fn binOp(comptime op: u32, comptime swap: bool) Word {
        var p1 = Asm.@".pop x0";
        var p2 = Asm.@".pop x1";
        if (swap) {
            p1 = Asm.@".pop x1";
            p2 = Asm.@".pop x0";
        }
        const code = &[_]u32{
            p1,
            p2,
            op,
            Asm.@".push x0",
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
            Asm.@".pop x0",
            Asm.@".pop x1",
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
            .callSlot = null,
        };
    }

    const Builtins = struct {
        fn print(a: Value) void {
            std.io.getStdOut().writer().print("{d}\n", .{a}) catch std.debug.print("{d}\n", .{a});
        }
        fn printHex(a: Value) void {
            std.io.getStdOut().writer().print("{x}\n", .{a}) catch std.debug.print("{x}\n", .{a});
        }
        fn spy(a: Value) Value {
            print(a);
            return a;
        }
    };

    const words = std.ComptimeStringMap(Word, .{
        // a b -- a+b
        .{ "+", binOp(Asm.@"add x0, x0, x1", false) },
        // a b -- a-b
        .{ "-", binOp(Asm.@"sub x0, x1, x0", true) },
        // a b -- a*b
        .{ "*", binOp(Asm.@"mul x0, x0, x1", false) },
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
        // a b -- b a
        .{ "swap", inlineWord(&[_]u32{ Asm.@".pop x0", Asm.@".pop x1", Asm.@".push x0", Asm.@".push x1" }, 2, 2) },
        // a --
        .{ "drop", inlineWord(&[_]u32{Asm.@".pop x0"}, 1, 0) },
        // a b -- a b a
        .{ "over", inlineWord(&[_]u32{ Asm.@".pop x0", Asm.@".pop x1", Asm.@".push x1", Asm.@".push x0", Asm.@".push x1" }, 2, 3) },
        // a b -- b
        .{ "nip", inlineWord(&[_]u32{ Asm.@".pop x0", Asm.@".pop x1", Asm.@".push x0" }, 2, 1) },
        // a b -- b a b
        .{ "tuck", inlineWord(&[_]u32{ Asm.@".pop x0", Asm.@".pop x1", Asm.@".push x0", Asm.@".push x1", Asm.@".push x0" }, 2, 3) },
        // a --
        .{ ".", fnToWord(Builtins.print) },
        // a --
        .{ ".hex", fnToWord(Builtins.printHex) },
        // a -- a
        .{ "spy", fnToWord(Builtins.spy) },
        // ? -- ?
        .{ "call", inlineWord(&[_]u32{ Asm.@".pop x0", Asm.@"blr Xn"(0) }, 0, 0) },
    });

    fn findWord(self: *Fy, word: []const u8) ?Word {
        return self.userWords.get(word) orelse words.get(word);
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
            if (c == ':') {
                self.pos += 1;
                return Token{ .Word = Word.DEFINE };
            }
            if (c == ';') {
                self.pos += 1;
                return Token{ .Word = Word.END };
            }
            if (c == '[') {
                self.pos += 1;
                return Token{ .Word = Word.QUOTE_OPEN };
            }
            if (c == ']') {
                self.pos += 1;
                return Token{ .Word = Word.QUOTE_END };
            }
            if (isDigit(c)) {
                while (self.pos < self.code.len and isDigit(self.code[self.pos])) {
                    self.pos += 1;
                }
                return Token{ .Number = std.fmt.parseInt(Value, self.code[start..self.pos], 10) catch 2137 };
            }
            while (self.pos < self.code.len and !isWhitespace(self.code[self.pos]) and self.code[self.pos] != ';' and self.code[self.pos] != ']') {
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
        fy: *Fy,

        const Error = error{
            ExpectedWord,
            UnexpectedEndOfInput,
            UnknownWord,
            OutOfMemory,
        };

        fn init(fy: *Fy, parser: *Parser) Compiler {
            return Compiler{
                .code = std.ArrayList(u32).init(fy.fyalloc),
                .parser = parser,
                .fy = fy,
            };
        }

        fn emit(self: *Compiler, instr: u32) !void {
            if (self.prev == Asm.@".push x0" and instr == Asm.@".pop x0") {
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
            while (true) {
                const instr = word.code[i];
                if (instr == Asm.CALLSLOT) {
                    const fun: u64 = @intFromPtr(word.callSlot);
                    try self.emitNumber(fun, Asm.REGCALL);
                    try self.emitCall(Asm.REGCALL);
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

        fn emitCall(self: *Compiler, r: u5) !void {
            try self.emit(Asm.@"blr Xn"(r));
        }

        fn compileToken(self: *Compiler, token: Parser.Token) Error!void {
            switch (token) {
                .Number => {
                    const n = @as(u64, @bitCast(token.Number));
                    try self.emitNumber(n, 0);
                    try self.emitPush();
                },
                .Word => {
                    const word = self.fy.findWord(token.Word);
                    if (word) |w| {
                        try self.emitWord(w);
                    } else {
                        std.debug.print("Unknown word: {s}\n", .{token.Word});
                        return Error.UnknownWord;
                    }
                },
            }
        }

        fn defineWord(self: *Compiler, name: []const u8, code: []u32) !void {
            var key: []u8 = undefined;
            if (self.fy.userWords.getPtr(name)) |oldword| {
                self.fy.fyalloc.free(oldword.code);
                key = @constCast(name);
            } else {
                key = try self.fy.fyalloc.dupe(u8, name);
            }
            try self.fy.userWords.put(key, Word{
                .code = code,
                .c = 0,
                .p = 0,
                .callSlot = null,
            });
        }

        const Wrap = enum {
            None,
            Quote,
            Function,
        };

        fn compileDefinition(self: *Compiler) Error!void {
            var name = self.parser.nextToken();
            if (name) |n| {
                switch (n) {
                    .Word => |w| {
                        var compiler = Compiler.init(self.fy, self.parser);
                        var code = try compiler.compile(.None);

                        try self.defineWord(w, code);
                    },
                    else => {
                        return Error.ExpectedWord;
                    },
                }
            } else {
                return Error.UnexpectedEndOfInput;
            }
        }

        fn compileQuote(self: *Compiler) Error!u64 {
            var compiler = Compiler.init(self.fy, self.parser);
            var code = try compiler.compile(.Quote);
            const executable = self.fy.image.link(code);
            compiler.fy.fyalloc.free(code);
            return @intFromPtr(executable.ptr);
        }

        fn enter(self: *Compiler) !void {
            try self.emit(Asm.@"stp x29, x30, [sp, #0x10]!");
            //try self.emit(Asm.@"mov x29, sp");

        }

        fn leave(self: *Compiler) !void {
            //try self.emit(Asm.@"mov sp, x29");
            try self.emit(Asm.@"ldp x29, x30, [sp], #0x10");
            try self.emit(Asm.ret);
        }

        fn compile(self: *Compiler, wrap: Wrap) Error![]u32 {
            switch (wrap) {
                .None => {},
                .Quote => {
                    try self.enter();
                },
                .Function => {
                    try self.enter();
                    try self.emitNumber(@intFromPtr(&self.fy.dataStack) + DATASTACKSIZE, 21);
                    try self.emitNumber(0, 0);
                    try self.emitPush();
                },
            }
            var token = self.parser.nextToken();
            while (token != null) : (token = self.parser.nextToken()) {
                switch (token.?) {
                    .Word => |w| {
                        if (std.mem.eql(u8, w, Word.END) or std.mem.eql(u8, w, Word.QUOTE_END)) {
                            break;
                        }
                        if (std.mem.eql(u8, w, Word.DEFINE)) {
                            try self.compileDefinition();
                            continue;
                        }
                        if (std.mem.eql(u8, w, Word.QUOTE_OPEN)) {
                            const target = try self.compileQuote();
                            try self.emitNumber(target, 0);
                            try self.emitPush();
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
                    try self.leave();
                },
                .Function => {
                    try self.emitPop();
                    try self.leave();
                },
            }
            return self.code.toOwnedSlice();
        }

        fn compileFn(self: *Compiler) ![]u32 {
            return self.compile(.Function);
        }
    };

    const Image = struct {
        mem: []align(std.mem.page_size) u8,
        end: usize,

        fn init() !Image {
            const mem = try std.os.mmap(null, std.mem.page_size, std.os.PROT.READ | std.os.PROT.WRITE, std.os.MAP.PRIVATE | std.os.MAP.ANONYMOUS, -1, 0);
            return Image{
                .mem = mem,
                .end = 0,
            };
        }

        fn deinit(self: *Image) void {
            std.os.munmap(self.mem);
        }

        fn grow(self: *Image) !void {
            const oldlen = self.mem.len;
            const newlen = oldlen + std.mem.page_size;
            var new = try std.os.mmap(null, newlen, std.os.PROT.READ | std.os.PROT.WRITE, std.os.MAP.PRIVATE | std.os.MAP.ANONYMOUS, -1, 0);
            @memcpy(new, self.mem);
            std.os.munmap(self.mem);
            self.mem = new;
        }

        fn protect(self: *Image, executable: bool) !void {
            if (executable) {
                try std.os.mprotect(self.mem, std.os.PROT.READ | std.os.PROT.EXEC);
            } else {
                try std.os.mprotect(self.mem, std.os.PROT.READ | std.os.PROT.WRITE);
            }
        }

        fn link(self: *Image, code: []u32) []u8 {
            const len: usize = code.len * @sizeOf(u32);
            const memlen = self.mem.len;
            if (self.end + len > memlen) {
                self.grow() catch @panic("failed to grow image");
            } else {
                self.protect(false) catch @panic("failed to set image writable");
            }
            const new = self.end;
            self.end += len;
            @memcpy(self.mem[new..self.end], std.mem.sliceAsBytes(code));
            self.protect(true) catch @panic("failed to set image executable");
            __clear_cache(@intFromPtr(self.mem.ptr), @intFromPtr(self.mem.ptr) + self.end);
            return self.mem[new..self.end];
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
        var fun: *const fn () Value = @alignCast(@ptrCast(executable));
        return Fn{ .call = fun };
    }

    fn run(self: *Fy, src: []const u8) !Fy.Value {
        var parser = Fy.Parser.init(src);
        var compiler = Fy.Compiler.init(self, &parser);
        var code = compiler.compileFn();

        if (code) |c| {
            var fyfn = try self.jit(c);
            const x = fyfn.call();
            return x;
        } else |err| {
            return err;
        }
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

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

    var fy = Fy.init(allocator);
    defer {
        fy.deinit();
    }

    try stdout.print("fy! {s}\n", .{Fy.version});

    while (true) {
        try stdout.print("fy> ", .{});
        const read = stdin.readUntilDelimiterAlloc(allocator, '\n', 1024);
        if (read) |line| {
            if (line.len == 0) {
                allocator.free(line);
                continue;
            }
            var result = fy.run(line);
            allocator.free(line);
            if (result) |r| {
                try stdout.print("    {d}\n", .{r});
            } else |err| {
                try stdout.print("error: {}\n", .{err});
            }
        } else |err| {
            if (err != error.EndOfStream) {
                try stdout.print("error: {}\n", .{err});
            }
            break;
        }
    }
    return;
}

// Tests below

const TestCase = struct {
    input: []const u8,
    expected: Fy.Value,

    fn run(self: *const TestCase, fy: *Fy) !void {
        std.debug.print("\nfy> {s}\n", .{self.input});
        var input = self.input;
        var result = try fy.run(input);
        std.debug.print("exp {d}\n    {d}\n", .{ self.expected, result });
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
        .{ .input = "", .expected = 0 }, //
        .{ .input = "1", .expected = 1 },
        .{ .input = "1 2", .expected = 2 },
        .{ .input = "1 2 +", .expected = 3 },
        .{ .input = "1 2 -", .expected = -1 },
        .{ .input = "2 2 *", .expected = 4 },
        .{ .input = "12 3 /", .expected = 4 },
        .{ .input = "1 2 =", .expected = 0 },
        .{ .input = "1 1 =", .expected = 1 },
        .{ .input = "1 2 !=", .expected = 1 },
        .{ .input = "1 1 !=", .expected = 0 },
        .{ .input = "1 2 >", .expected = 0 },
        .{ .input = "2 1 >", .expected = 1 },
        .{ .input = "1 2 <", .expected = 1 },
        .{ .input = "2 1 <", .expected = 0 },
        .{ .input = "1 2 >=", .expected = 0 },
        .{ .input = "2 1 >=", .expected = 1 },
        .{ .input = "2 2 >=", .expected = 1 },
        .{ .input = "1 2 <=", .expected = 1 },
        .{ .input = "2 1 <=", .expected = 0 },
        .{ .input = "2 2 <=", .expected = 1 },
        .{ .input = "2 dup", .expected = 2 },
        .{ .input = "2 3 swap", .expected = 2 },
        .{ .input = "2 3 over", .expected = 2 },
        .{ .input = "2 3 nip", .expected = 3 },
        .{ .input = "2 3 tuck", .expected = 3 },
        .{ .input = "2 3 drop", .expected = 2 },
    });
}

test "User defined words" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();

    try runCases(&fy, &[_]TestCase{
        .{ .input = ": sqr dup * ;", .expected = 0 },
        .{ .input = "2 sqr", .expected = 4 },
        .{ .input = ":sqr dup *; 2 sqr", .expected = 4 },
        .{ .input = ": sqr dup * ; 2 sqr", .expected = 4 },
        .{ .input = ":a 1; a a +", .expected = 2 },
        .{ .input = ": a 2 +; :b 3 +; 1 a b 6 =", .expected = 1 },
        .{ .input = "1 a b", .expected = 6 },
        .{ .input = "2 dup :dup *; dup", .expected = 4 }, // warning: this breaks dup in this Fy instance forever
    });
}

test "Quotes" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();

    try runCases(&fy, &[_]TestCase{
        .{ .input = "2 [dup +] call", .expected = 4 },
        .{ .input = "[dup +] 3 swap call", .expected = 6 },
        .{ .input = ":dup+ [dup +]; 5 dup+ call", .expected = 10 },
    });
}
