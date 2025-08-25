const std = @import("std");
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

const Fy = struct {
    fyalloc: std.mem.Allocator,
    userWords: std.StringHashMap(Word),
    dataStack: [DATASTACKSIZE]Value = undefined,
    image: Image,
    stringHeap: StringHeap,

    const version = "v0.0.1";
    const DATASTACKSIZE = 512;

    // Tagged value constants
    const TAG_INT = 0;
    const TAG_STR = 1;
    const TAG_MASK = 1;
    const TAG_BITS = 1;

    // Value is a tagged pointer - lowest bit indicates type:
    // 0 = integer, 1 = string reference
    const Value = i64;

    fn makeInt(n: i64) Value {
        return n;
    }

    fn makeStr(id: usize) Value {
        return @as(Value, @intCast(id)) | TAG_STR;
    }

    fn isInt(v: Value) bool {
        return v & TAG_MASK == TAG_INT;
    }

    fn isStr(v: Value) bool {
        return v & TAG_MASK == TAG_STR;
    }

    fn getInt(v: Value) i64 {
        std.debug.assert(isInt(v));
        return v;
    }

    fn getStrId(v: Value) usize {
        std.debug.assert(isStr(v));
        return @intCast(v & ~@as(Value, TAG_MASK));
    }

    fn init(allocator: std.mem.Allocator) Fy {
        const image = Image.init() catch @panic("failed to allocate image");
        return Fy{
            .userWords = std.StringHashMap(Word).init(allocator),
            .fyalloc = allocator,
            .image = image,
            .stringHeap = StringHeap.init(allocator),
        };
    }

    fn deinit(self: *Fy) void {
        self.image.deinit();
        self.stringHeap.deinit();
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

    // String heap for string storage and management
    const StringHeap = struct {
        allocator: std.mem.Allocator,
        strings: std.ArrayList([]u8),

        fn init(allocator: std.mem.Allocator) StringHeap {
            return StringHeap{
                .allocator = allocator,
                .strings = std.ArrayList([]u8).init(allocator),
            };
        }

        fn deinit(self: *StringHeap) void {
            for (self.strings.items) |str| {
                self.allocator.free(str);
            }
            self.strings.deinit();
        }

        fn store(self: *StringHeap, str: []const u8) !Value {
            const newStr = try self.allocator.alloc(u8, str.len);
            @memcpy(newStr, str);
            try self.strings.append(newStr);
            return makeStr(self.strings.items.len - 1);
        }

        fn get(self: *StringHeap, v: Value) []const u8 {
            std.debug.assert(isStr(v));
            const id = getStrId(v);
            if (id >= self.strings.items.len) {
                // Return a placeholder for invalid IDs
                return "<invalid string>";
            }
            return self.strings.items[id];
        }

        fn concat(self: *StringHeap, a: Value, b: Value) !Value {
            const strA = self.get(a);
            const strB = self.get(b);
            const newLen = strA.len + strB.len;
            var newStr = try self.allocator.alloc(u8, newLen);
            @memcpy(newStr[0..strA.len], strA);
            @memcpy(newStr[strA.len..], strB);
            try self.strings.append(newStr);
            const newId = self.strings.items.len - 1;
            std.debug.print("Concatenated result: ID={d}, content=\"{s}\"\n", .{ newId, newStr });
            return makeStr(newId);
        }

        fn length(self: *StringHeap, v: Value) Value {
            const str = self.get(v);
            return makeInt(@as(i64, @intCast(str.len)));
        }
    };

    const Word = struct {
        code: []const u32, //machine code
        c: usize, //consumes
        p: usize, //produces
        callSlot: ?*const anyopaque,

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
            .callSlot = &fun,
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
            .callSlot = null,
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
            .callSlot = null,
        };
    }

    const Builtins = struct {
        fn print(a: Value) void {
            if (isInt(a)) {
                const i = getInt(a);
                std.io.getStdOut().writer().print("{d}\n", .{i}) catch std.debug.print("{d}\n", .{i});
            } else if (isStr(a)) {
                const fy = @as(*Fy, @ptrFromInt(fyPtr));
                const id = getStrId(a);
                // Check if the ID is valid
                if (id < fy.stringHeap.strings.items.len) {
                    const s = fy.stringHeap.get(a);
                    std.io.getStdOut().writer().print("{s}\n", .{s}) catch std.debug.print("{s}\n", .{s});
                } else {
                    std.io.getStdOut().writer().print("<invalid string: {d}>\n", .{id}) catch std.debug.print("<invalid string: {d}>\n", .{id});
                }
            } else {
                std.io.getStdOut().writer().print("<unknown value type>\n", .{}) catch std.debug.print("<unknown value type>\n", .{});
            }
        }

        fn printHex(a: Value) void {
            if (isInt(a)) {
                const i = getInt(a);
                std.io.getStdOut().writer().print("0x{x}\n", .{i}) catch std.debug.print("0x{x}\n", .{i});
            } else if (isStr(a)) {
                const fy = @as(*Fy, @ptrFromInt(fyPtr));
                const id = getStrId(a);
                // Check if the ID is valid
                if (id < fy.stringHeap.strings.items.len) {
                    const s = fy.stringHeap.get(a);
                    std.io.getStdOut().writer().print("\"{s}\"\n", .{s}) catch std.debug.print("\"{s}\"\n", .{s});
                } else {
                    std.io.getStdOut().writer().print("<invalid string: {d}>\n", .{id}) catch std.debug.print("<invalid string: {d}>\n", .{id});
                }
            } else {
                std.io.getStdOut().writer().print("<unknown value type>\n", .{}) catch std.debug.print("<unknown value type>\n", .{});
            }
        }

        fn printNewline() void {
            std.io.getStdOut().writer().print("\n", .{}) catch std.debug.print("\n", .{});
        }

        fn printChar(a: Value) void {
            if (isInt(a)) {
                const i = getInt(a);
                std.io.getStdOut().writer().print("{c}", .{@as(u8, @intCast(i))}) catch std.debug.print("{c}", .{@as(u8, @intCast(i))});
            } else if (isStr(a)) {
                const fy = @as(*Fy, @ptrFromInt(fyPtr));
                const id = getStrId(a);
                // Check if the ID is valid
                if (id < fy.stringHeap.strings.items.len) {
                    const s = fy.stringHeap.get(a);
                    if (s.len > 0) {
                        std.io.getStdOut().writer().print("{c}", .{s[0]}) catch std.debug.print("{c}", .{s[0]});
                    } else {
                        std.io.getStdOut().writer().print("<empty string>", .{}) catch std.debug.print("<empty string>", .{});
                    }
                } else {
                    std.io.getStdOut().writer().print("<invalid string: {d}>", .{id}) catch std.debug.print("<invalid string: {d}>", .{id});
                }
            } else {
                std.io.getStdOut().writer().print("<unknown value type>", .{}) catch std.debug.print("<unknown value type>", .{});
            }
        }

        fn spy(a: Value) Value {
            print(a);
            return a;
        }

        fn spyStack(base: Value, end: Value) void {
            const w = std.io.getStdOut().writer();
            const p: [*]Value = @ptrFromInt(@as(usize, @intCast(getInt(base))));
            const l: usize = @intCast(getInt(end - base));
            const len: usize = l / @sizeOf(Value);
            const s: []Value = p[0..len];
            w.print("--| ", .{}) catch std.debug.print("--| ", .{});
            for (2..len + 1) |v| {
                w.print("{} ", .{s[len - v]}) catch std.debug.print("{} ", .{s[len - v]});
            }
            w.print("\n", .{}) catch std.debug.print("\n", .{});
        }

        // Keep a pointer to the Fy instance for string operations
        var fyPtr: usize = 0;

        // String concatenation
        fn strConcat(a: Value, b: Value) Value {
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            // Debug output to trace values
            const strA = fy.stringHeap.get(a);
            const strB = fy.stringHeap.get(b);
            std.debug.print("Concatenating: \"{s}\" + \"{s}\"\n", .{ strA, strB });
            return fy.stringHeap.concat(a, b) catch @panic("String concatenation failed");
        }

        // String length
        fn strLen(a: Value) Value {
            if (!isStr(a)) {
                @panic("Expected string for length");
            }
            const fy = @as(*Fy, @ptrFromInt(fyPtr));
            return fy.stringHeap.length(a);
        }

        // Type checking
        fn isString(a: Value) Value {
            return makeInt(@as(i64, @intFromBool(isStr(a))));
        }

        fn isInteger(a: Value) Value {
            return makeInt(@as(i64, @intFromBool(isInt(a))));
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
        // x f -- x
        .{ "dip", inlineWord(&[_]u32{
            Asm.@".pop x0, x1",
            Asm.@".rpush x1",
            Asm.@"blr Xn"(0),
            Asm.@".rpop x1",
            Asm.@".push x1",
        }, 2, 1) },
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
            .callSlot = &Builtins.spyStack,
        } },
        // a -- a + 1
        .{ "1+", inlineWord(&[_]u32{ Asm.@".pop x0", Asm.@"add x0, x0, #1", Asm.@".push x0" }, 1, 1) },
        // a -- a - 1
        .{ "1-", inlineWord(&[_]u32{ Asm.@".pop x0", Asm.@"sub x0, x0, #1", Asm.@".push x0" }, 1, 1) },
        // ... f -- f(...)
        .{ "do", inlineWord(&[_]u32{ Asm.@".pop x0", Asm.@"blr Xn"(0) }, 0, 0) },
        // ... ft -- ft(...) | ...
        .{
            "do?", inlineWord(&[_]u32{
                Asm.@".pop x1, x0", //
                Asm.@"cbz Xn, offset"(0, 2),
                Asm.@"blr Xn"(1),
            }, 0, 1),
        },
        // ... c ft ff -- ft(...) | ff(...)
        .{
            "ifte", inlineWord(&[_]u32{
                Asm.@".pop x1, x0", //
                Asm.@".pop Xn"(2),
                Asm.@"cmp x2, #0",
                Asm.@"csel x0, x0, x1, ne",
                Asm.@"blr Xn"(0),
            }, 0, 1),
        },
        // ... n f -- ...
        .{
            "dotimes", inlineWord(&[_]u32{
                Asm.@".pop x0", // function pointer
                Asm.@".pop x1", // counter
                // Check if counter <= 0, exit early if so
                Asm.@"cbz Xn, offset"(1, 7), // Skip if counter is 0
                // Loop start:
                Asm.@".push x0", // Save function pointer
                Asm.@".push x1", // Save counter
                Asm.@"blr x0", // Call the function
                Asm.@".pop x1", // Restore counter
                Asm.@".pop x0", // Restore function pointer
                // Move counter to x0, decrement, and move back
                Asm.@"mov x0, x1", // Move counter to x0
                Asm.@"sub x0, x0, #1", // Decrement using available instruction
                Asm.@"mov x1, x0", // Move back to x1
                Asm.@"cbnz Xn, offset"(1, 2), // Skip the branch if counter is 0
                Asm.@"b offset"(-7), // Jump back to loop start
                // End of loop
            }, 2, 0),
        },
        // ... f -- ...
        // repeat the quote until the top of the stack is 0
        .{ "repeat", inlineWord(&[_]u32{
            Asm.@".pop x0",
            Asm.@"cbz Xn, offset"(0, 2),
            Asm.@"blr Xn"(0),
            Asm.@"b offset"(-2),
        }, 1, 0) },
        // recur --
        .{ "recur", inlineWord(&[_]u32{Asm.RECUR}, 0, 0) },
        // String operations
        .{ "s.", fnToWord(Builtins.print) }, // Print string or number
        .{ "s+", fnToWord(Builtins.strConcat) }, // Concatenate strings
        .{ "slen", fnToWord(Builtins.strLen) }, // String length
        .{ "string?", fnToWord(Builtins.isString) }, // Check if value is string
        .{ "int?", fnToWord(Builtins.isInteger) }, // Check if value is integer
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

        fn nextToken(self: *Parser) ?Token {
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
                    @panic("Unbalanced parentheses in comment");
                }
                return self.nextToken();
            }
            if (c == '\'') {
                self.pos += 1;
                if (self.pos >= self.code.len) {
                    @panic("Expected character after '\\''");
                }
                c = self.code[self.pos];
                const charValue = @as(i64, c);
                self.pos += 1;
                return Token{ .Number = charValue };
            }
            if (c == ':') {
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
                    @panic("Unterminated string literal");
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
                    const value = std.fmt.parseInt(i64, self.code[start..self.pos], 10) catch 2137;
                    return Token{ .Number = value };
                }
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
                .parser = parser,
                .fy = fy,
            };
        }

        fn deinit(self: *Compiler) void {
            self.code.deinit();
        }

        fn emit(self: *Compiler, instr: u32) !void {
            try self.code.append(instr);
            self.prev = instr;
        }

        fn emitWord(self: *Compiler, word: Word) !void {
            var i: usize = 0;
            const pos = self.code.items.len;
            while (true) {
                const instr = word.code[i];
                if (instr == Asm.CALLSLOT) {
                    const fun: u64 = @intFromPtr(word.callSlot);
                    try self.emitNumber(fun, Asm.REGCALL);
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

        fn emitCall(self: *Compiler, r: u5) !void {
            try self.emit(Asm.@"blr Xn"(r));
        }

        fn compileToken(self: *Compiler, token: Parser.Token) Error!void {
            switch (token) {
                .Number => |n| {
                    try self.emitNumber(@as(u64, @bitCast(Fy.makeInt(n))), 0);
                    try self.emitPush();
                },
                .Word => |w| {
                    const word = self.fy.findWord(w);
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

                    // Store the string in the heap
                    const strValue = try self.fy.stringHeap.store(unescaped);
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
                    .callSlot = null,
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
        };

        fn compileDefinition(self: *Compiler) Error!void {
            const name = self.parser.nextToken();
            if (name) |n| {
                switch (n) {
                    .Word => |w| {
                        var compiler = Compiler.init(self.fy, self.parser);
                        defer compiler.deinit();

                        try self.declareWord(w);

                        const code = try compiler.compile(.None);

                        try self.defineWord(w, code);
                        // Free the code after it's been copied to the word definition
                        self.fy.fyalloc.free(code);
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
            defer compiler.deinit();
            const code = try compiler.compile(.Quote);
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
                    try self.emitNumber(@intFromPtr(&self.fy.dataStack) + DATASTACKSIZE, 22);
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

    // const TableEntry = struct {
    //     length: usize,
    // };

    const Image = struct {
        mem: []align(std.mem.page_size) u8,
        end: usize,
        // table: std.AutoHashMap(usize, TableEntry),
        fn init() !Image {
            // flags: std.posix.MAP.PRIVATE | std.posix.MAP.ANONYMOUS = 3
            const mem = try std.posix.mmap(null, std.mem.page_size, std.posix.PROT.READ | std.posix.PROT.WRITE, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0);
            return Image{
                .mem = mem,
                .end = 0,
            };
        }

        fn deinit(self: *Image) void {
            std.posix.munmap(self.mem);
        }

        fn grow(self: *Image) !void {
            const oldlen = self.mem.len;
            const newlen = oldlen + std.mem.page_size;
            // flags: std.posix.MAP.PRIVATE | std.posix.MAP.ANONYMOUS = 3
            const new = try std.posix.mmap(null, newlen, std.posix.PROT.READ | std.posix.PROT.WRITE, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0);
            @memcpy(new, self.mem);
            std.posix.munmap(self.mem);
            self.mem = new;
        }

        fn protect(self: *Image, executable: bool) !void {
            if (executable) {
                try std.posix.mprotect(self.mem, std.posix.PROT.READ | std.posix.PROT.EXEC);
            } else {
                try std.posix.mprotect(self.mem, std.posix.PROT.READ | std.posix.PROT.WRITE);
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
            //debugSlice(self.mem[new..self.end], self.end - new);
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

    fn run(self: *Fy, src: []const u8) !Fy.Value {
        // Set fyPtr for Builtins to access stringHeap
        Builtins.fyPtr = @intFromPtr(self);

        var parser = Fy.Parser.init(src);
        var compiler = Fy.Compiler.init(self, &parser);
        defer compiler.deinit();
        const code = compiler.compileFn();

        if (code) |c| {
            var fyfn = try self.jit(c);
            const x = fyfn.call();
            //self.image.reset();
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
        const result = fy.run(line);
        if (result) |r| {
            if (Fy.isInt(r)) {
                try stdout.print("    {d}\n", .{Fy.getInt(r)});
            } else if (Fy.isStr(r)) {
                const str = fy.stringHeap.get(r);
                try stdout.print("    \"{s}\"\n", .{str});
            } else {
                try stdout.print("    {x}\n", .{r});
            }
        } else |err| {
            try stdout.print("error: {}\n", .{err});
        }
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
    const result = fy.run(cleanSrc);
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
    _ = try file.write(fy.image.mem);
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
        //std.debug.print("eval: '{s}'\n", .{e});
        const result = fy.run(e);
        if (result) |r| {
            std.debug.print("{d}\n", .{r});
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
            if (Fy.isStr(v)) {
                const id = Fy.getStrId(v);
                const str = f.stringHeap.get(v);
                std.debug.print("DEBUG - {s}: id={d}, len={d}, content=\"{s}\"\n", .{ label, id, str.len, str });
            } else {
                std.debug.print("DEBUG - {s}: Not a string, value={d}\n", .{ label, v });
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
        std.debug.print("DEBUG - Length: {d}\n", .{result});
    }

    try runCases(&fy, &[_]TestCase{
        .{ .input = "\"hello\"", .expected = Fy.makeStr(9) },
        .{ .input = "\"hello\" slen", .expected = Fy.makeInt(5) },
        .{ .input = "\"hello\" \"world\" s+", .expected = Fy.makeStr(4) },
        .{ .input = "\"hello\" \"world\" s+ slen", .expected = Fy.makeInt(10) },
        .{ .input = "\"hello\" string?", .expected = Fy.makeInt(1) },
        .{ .input = "123 string?", .expected = Fy.makeInt(0) },
        .{ .input = "\"hello\" int?", .expected = Fy.makeInt(0) },
        .{ .input = "123 int?", .expected = Fy.makeInt(1) },
    });
}
