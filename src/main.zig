const std = @import("std");
const testing = std.testing;
const net = std.net;
const mem = std.mem;
const fs = std.fs;

const Args = struct {
    directory: ?[]const u8 = null,
};

const Response = struct {
    http: []u8 = "",
    code: []u8 = "",
    message: []u8 = "",
    body: []u8 = "",
};

fn handleConnection(connection: net.Server.Connection, args: Args) !void {
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
        const line = if (l[0] == '\n') l[1..] else l;
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

    // Read request body by content-length
    const content_len_opt = req.get("Content-Length");
    if (content_len_opt != null) {
        if (mem.eql(u8, try r.peek(1), "\n")) {
            _ = try r.take(1);
        }
        const content_len = try std.fmt.parseInt(u32, content_len_opt.?, 10);
        _ = try req.put("Body", try r.take(content_len));
    }

    // Generate response
    const url = req.get("Url") orelse "";
    if (url.len == 0) {
        // No url
        _ = try w.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n");
    } else if (mem.eql(u8, "/", url)) {
        // Root -> 200 OK
        _ = try w.write("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n");
    } else {
        // Other routes
        var url_iter = mem.splitAny(u8, url[1..], "/");
        const route = url_iter.first();
        if (mem.eql(u8, "echo", route)) {
            const echo_text = url_iter.next();
            if (echo_text != null) {
                var len_buf: [256]u8 = undefined;
                const len = try std.fmt.bufPrint(&len_buf, "{d}", .{echo_text.?.len});
                _ = try w.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: ");
                _ = try w.write(len);
                _ = try w.write("\r\n\r\n");
                _ = try w.write(echo_text.?);
            } else {
                _ = try w.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 0\r\n\r\n");
            }
        } else if (mem.eql(u8, "user-agent", route)) {
            const user_agent = req.get("User-Agent");
            if (user_agent != null) {
                var len_buf: [256]u8 = undefined;
                const len = try std.fmt.bufPrint(&len_buf, "{d}", .{user_agent.?.len});
                _ = try w.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: ");
                _ = try w.write(len);
                _ = try w.write("\r\n\r\n");
                _ = try w.write(user_agent.?);
            } else {
                _ = try w.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 0\r\n\r\n");
            }
        } else if (mem.eql(u8, "files", route)) {
            const file_name = url_iter.next();
            if (file_name != null) {
                var dir = try fs.openDirAbsolute(args.directory.?, .{});
                defer dir.close();

                if (mem.eql(u8, req.get("Method").?, "GET")) {
                    var file = dir.openFile(file_name.?, .{}) catch |err| {
                        std.debug.print("File not found\n", .{});
                        _ = try w.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n");
                        _ = try w.flush();
                        return err;
                    };
                    defer file.close();

                    var file_buf: [1024]u8 = undefined;
                    var file_reader = file.reader(&file_buf);
                    const fr = &file_reader.interface;
                    const file_content = try fr.takeDelimiterExclusive('\r');

                    var len_buf: [256]u8 = undefined;
                    const len = try std.fmt.bufPrint(&len_buf, "{d}", .{file_content.len});
                    _ = try w.write("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: ");
                    _ = try w.write(len);
                    _ = try w.write("\r\n\r\n");
                    _ = try w.write(file_content);
                } else if (mem.eql(u8, req.get("Method").?, "POST")) {
                    var file = try dir.createFile(file_name.?, .{});
                    defer file.close();

                    const content = req.get("Body");
                    if (content != null) {
                        _ = try file.write(content.?);
                        _ = try w.write("HTTP/1.1 201 Created\r\nContent-Length: 0\r\n\r\n");
                    } else {
                        _ = try w.write("HTTP/1.1 201 Created\r\nContent-Length: 0\r\n\r\n");
                    }

                } else {
                    _ = try w.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n");
                }
            } else {
                _ = try w.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n");
            }
        } else {
            _ = try w.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n");
        }
    }

    _ = try w.flush();
}

pub fn main() !void {
    var args: Args = .{};
    var args_iter = std.process.args();
    _ = args_iter.next();
    while (args_iter.next()) |arg| {
        if (mem.startsWith(u8, arg, "--")) {
            const arg_name = arg[2..];
            const arg_value = args_iter.next();
            if (mem.eql(u8, arg_name, "directory")) {
                if (arg_value != null) {
                    args.directory = arg_value;
                } else {
                    return error.ArgsValueNotFound;
                }
            } else {
                return error.UnknownArgName;
            }
        }
    }
    if (args.directory == null) {
        args.directory = "/tmp";
    }

    std.debug.print("\n----- Zig TCP/IP server -----\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    while (true) {
        const connection = try server.accept();
        var thread = try std.Thread.spawn(.{}, handleConnection, .{connection, args});
        thread.join();
    }

    std.debug.print("----- Client connected -----\n", .{});
}
