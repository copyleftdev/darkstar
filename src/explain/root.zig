const std = @import("std");
const probe = @import("../probe/root.zig");
const ris = @import("../collect/ris_live.zig");
const ioda = @import("../collect/ioda.zig");

pub fn run(allocator: std.mem.Allocator, target: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n🧑‍⚕️  Doctor Mode: Analyzing {s}...\n", .{target});
    try stdout.print("========================================\n", .{});

    // 1. Active Reachability (Ping)
    try stdout.print("\n[1] Active Reachability (ICMP/Ping)\n", .{});
    try probe.run(allocator, target, .Ping);

    // 2. BGP Stability (5s Sample)
    try stdout.print("\n[2] BGP Stability (Sampling 5s...)\n", .{});
    
    // Determine if ASN or Prefix for subscription
    // Simple heuristic: if contains '.', it's prefix. Else ASN (prepend AS if needed? RisLive handles digit only as ASN?)
    // RIS Live "path" expects AS number (integers or 'AS' prefix?)
    // Actually RIS Live 'path' argument matches ASN.
    var r = try ris.RisLiveClient.init(allocator);
    defer r.deinit();

    try r.handshake();
    try r.subscribe(target); // Optimistic subscription

    var msg_count: usize = 0;
    const end = std.time.milliTimestamp() + 5000;
    
    while (std.time.milliTimestamp() < end) {
         const payload = r.readMessage() catch |err| {
             if (err == error.ConnectionClosed) break;
             continue; // Timeout or keepalive
         };
         defer allocator.free(payload);
         
         const parsed = std.json.parseFromSlice(std.json.Value, allocator, payload, .{}) catch continue;
         defer parsed.deinit();
         
         const root = parsed.value;
         if (root != .object) continue;
         
         const type_val = root.object.get("type") orelse continue;
         if (!std.mem.eql(u8, type_val.string, "ris_message")) continue;
         
         // If we got a real message
         msg_count += 1;
         try stdout.print("   -> BGP Update received (See health command for details)\n", .{});
    }

    if (msg_count == 0) {
        try stdout.print("   ✅ BGP Routing appears stable (No updates in 5s)\n", .{});
    } else {
        try stdout.print("   ⚠️  BGP Routing is FLAPPING ({d} updates in 5s)\n", .{msg_count,});
    }

    // 3. IODA Context
    try stdout.print("\n[3] Global Outage Context (IODA)\n", .{});
    const asn = std.fmt.parseInt(u32, target, 10) catch {
         // If fails to parse as int, check if it starts with AS
         if (std.mem.startsWith(u8, target, "AS")) {
             const sub = target[2..];
             if (std.fmt.parseInt(u32, sub, 10)) |val| {
                 var client = try ioda.IodaClient.init(allocator);
                 defer client.deinit();
                 try client.fetchOutages(val);
                 return;
             } else |_| {}
         }
         try stdout.print("   (Skipping IODA: Target is not a simple ASN)\n", .{});
         return;
    };
    
    // If we parsed an ASN successfully
    var client = try ioda.IodaClient.init(allocator);
    defer client.deinit();
    try client.fetchOutages(asn);
}
