const std = @import("std");
const testing = std.testing;
const net = std.net;

const Response = struct {
    http: []u8 = "",
    code: []u8 = "",
    message: []u8 = "",
    body: []u8 = "",
};

/// Find the index of the first occurrence of target in str,
/// target cannot be longer than 1 char.
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

    // Request reader
    var request_buf: [1024]u8 = undefined;
    var reader = connection.stream.reader(&request_buf);
    const r = reader.interface();

    // Reponse writer
    var response_buf: [1024]u8 = undefined;
    var writer = connection.stream.writer(&response_buf);
    const w = &writer.interface;

    // Parse request
    const allocator = std.heap.page_allocator;
    var req = std.StringHashMap([]const u8).init(allocator);
    defer req.deinit();

    var i: u4 = 0;
    while (r.takeDelimiterExclusive('\r')) |l| : (i += 1) {
        const line = if (l[0] == '\n') l[1..l.len] else l;
        if (line.len == 0) {
            std.debug.print("End of request\n", .{});
            break;
        }
        std.debug.print("line {d} is: {s} (len={d})\n", .{ i, line, line.len });
        if (i == 0) {
            const first_space = try findIndex(line, " ");
            try req.put("Method", line[0..first_space]);
            const second_space = first_space + 1 + try findIndex(line[first_space + 1 .. line.len], " ");
            try req.put("Url", line[first_space + 1 .. second_space]);
            try req.put("Http",line[first_space + 1 + second_space + 1 .. line.len]);
        } else {
            const colon = try findIndex(line, ":");
            try req.put(line[0..colon], line[colon + 2 .. line.len]);
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.StreamTooLong => return err,
        error.ReadFailed => return err,
    }

    // Generate response
    const root = "/";
    if (std.mem.eql(u8, root, req.get("Url").?)) {
        _ = try w.write("HTTP/1.1 200 OK\r\n\r\n");
    } else {
        _ = try w.write("HTTP/1.1 404 Not Found\r\n\r\n");
    }

    _ = try w.flush();
    std.debug.print("----- Client connected -----\n", .{});
}

test findIndex {
    try testing.expect(0 == try findIndex("abc", "a"));
    try testing.expect(1 == try findIndex("abc", "b"));
    try testing.expect(2 == try findIndex("abc", "c"));
    try testing.expectError(error.TooLong, findIndex("abc", "ab"));
    try testing.expectError(error.NotFound, findIndex("abc", "d"));
}
