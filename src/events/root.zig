const std = @import("std");
const ris = @import("../collect/ris_live.zig");

pub fn run(allocator: std.mem.Allocator, limit: usize) !void {
    const r = try ris.RisLiveClient.init(allocator);
    defer r.deinit();

    try r.handshake();
    try r.subscribeGlobal();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Connected to Global Event Stream (Press Ctrl+C to stop)...\n", .{});
    
    var count: usize = 0;
    while (true) {
        const msg_payload = r.readMessage() catch |err| {
            if (err == error.ConnectionClosed) break;
            continue;
        };
        defer allocator.free(msg_payload);
        
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, msg_payload, .{}) catch continue;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) continue;
        
        const type_val = root.object.get("type") orelse continue;
        if (!std.mem.eql(u8, type_val.string, "ris_message")) continue;

        const data = root.object.get("data") orelse continue;
        if (data != .object) continue;

        const peer_str = if (data.object.get("peer")) |p| p.string else "unknown";
        
        // Print Announcements
        if (data.object.get("announcements")) |list| {
            if (list == .array) {
                for (list.array.items) |prefix| {
                     if (prefix == .object) {
                         if (prefix.object.get("prefixes")) |p_array| { // format varies
                             // Actually announcements is usually array of prefixes or objects?
                             // RIS Live format: "announcements": [{"prefixes": ["1.2.3.0/24"], "next_hop": "..."}]
                             // Or simplified?
                             // Let's assume structure: "announcements": [ { "prefixes": ["..."] } ]
                             // or sometimes just list of prefixes?
                             // Documentation says for 'ris_message': 
                             // announcements: [ { prefixes: [String], next_hop: String, ... } ]
                            if (p_array == .array) {
                                for (p_array.array.items) |p_str| {
                                     try stdout.print("[A] {s} via {s}\n", .{p_str.string, peer_str});
                                     count += 1;
                                }
                            }
                         }
                     }
                }
            }
        }
        
        // Print Withdrawals
        if (data.object.get("withdrawals")) |list| {
            if (list == .array) {
                // Withdrawals is usually just a list of prefixes? "withdrawals": ["1.2.3.0/24"]
                for (list.array.items) |w| {
                    if (w == .string) {
                         try stdout.print("[W] {s} via {s}\n", .{w.string, peer_str});
                         count += 1;
                    }
                }
            }
        }

        if (count >= limit and limit != 0) break;
    }
}
