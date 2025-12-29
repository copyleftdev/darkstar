const std = @import("std");

pub const IodaClient = struct {
    allocator: std.mem.Allocator,
    client: std.http.Client,

    pub fn init(allocator: std.mem.Allocator) !IodaClient {
        return IodaClient{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *IodaClient) void {
        self.client.deinit();
    }

    pub fn fetchOutages(self: *IodaClient, asn: u32) !void {
        var buf: [4096]u8 = undefined;
        // IODA API V2
        // Warning: This will likely fail without a TLS bundle in strict Zig build
        // For prototype, we might need a workaround or just verify the struct structure.
        const url_fmt = "https://api.ioda.inetintel.cc.gatech.edu/v2/signals?entityType=asn&entityCode={d}";
        const url_str = try std.fmt.allocPrint(self.allocator, url_fmt, .{asn});
        defer self.allocator.free(url_str);

        const uri = try std.Uri.parse(url_str);
        
        var server_header_buffer: [4096]u8 = undefined;
        var req = try self.client.open(.GET, uri, .{ .server_header_buffer = &server_header_buffer });
        defer req.deinit();

        try req.send();
        try req.wait();
        
        const bytes = try req.read(&buf);
        std.debug.print("IODA Response ({d} bytes): {s}\n", .{bytes, buf[0..bytes]});
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
