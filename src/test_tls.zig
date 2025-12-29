const std = @import("std");
const bearssl = @import("bearssl");

test "bearssl_link" {
    // Just verify we can access the module and a basic function/struct
    const ssl = bearssl.Client.init;
    _ = ssl;
    std.debug.print("BearSSL linked successfully!\n", .{});
}
