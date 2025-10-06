const std = @import("std");
const testing = std.testing;
const net = std.net;
const mem = std.mem;

const Response = struct {
    http: []u8 = "",
    code: []u8 = "",
    message: []u8 = "",
    body: []u8 = "",
};

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
            const space_one = mem.indexOf(u8, line, " ").?;
            try req.put("Method", line[0..space_one]);
            const space_two = space_one + 1 + mem.indexOf(u8, line[space_one + 1 ..], " ").?;
            try req.put("Url", line[space_one + 1 .. space_two]);
            try req.put("Http", line[space_one + 1 + space_two + 1 ..]);
        } else {
            const colon = mem.indexOf(u8, line, ":").?;
            try req.put(line[0..colon], line[colon + 2 .. line.len]);
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.StreamTooLong => return err,
        error.ReadFailed => return err,
    }

    // Generate response
    const url = req.get("Url").?;
    if (mem.eql(u8, "/", url)) {
        // Root -> 200 OK
        _ = try w.write("HTTP/1.1 200 OK\r\n\r\n");
    } else if (url.len > 1) {
        var url_iter = mem.splitAny(u8, url[1..], "/");
        if (mem.eql(u8, "echo", url_iter.first())) {
            const echo_text = url_iter.next();
            if (echo_text != null) {
                var len_buf: [8]u8 = undefined;
                const len = try std.fmt.bufPrint(&len_buf, "{d}", .{echo_text.?.len});
                _ = try w.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: ");
                _ = try w.write(len);
                _ = try w.write("\r\n\r\n");
                _ = try w.write(echo_text.?);
            } else {
                _ = try w.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 0\r\n\r\n");
            }
        } else {
            _ = try w.write("HTTP/1.1 404 Not Found\r\n\r\n");
        }
    } else {
        _ = try w.write("HTTP/1.1 404 Not Found\r\n\r\n");
    }

    _ = try w.flush();
    std.debug.print("----- Client connected -----\n", .{});
}
