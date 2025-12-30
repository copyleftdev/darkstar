const std = @import("std");
const cli = @import("cli/root.zig");
const ris = @import("collect/ris_live.zig");
const norm = @import("normalize/root.zig");
const tui = @import("tui/root.zig");
const probe = @import("probe/root.zig");
const events = @import("events/root.zig");
const explain = @import("explain/root.zig");

var global_dash: ?*tui.Dashboard = null;

fn handleSigInt(_: c_int) callconv(.C) void {
    if (global_dash) |d| {
        d.term.disableRawMode();
        d.term.showCursor() catch {};
    }
    std.debug.print("\n[SIGINT] Exiting gracefully...\n", .{});
    std.process.exit(0);
}

pub fn main() !void {
    // Register SIGINT handler
    const act = std.posix.Sigaction{
        .handler = .{ .handler = handleSigInt },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &act, null);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cmd = cli.parseArgs(allocator) catch |err| {
        std.debug.print("Error parsing args: {}\n", .{err});
        std.debug.print("Usage: darkstar <command> [args]\n", .{});
        return;
    };

    switch (cmd) {

        .Health => |info| {
            defer allocator.free(info.target);
            
            // 1. Init Components
            const r = try ris.RisLiveClient.init(allocator);
            defer r.deinit();
            
            var agg = norm.Aggregator.init(allocator);
            defer agg.deinit();

            var dash = tui.Dashboard.init(allocator); // New allocator requirement
            defer dash.deinit();
            global_dash = &dash;

            // 2. Connect & Subscribe
            try r.handshake();
            try r.subscribe(info.target);
            
            try dash.start();
            defer dash.finish() catch {};

             // 3. Collection Loop
             const start = std.time.milliTimestamp();
             var count: usize = 0;
             var num_withdrawals: usize = 0;
             var num_announcements: usize = 0;
             
             // Interactive Loop (Infinite until 'q')
             while (true) {
                  const current_time = std.time.milliTimestamp();
                  const elapsed = current_time - start;
 
                  // Render UI frame
                  try dash.render(info.target, elapsed, num_announcements, num_withdrawals, agg.signals.count());
                  
                  // Handle Input
                  if (dash.term.readKey() catch null) |k| {
                      if (k == 'q') break;
                      // Future: 'c' clear, 'p' pause
                  }
 
                  const msg_payload = r.readMessage() catch |err| {
                      if (err == error.ConnectionClosed) break;
                      continue; 
                  };
                  defer allocator.free(msg_payload);
                 
                 const parsed = std.json.parseFromSlice(std.json.Value, allocator, msg_payload, .{}) catch {
                     continue; 
                 };
                 defer parsed.deinit();
                 
                 const root = parsed.value;
                 if (root != .object) continue;
                 
                 const type_val = root.object.get("type") orelse continue;
                 if (!std.mem.eql(u8, type_val.string, "ris_message")) continue;
                 
                 const data = root.object.get("data") orelse continue;
                 if (data != .object) continue;
                 
                 const peer_str = if (data.object.get("peer")) |p| p.string else "unknown";
                 const timestamp = current_time;
                 
                 if (data.object.get("withdrawals")) |w_list| {
                     if (w_list == .array) {
                         if (w_list.array.items.len > 0) {
                             // Log Details
                             if (dash.canLog()) {
                                 const log_msg = try std.fmt.allocPrint(allocator, "[W] {s} withdrew {d} prefixes", .{peer_str, w_list.array.items.len});
                                 defer allocator.free(log_msg);
                                 try dash.addLog(log_msg);
                             }
                             
                             try agg.processUpdate(info.target, peer_str, true, timestamp);
                             num_withdrawals += 1;
                         }
                     }
                 }
                 
                 if (data.object.get("announcements")) |a_list| {
                     if (a_list == .array) {
                         if (a_list.array.items.len > 0) {
                             // Log Details
                             if (dash.canLog()) {
                                 const log_msg = try std.fmt.allocPrint(allocator, "[A] {s} announced {d} prefixes", .{peer_str, a_list.array.items.len});
                                 defer allocator.free(log_msg);
                                 try dash.addLog(log_msg);
                             }

                             try agg.processUpdate(info.target, peer_str, false, timestamp);
                             num_announcements += 1;
                         }
                     }
                 }
                 count += 1;
            }

            // 4. Compute Health
            // We need to print this AFTER TUI finishes (which defer dash.finish handles?)
            // Actually defer runs at end of scope.
            // We want to stop TUI cleanly, then print result.
            global_dash = null;
            try dash.finish();
            
            const health_score = agg.computeHealth(info.target);
            const t = tui.Terminal.init();
            
            try t.bold();
            try t.writer.print("Flux Analysis Complete.\n", .{});
            try t.colorReset();
            
            try t.writer.print("Health Score: ", .{});
            if (health_score < 0.5) try t.colorRed() else try t.colorGreen();
            try t.writer.print("{d:.2}\n", .{health_score});
            try t.colorReset();
        },
        .Events => |info| {
            try events.run(allocator, info.limit);
        },
        .Probe => |info| {
            const pt = switch (info.type) {
                .Ping => probe.ProbeType.Ping,
                .Trace => probe.ProbeType.Trace,
            };
            try probe.run(allocator, info.target, pt);
            allocator.free(info.target);
        },
        .Explain => |info| {
            try explain.run(allocator, info.target);
            allocator.free(info.target);
        },
        .Version => {
            std.debug.print("darkstar v0.1.0\n", .{});
        },
        .Help => {
            std.debug.print(
                \\Usage: darkstar <command> [options]
                \\
                \\Commands:
                \\  health <asn|prefix>   Check health status
                \\  events                Show recent global events
                \\  probe ping <target>   Active ping measurement
                \\  probe trace <target>  Trace path to target
                \\  explain <asn>         Deep analysis of an incident
                \\
            , .{});
        },
    }
}
