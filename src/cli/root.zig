const std = @import("std");

pub const Command = union(enum) {
    Health: struct {
        target: []const u8,
    },
    Events: struct {
        limit: usize,
    },
    Probe: struct {
        target: []const u8,
        type: enum { Ping, Trace },
    },
    Explain: struct {
        target: []const u8,
    },
    Help,
    Version,
};

pub fn parseArgs(allocator: std.mem.Allocator) !Command {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // Skip executable name

    const cmd_str = args.next() orelse return .Help;

    if (std.mem.eql(u8, cmd_str, "health")) {
        const target = args.next() orelse return error.MissingTarget;
        return Command{ .Health = .{ .target = try allocator.dupe(u8, target) } };
    } else if (std.mem.eql(u8, cmd_str, "events")) {
        return Command{ .Events = .{ .limit = 10 } }; // Default limit
    } else if (std.mem.eql(u8, cmd_str, "probe")) {
        const type_str = args.next() orelse return error.MissingProbeType;
        const target = args.next() orelse return error.MissingTarget;
        
        const probe_type = if (std.mem.eql(u8, type_str, "ping"))
            @as(u8, 0)
        else if (std.mem.eql(u8, type_str, "trace"))
            @as(u8, 1)
        else
            return error.InvalidProbeType;

        return Command{ .Probe = .{ 
            .target = try allocator.dupe(u8, target),
            .type = if (probe_type == 0) .Ping else .Trace
        }};
    } else if (std.mem.eql(u8, cmd_str, "explain")) {
         const target = args.next() orelse return error.MissingTarget;
         return Command{ .Explain = .{ .target = try allocator.dupe(u8, target) } };
    } else if (std.mem.eql(u8, cmd_str, "--version")) {
        return .Version;
    } else {
        return .Help;
    }
}
