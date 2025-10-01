const std = @import("std");
const net = std.net;

pub fn main() !void {
    std.debug.print("----- Zig TCP/IP server -----\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();
    const connection = try server.accept();

    var buf: [1024]u8 = undefined;
    var writer = connection.stream.writer(&buf);
    const stream = &writer.interface;

    _ = try stream.write("HTTP/1.1 200 OK\r\n\r\n");
    _ = try stream.flush();

    std.debug.print("Client connected", .{});
}
