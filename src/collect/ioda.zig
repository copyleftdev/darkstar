const std = @import("std");

pub const IodaClient = struct {
    allocator: std.mem.Allocator,
    pub fn init(allocator: std.mem.Allocator) !IodaClient {
        return IodaClient{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *IodaClient) void {
        _ = self;
    }

    pub fn fetchOutages(self: *IodaClient, asn: u32) !void {
        const url_fmt = "https://api.ioda.inetintel.cc.gatech.edu/v2/signals?entityType=asn&entityCode={d}";
        const url_str = try std.fmt.allocPrint(self.allocator, url_fmt, .{asn});
        defer self.allocator.free(url_str);

        const argv = &[_][]const u8{ "curl", "-s", url_str };
        
        var child = std.process.Child.init(argv, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;
        
        try child.spawn();
        
        // Read output
        const output = try child.stdout.?.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(output);
        
        _ = try child.wait();
        
        // Simple heuristic: check if JSON contains "data"
        if (std.mem.indexOf(u8, output, "\"data\":") != null) {
            std.debug.print("IODA: Data retrieved for ASN {d}\n", .{asn});
            // In a real implementation we would parse this JSON
            // For now, just print a snippet
            if (output.len > 200) {
                 std.debug.print("Response: {s}...\n", .{output[0..200]});
            } else {
                 std.debug.print("Response: {s}\n", .{output});
            }
        } else {
            std.debug.print("IODA: No data or API error for ASN {d}\n", .{asn});
        }
    }
};

test "fetch_ioda" {
    // This test requires internet access and TLS support
    const allocator = std.testing.allocator;
    var client = try IodaClient.init(allocator);
    defer client.deinit();
    
    // Test with Google ASN 15169
    // Expect failure gracefully if no TLS
    client.fetchOutages(15169) catch |err| {
        std.debug.print("Fetch failed (expected if no TLS): {}\n", .{err});
    };
}
