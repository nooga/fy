const std = @import("std");

const Args = struct {
    repl: bool = false,
    eval: ?[]const u8 = null,
    help: bool = false,
    version: bool = false,
    image: bool = false,
    serve: bool = false,
    port: u16 = 0,
    files: u32,
    other_args: std.ArrayList([]const u8) = undefined, // Initialize this later

    // Clean up resources
    pub fn deinit(self: *Args) void {
        self.other_args.deinit();
    }
};

pub fn parseArgs(allocator: std.mem.Allocator, args_it: *std.process.ArgIterator) !Args {
    var result = Args{
        .other_args = std.ArrayList([]const u8).init(allocator),
        .files = 0,
        .help = false,
        .repl = false,
        .version = false,
        .image = false,
        .serve = false,
        .eval = null,
    };

    while (args_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--repl") or std.mem.eql(u8, arg, "-r")) {
            result.repl = true;
        } else if (std.mem.eql(u8, arg, "--eval") or std.mem.eql(u8, arg, "-e")) {
            if (result.eval) |_| {
                std.debug.print("Error: '--eval' flag was already set\n", .{});
                return result;
            }
            if (args_it.next()) |evalExp| {
                result.eval = evalExp;
            } else {
                std.debug.print("Error: '--eval' flag requires an argument\n", .{});
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            result.help = true;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            result.version = true;
        } else if (std.mem.eql(u8, arg, "--image") or std.mem.eql(u8, arg, "-i")) {
            result.image = true;
        } else if (std.mem.eql(u8, arg, "--serve") or std.mem.eql(u8, arg, "-s")) {
            result.serve = true;
        } else if (std.mem.eql(u8, arg, "--port") or std.mem.eql(u8, arg, "-p")) {
            if (args_it.next()) |portStr| {
                result.port = std.fmt.parseInt(u16, portStr, 10) catch 0;
            }
        } else if (arg[0] == '-') {
            std.debug.print("Error: Unknown flag: '{s}'\n", .{arg});
            result.help = true;
            return result;
        } else {
            result.files += 1;
            try result.other_args.append(arg);
        }
    }

    return result;
}
