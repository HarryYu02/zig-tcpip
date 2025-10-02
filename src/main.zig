const std = @import("std");
const testing = std.testing;
const net = std.net;

const Request = struct {
    method: []u8,
    url: []u8,
    host: []u8,
    user_agent: []u8,
    accept: []u8,
};

fn findIndex(str: []const u8, target: []const u8) !usize {
    if (target.len > 1) return error.TooLong;
    for (str, 0..) |char, index| {
        if (char == target[0]) return index;
    }
    return error.NotFound;
}

pub fn main() !void {
    std.debug.print("\n----- Zig TCP/IP server -----\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();
    const connection = try server.accept();

    // Request
    var request_buf: [1024]u8 = undefined;
    var reader = connection.stream.reader(&request_buf);
    const r = reader.interface();

    // Reponse
    var response_buf: [1024]u8 = undefined;
    var response_writer = connection.stream.writer(&response_buf);
    const w = &response_writer.interface;

    // Parse request
    var i: u4 = 0;
    // var req = Request{};
    while (r.takeDelimiterExclusive('\r')) |l| : (i += 1) {
        if (l.len <= 1) break;
        const line = if (l[0] == '\n') l[1..l.len] else l;
        std.debug.print("line {d} is: {s} (len={d})\n", .{ i, line, line.len });

        switch (i) {
            0 => {
                // GET /abc HTTP1.1
                const first_space = try findIndex(line, " ");
                const method = line[0..first_space];
                std.debug.print("method: {s}\n", .{method});
                const second_space = first_space + 1 + try findIndex(line[first_space + 1 .. line.len], " ");
                const url = line[first_space + 1 .. second_space];
                std.debug.print("url: {s}\n", .{url});

                const root = "/";
                if (std.mem.eql(u8, root, url)) {
                    _ = try w.write("HTTP/1.1 200 OK\r\n\r\n");
                    _ = try w.flush();
                    return;
                } else {
                    _ = try w.write("HTTP/1.1 404 Not Found\r\n\r\n");
                    _ = try w.flush();
                    return;
                }
            },
            else => {},
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.StreamTooLong => {},
        error.ReadFailed => {},
    }

    _ = try w.write("HTTP/1.1 200 OK\r\n\r\n");
    _ = try w.flush();

    std.debug.print("\n----- Client connected -----\n", .{});
}

test findIndex {
    try testing.expect(0 == try findIndex("abc", "a"));
    try testing.expect(1 == try findIndex("abc", "b"));
    try testing.expect(2 == try findIndex("abc", "c"));
    try testing.expectError(error.TooLong, findIndex("abc", "ab"));
    try testing.expectError(error.NotFound, findIndex("abc", "d"));
}
