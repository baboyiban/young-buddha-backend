const std = @import("std");

const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const sqlite3 = c.sqlite3;
pub const sqlite3_stmt = c.qlite3_stmt;

pub const Error = error{
    OpenFailed,
    ExecFailed,
    MallocFailed,
};

pub fn open(path: []const u8) !*sqlite3 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const path_c = try std.fmt.allocPrint(alloc, "{s}\x00", .{path});
    defer alloc.free(path_c);

    var db_ptr: ?*sqlite3 = null;
    const rc = c.sqlite3_open(@ptrCast(path_c.ptr), &db_ptr);
    if (rc != c.SQLITE_OK) {
        if (db_ptr) |db| _ = c.sqlite3_close(db);
        return Error.OpenFailed;
    }
    return db_ptr.?;
}

pub fn close(db: *sqlite3) void {
    _ = c.sqlite3_close(db);
}

pub fn exec(db: *sqlite3, sql: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const sql_c = try std.fmt.allocPrint(alloc, "{s}\x00", .{sql});
    defer alloc.free(sql_c);

    var err_msg: ?[*:0]u8 = null;
    const err_msg_ptr: [*c][*c]u8 = @ptrCast(&err_msg);
    const rc = c.sqlite3_exec(db, @ptrCast(sql_c.ptr), null, null, err_msg_ptr);
    if (rc != c.SQLITE_OK) {
        if (err_msg != null) {
            _ = c.sqlite3_free(err_msg);
        }
        return Error.ExecFailed;
    }
}

pub fn execFile(db: *sqlite3, allocator: std.mem.Allocator, path: []const u8) !void {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    var buf = try allocator.alloc(u8, @intCast(stat.size));
    defer allocator.free(buf);

    _ = try file.readAll(buf);
    const sql = buf[0..stat.size];
    try exec(db, sql);
}
