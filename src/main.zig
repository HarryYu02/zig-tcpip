const std = @import("std");
const net = std.net;

pub fn main() !void {
    std.debug.print("----- Zig TCP/IP server -----", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{ .reuse_address = true });
    defer listener.deinit();

    _ = try listener.accept();
    std.debug.print("Client connected", .{});
}
