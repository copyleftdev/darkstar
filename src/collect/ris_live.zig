const std = @import("std");
const net = std.net;
const bearssl = @import("bearssl");

const isrg_root_x1 = 
    \\-----BEGIN CERTIFICATE-----
    \\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
    \\-----END CERTIFICATE-----
    \\
;

const SslStream = bearssl.Stream(*net.Stream, *net.Stream);

pub const RisLiveClient = struct {
    allocator: std.mem.Allocator,
    
    // Stable storage for connection components
    tcp_stream: net.Stream,
    
    anchors: bearssl.TrustAnchorCollection,
    x509: bearssl.x509.Minimal,
    ssl_client: bearssl.Client,
    stream: SslStream,

    pub fn init(allocator: std.mem.Allocator) !*RisLiveClient {
        // Allocate self on heap to ensure pointer stability for SSL context
        const self = try allocator.create(RisLiveClient);
        errdefer allocator.destroy(self);
        
        self.allocator = allocator;

        // 1. Connect TCP (Port 443 for Secure WebSocket)
        self.tcp_stream = try net.tcpConnectToHost(allocator, "ris-live.ripe.net", 443);
        errdefer self.tcp_stream.close();

        // 2. Setup Trust Anchors
        self.anchors = bearssl.TrustAnchorCollection.init(allocator);
        try self.anchors.appendFromPEM(isrg_root_x1);

        
        // 3. Init X.509 Engine
        self.x509 = bearssl.x509.Minimal.init(self.anchors);
        
        // 4. Init SSL Client Engine
        self.ssl_client = bearssl.Client.init(self.x509.getEngine());
        self.ssl_client.relocate();
        
        // 5. Start Handshake
        try self.ssl_client.reset("ris-live.ripe.net", false);
        
        // 6. Create Stream Wrapper
        self.stream = bearssl.initStream(self.ssl_client.getEngine(), &self.tcp_stream, &self.tcp_stream);
        
        return self;
    }

    pub fn handshake(self: *RisLiveClient) !void {
        // Standard HTTP Upgrade request over the SSL stream
        const req = 
            "GET /v1/ws/ HTTP/1.1\r\n" ++
            "Host: ris-live.ripe.net\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
            "Sec-WebSocket-Version: 13\r\n" ++
            "\r\n";
        
        // Use the SSL stream writer
        try self.stream.writer().writeAll(req);
        
        // Flush SSL buffer
        try self.stream.flush();

        var buf: [4096]u8 = undefined;
        // Read handshake response
        _ = try self.stream.reader().read(&buf);
    }

    pub fn subscribe(self: *RisLiveClient, asn: []const u8) !void {
        const msg_fmt = "{{\"type\": \"ris_subscribe\", \"data\": {{\"path\": \"{s}\"}}}}";
        const msg = try std.fmt.allocPrint(self.allocator, msg_fmt, .{asn});
        defer self.allocator.free(msg);

        try self.writeFrame(msg);
        try self.stream.flush();
    }

    fn writeFrame(self: *RisLiveClient, payload: []const u8) !void {
        const len = payload.len;
        if (len > 125) return error.PayloadTooLargeForSimpleFramer;

        var header: [6]u8 = undefined;
        header[0] = 0x81; // FIN + Text
        header[1] = 0x80 | @as(u8, @intCast(len)); // Masked + len
        
        const mask_key = [4]u8{0x01, 0x02, 0x03, 0x04};
        @memcpy(header[2..6], &mask_key);

        var writer = self.stream.writer();
        try writer.writeAll(header[0..6]);

        const masked_payload = try self.allocator.dupe(u8, payload);
        defer self.allocator.free(masked_payload);
        
        for (masked_payload, 0..) |*b, i| {
            b.* ^= mask_key[i % 4];
        }
        try writer.writeAll(masked_payload);
    }

    pub fn readMessage(self: *RisLiveClient) ![]u8 {
        var reader = self.stream.reader();
        
        var head: [2]u8 = undefined;
        const n = try reader.read(&head);
        if (n < 2) return error.IncompleteFrame;

        const len_byte = head[1] & 0x7F;
        var payload_len: usize = len_byte;
        
        if (len_byte == 126) {
             var ext: [2]u8 = undefined;
             _ = try reader.read(&ext);
             payload_len = (@as(usize, ext[0]) << 8) | ext[1]; 
        }

        const buf = try self.allocator.alloc(u8, payload_len);
        
        var total_read: usize = 0;
        while (total_read < payload_len) {
            const bytes = try reader.read(buf[total_read..]);
            if (bytes == 0) return error.ConnectionClosed;
            total_read += bytes;
        }

        return buf;
    }

    pub fn deinit(self: *RisLiveClient) void {
        // Close SSL stream (sends notify)
        self.stream.close() catch {};
        // Close underlying TCP
        self.tcp_stream.close();
        
        // Deinit BearSSL components
        self.anchors.deinit();
        // Minimial and Client don't seem to have deinit in binding.zig used here?
        // Checking binding.zig again... Client has no deinit, Minimal no deinit.
        // They use arena allocators internally? 
        // Wait, TrustAnchorCollection has deinit.
        // PublicKey has deinit.
        
        self.allocator.destroy(self);
    }
};
