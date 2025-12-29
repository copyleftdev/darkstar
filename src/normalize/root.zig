const std = @import("std");

pub const Aggregator = struct {
    allocator: std.mem.Allocator,
    // (Prefix, PeerASN) -> SignalState
    signals: std.StringHashMap(SignalState),
    
    // Config
    flap_window_ms: i64 = 60_000, 
    min_peer_threshold: u32 = 3,

    pub const SignalState = struct {
        first_seen: i64,
        last_updated: i64,
        withdrawal_count: u32,
        announcement_count: u32,
        is_withdrawal: bool,
    };

    pub fn init(allocator: std.mem.Allocator) Aggregator {
        return Aggregator{
            .allocator = allocator,
            .signals = std.StringHashMap(SignalState).init(allocator),
        };
    }

    pub fn deinit(self: *Aggregator) void {
        var iter = self.signals.keyIterator();
        while (iter.next()) |key_ptr| {
            self.allocator.free(key_ptr.*);
        }
        self.signals.deinit();
    }

    pub fn processUpdate(self: *Aggregator, prefix: []const u8, peer_asn: []const u8, is_withdrawal: bool, timestamp: i64) !void {
        // Create lookup key first to check existence
        // Strategy: Use a temp allocated key for lookup? Or just alloc and free if exists?
        // Optimization: "prefix|peer_asn"
        const key = try std.fmt.allocPrint(self.allocator, "{s}|{s}", .{prefix, peer_asn});
        
        const gop = try self.signals.getOrPut(key);
        if (!gop.found_existing) {
            // New entry, key usage is valid. Keep `key` allocated.
            gop.value_ptr.* = SignalState{
                .first_seen = timestamp,
                .last_updated = timestamp,
                .withdrawal_count = if (is_withdrawal) 1 else 0,
                .announcement_count = if (is_withdrawal) 0 else 1,
                .is_withdrawal = is_withdrawal,
            };
        } else {
            // Entry exists. We don't need the new `key` alloc.
            self.allocator.free(key);
            
            var state = gop.value_ptr;
            
            // Check window
            if (timestamp - state.last_updated > self.flap_window_ms) {
                state.first_seen = timestamp;
                state.withdrawal_count = 0;
                state.announcement_count = 0;
            }
            
            state.last_updated = timestamp;
            if (is_withdrawal) {
                 state.withdrawal_count += 1;
                 state.is_withdrawal = true;
            } else {
                 state.announcement_count += 1;
                 state.is_withdrawal = false;
            }
        }
    }


    pub fn computeHealth(self: *Aggregator, prefix: []const u8) f32 {
        // Iterate signals matching prefix
        var withdrawal_peers: u32 = 0;
        var total_peers: u32 = 0;
        
        var iter = self.signals.iterator();
        while (iter.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, prefix)) {
                 total_peers += 1;
                 // Naive check: if latest state is withdrawal
                 if (entry.value_ptr.is_withdrawal) {
                     withdrawal_peers += 1;
                 }
            }
        }
        
        if (total_peers == 0) return 1.0; // Healthy (Unknown)
        
        // Simple ratio
        const health = 1.0 - (@as(f32, @floatFromInt(withdrawal_peers)) / @as(f32, @floatFromInt(total_peers)));
        return health;
    }
};

test "aggregator_logic" {
    const allocator = std.testing.allocator;
    var agg = Aggregator.init(allocator);
    defer agg.deinit();

    // Sim: 3 peers withdraw prefix 1.2.3.0/24
    try agg.processUpdate("1.2.3.0/24", "3333", true, 1000);
    try agg.processUpdate("1.2.3.0/24", "1234", true, 1005);
    try agg.processUpdate("1.2.3.0/24", "5678", true, 1010);
    
    // 1 peer announces (flap?)
    try agg.processUpdate("1.2.3.0/24", "9999", false, 1020);

    const health = agg.computeHealth("1.2.3.0/24");
    // 3 withdrawals, 1 announcement = 3/4 bad = 0.25 health?
    // Wait, logic says: withdrawal_peers / total. 
    // Is 9999 counted? Yes.
    // 3 withdrawals. Total 4. 
    // Health = 1.0 - (3/4) = 0.25.
    
    std.debug.print("Computed Health: {d}\n", .{health});
}
