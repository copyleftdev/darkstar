const std = @import("std");

pub const ProbeType = enum { Ping, Trace };

pub fn run(allocator: std.mem.Allocator, target: []const u8, probe_type: ProbeType) !void {
    const argv = switch (probe_type) {
        .Ping => &[_][]const u8{ "ping", "-c", "4", target },
        .Trace => &[_][]const u8{ "traceroute", target },
    };

    var child = std.process.Child.init(argv, allocator);
    
    // Inherit stdout/stderr to stream directly to user terminal
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = child.spawnAndWait() catch |err| {
        std.debug.print("Error spawning {s}: {}\n", .{argv[0], err});
        return err;
    };

    switch (term) {
        .Exited => |code| {
             if (code != 0) {
                 std.debug.print("{s} exited with code {d}\n", .{argv[0], code});
             }
        },
        else => {
            std.debug.print("{s} terminated abnormally\n", .{argv[0]});
        },
    }
}
