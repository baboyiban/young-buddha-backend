const std = @import("std");

pub fn handleConnection(_: std.mem.Allocator, conn: std.net.Server.Connection) !void {
    defer conn.stream.close();

    var read_buf: [4096]u8 = undefined;
    var write_buf: [4096]u8 = undefined;

    var net_reader = std.net.Stream.reader(conn.stream, &read_buf);
    var net_writer = std.net.Stream.writer(conn.stream, &write_buf);

    const in_iface: *std.Io.Reader = std.net.Stream.Reader.interface(&net_reader);
    const out_iface: *std.Io.Writer = &net_writer.interface;

    var server = std.http.Server.init(in_iface, out_iface);

    while (true) {
        var req = server.receiveHead() catch |err| {
            std.log.err("Failed to receive request head: {s}", .{@errorName(err)});
            break;
        };

        try req.respond("Hello, World!", .{});
    }
}
