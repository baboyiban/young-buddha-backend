const std = @import("std");
const db = @import("connection.zig");

test "sqlite exec basic (in-memory)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const dbh = try db.open(":memory:");
    defer db.close(dbh);

    try db.exec(dbh, "CREATE TABLE person (id INTEGER PRIMARY KEY, name TEXT);");
    try db.exec(dbh, "INSERT INTO person (name) VALUES ('alice');");
    // 현재 db.exec는 결과를 반환하지 않으므로 이상이 없으면 성공을 간주
}
