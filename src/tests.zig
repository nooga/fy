const std = @import("std");
const Fy = @import("main.zig").Fy;

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

test "Curry, compose, each, filter" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();
    Fy.Builtins.fyPtr = @intFromPtr(&fy);

    try runCases(&fy, &[_]TestCase{
        // curry prepends value to quotation
        .{ .input = "3 5 [+] curry do", .expected = Fy.makeInt(8) },
        // compose chains two quotations
        .{ .input = "3 [2 *] [1+] compose do", .expected = Fy.makeInt(7) },
        // filter keeps matching elements
        .{ .input = "[1 2 3 4 5] [3 >] filter qhead", .expected = Fy.makeInt(4) },
        // filter length check
        .{ .input = "[1 2 3 4 5] [3 >] filter qlen", .expected = Fy.makeInt(2) },
        // each returns 0 (side-effect only)
        .{ .input = "[1 2 3] [drop] each", .expected = Fy.makeInt(0) },
        // qpush inlines single-item quotation (\ word syntax)
        .{ .input = "[1 2] [+] qpush qlen", .expected = Fy.makeInt(3) },
        // curry + map
        .{ .input = "[1 2 3] 10 [+] curry map qhead", .expected = Fy.makeInt(11) },
        // range generates [0..n-1]
        .{ .input = "5 range qlen", .expected = Fy.makeInt(5) },
        .{ .input = "5 range qhead", .expected = Fy.makeInt(0) },
        .{ .input = "5 range qtail qhead", .expected = Fy.makeInt(1) },
        // range + map
        .{ .input = "5 range [1+] map qhead", .expected = Fy.makeInt(1) },
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

test "Memory operations - alloc, !32, @32, free" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();

    try runCases(&fy, &[_]TestCase{
        // Store 42 at allocated address, load it back
        .{ .input = "32 alloc dup 42 swap !32 @32", .expected = Fy.makeInt(42) },
        // Store and load multiple values
        .{ .input = "16 alloc dup 10 swap !32 dup 4 + 20 swap !32 dup @32 swap 4 + @32 +", .expected = Fy.makeInt(30) },
        // Free returns 0
        .{ .input = "8 alloc free", .expected = Fy.makeInt(0) },
    });
}

test "Callbacks - callback: with ccall" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();

    try runCases(&fy, &[_]TestCase{
        // 1-arg callback
        .{ .input = ": add-one 1 + ; :: cb callback: i:i add-one ; cb 41 ccall1", .expected = Fy.makeInt(42) },
        // 2-arg callback
        .{ .input = ": my-sub - ; :: sub-cb callback: ii:i my-sub ; sub-cb 10 3 ccall2", .expected = Fy.makeInt(7) },
    });
}

test "Type introspection - quote?, word?, word->str" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();
    Fy.Builtins.fyPtr = @intFromPtr(&fy);

    try runCases(&fy, &[_]TestCase{
        .{ .input = "[1 2] quote?", .expected = Fy.makeInt(1) },
        .{ .input = "42 quote?", .expected = Fy.makeInt(0) },
        .{ .input = "\"hi\" quote?", .expected = Fy.makeInt(0) },
        .{ .input = "[hello] qhead word?", .expected = Fy.makeInt(1) },
        .{ .input = "42 word?", .expected = Fy.makeInt(0) },
        .{ .input = "\"test\" word?", .expected = Fy.makeInt(0) },
        .{ .input = "[1 2] word?", .expected = Fy.makeInt(0) },
        // word->str returns string, test via slen
        .{ .input = "[hello] qhead word->str slen", .expected = Fy.makeInt(5) },
        .{ .input = "42 word->str", .expected = Fy.makeInt(0) },
    });
}

test "Type introspection - qnth, qnth-type" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();
    Fy.Builtins.fyPtr = @intFromPtr(&fy);

    try runCases(&fy, &[_]TestCase{
        // qnth — indexed access
        .{ .input = "[10 20 30] 0 qnth", .expected = Fy.makeInt(10) },
        .{ .input = "[10 20 30] 2 qnth", .expected = Fy.makeInt(30) },
        // qnth-type — type tags: 0=int, 1=float, 2=word, 3=string, 4=quote
        .{ .input = "[42] 0 qnth-type", .expected = Fy.makeInt(0) },
        .{ .input = "[3.14] 0 qnth-type", .expected = Fy.makeInt(1) },
        .{ .input = "[hello] 0 qnth-type", .expected = Fy.makeInt(2) },
        .{ .input = "[\"test\"] 0 qnth-type", .expected = Fy.makeInt(3) },
        .{ .input = "[[1 2]] 0 qnth-type", .expected = Fy.makeInt(4) },
        // mixed quote
        .{ .input = "[10 \"hi\" 2.5 foo [1]] 0 qnth-type", .expected = Fy.makeInt(0) },
        .{ .input = "[10 \"hi\" 2.5 foo [1]] 1 qnth-type", .expected = Fy.makeInt(3) },
        .{ .input = "[10 \"hi\" 2.5 foo [1]] 2 qnth-type", .expected = Fy.makeInt(1) },
        .{ .input = "[10 \"hi\" 2.5 foo [1]] 3 qnth-type", .expected = Fy.makeInt(2) },
        .{ .input = "[10 \"hi\" 2.5 foo [1]] 4 qnth-type", .expected = Fy.makeInt(4) },
    });
}

test "Macros - emit-lit" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();
    Fy.Builtins.fyPtr = @intFromPtr(&fy);

    try runCases(&fy, &[_]TestCase{
        .{ .input = "macro: push42 42 emit-lit ; push42", .expected = Fy.makeInt(42) },
        .{ .input = "macro: push10 5 5 + emit-lit ; push10", .expected = Fy.makeInt(10) },
    });
}

test "Macros - emit-word" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();
    Fy.Builtins.fyPtr = @intFromPtr(&fy);

    try runCases(&fy, &[_]TestCase{
        .{ .input = "macro: emit-add \"+\" emit-word ; 3 4 emit-add", .expected = Fy.makeInt(7) },
        .{ .input = "macro: emit-dup \"dup\" emit-word ; 5 emit-dup +", .expected = Fy.makeInt(10) },
    });
}

test "Macros - peek-quote and unpush" {
    var fy = Fy.init(std.testing.allocator);
    defer fy.deinit();
    Fy.Builtins.fyPtr = @intFromPtr(&fy);

    try runCases(&fy, &[_]TestCase{
        // const macro: compile-time evaluation of a quote
        .{ .input = "macro: const peek-quote unpush do emit-lit ; [6 7 *] const", .expected = Fy.makeInt(42) },
        .{ .input = "[3 4 +] const", .expected = Fy.makeInt(7) },
        .{ .input = "[10 2 * 1 +] const", .expected = Fy.makeInt(21) },
    });
}
