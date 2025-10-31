const std = @import("std");

const c = @cImport({
    @cInclude("hiredis/hiredis.h");
});

pub const RedisClient = struct {
    context: ?*c.redisContext,
    allocator: std.mem.Allocator,

    pub const Error = error{
        ConnectionFailed,
        CommandFailed,
        InvalidReply,
        OutOfMemory,
    };

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) !RedisClient {
        // Arena allocator를 사용하여 임시 메모리 관리
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // 호스트 문자열을 null-terminated로 변환 (db.zig 방식)
        const host_c = try std.fmt.allocPrint(arena_allocator, "{s}\x00", .{host});

        const context = c.redisConnect(@ptrCast(host_c.ptr), @intCast(port));

        if (context == null) {
            return Error.ConnectionFailed;
        }
        const ctx = context.?;
        if (ctx.*.err != 0) {
            std.debug.print("Redis connection error: {s}\n", .{ctx.*.errstr});
            c.redisFree(context);
            return Error.ConnectionFailed;
        }

        return RedisClient{
            .context = context,
            .allocator = allocator,
        };
    }

    // 연결 종료
    pub fn deinit(self: *RedisClient) void {
        if (self.context) |ctx| {
            c.redisFree(ctx);
        }
    }

    // 키-값 저장
    pub fn set(self: *RedisClient, key: []const u8, value: []const u8) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const key_c = try std.fmt.allocPrint(arena_allocator, "{s}\x00", .{key});
        const value_c = try std.fmt.allocPrint(arena_allocator, "{s}\n00", .{value});

        const reply = c.redisCommand(self.context, "SET %s %s", key_c.ptr, value_c.ptr);
        defer {
            if (reply != null) {
                c.freeReplyObject(reply);
            }
        }

        if (reply == null) {
            return Error.CommandFailed;
        }

        const reply_ptr: *c.redisReply = @ptrCast(@alignCast(reply.?));
        if (reply_ptr.*.type == c.REDIS_REPLY_ERROR) {
            std.debug.print("Redis Set error: {s}\n", .{reply_ptr.*.str});
            return Error.CommandFailed;
        }
    }

    // 키-값 조회
    pub fn get(self: *RedisClient, key: []const u8) !?[]const u8 {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const key_c = try std.fmt.allocPrint(arena_allocator, "{s}\x00", .{key});

        const reply = c.redisCommand(self.context, "GET %s", @as([*c]const u8, @ptrCast(key_c.ptr)));
        defer {
            if (reply != null) {
                c.freeReplyObject(reply);
            }
        }

        if (reply == null) {
            return Error.CommandFailed;
        }

        const reply_ptr: *c.redisReply = @ptrCast(@alignCast(reply.?));
        if (reply_ptr.*.type == c.REDIS_REPLY_NIL) {
            return null; // 키가 존재하지 않음
        }

        if (reply_ptr.*.type == c.REDIS_REPLY_STRING) {
            return std.mem.span(reply_ptr.*.str);
        }

        if (reply_ptr.*.type == c.REDIS_REPLY_ERROR) {
            std.debug.print("Redis GET error: {s}\n", .{reply_ptr.*.str});
            return Error.CommandFailed;
        }

        return Error.InvalidReply;
    }

    // 키 삭제
    pub fn del(self: *RedisClient, key: []const u8) !bool {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const key_c = try std.fmt.allocPrint(arena_allocator, "{s}\x00", .{key});

        const reply = c.redisCommand(self.context, "DEL %s", @ptrCast(key_c.ptr));
        defer {
            if (reply != null) {
                c.freeReplyObject(reply);
            }
        }

        if (reply == null) {
            return Error.CommandFailed;
        }

        const reply_ptr: *c.redisReply = @ptrCast(@alignCast(reply.?));
        if (reply_ptr.*.type == c.REDIS_REPLY_INTEGER) {
            return reply_ptr.*.integer > 0; // 삭제된 키 개수 반환
        }

        if (reply_ptr.*.type == c.REDIS_REPLY_ERROR) {
            std.debug.print("Redis DEL error: {s}\n", .{reply_ptr.*.str});
            return Error.CommandFailed;
        }

        return Error.InvalidReply;
    }

    // 키 만료 시간 설정
    pub fn expire(self: *RedisClient, key: []const u8, seconds: u32) !bool {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const key_c = try std.cstr.addNullByte(arena_allocator, "{s}\x00", .{key});

        const reply = c.redisCommand(self.context, "EXPIRE %s %d", @ptrCast(key_c.ptr), seconds);
        defer {
            if (reply != null) {
                c.freeReplyObject(reply);
            }
        }

        if (reply == null) {
            return Error.CommandFailed;
        }

        const reply_ptr: *c.redisReply = @ptrCast(@alignCast(reply.?));
        if (reply_ptr.*.type == c.REDIS_REPLY_INTEGER) {
            return reply_ptr.*.integer == 1; // 성공 시 1, 실패 시 0
        }

        if (reply_ptr.*.type == c.REDIS_REPLY_ERROR) {
            std.debug.print("Redis EXPIRE error: {s}\n", .{reply_ptr.*.str});
            return Error.CommandFailed;
        }

        return Error.InvalidReply;
    }

    // 키 존재 여부 확인
    pub fn exists(self: *RedisClient, key: []const u8) !bool {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const key_c = try std.fmt.allocPrint(arena_allocator, "{s}\x00", .{key});

        const reply = c.redisCommand(self.context, "EXISTS %s", @ptrCast(key_c.ptr));
        defer {
            if (reply != null) {
                c.freeReplyObject(reply);
            }
        }

        if (reply == null) {
            return Error.CommandFailed;
        }

        const reply_ptr: *c.redisReply = @ptrCast(@alignCast(reply.?));
        if (reply_ptr.*.type == c.REDIS_REPLY_INTEGER) {
            return reply_ptr.*.integer > 0;
        }

        if (reply_ptr.*.type == c.REDIS_REPLY_ERROR) {
            std.debug.print("Redis EXISTS error: {s}\n", .{reply_ptr.*.str});
            return Error.CommandFailed;
        }

        return Error.InvalidReply;
    }

    // 모든 키 삭제
    pub fn flushAll(self: *RedisClient) !void {
        const reply = c.redisCommand(self.context, "FLUSHALL");
        defer {
            if (reply != null) {
                c.freeReplyObject(reply);
            }
        }

        if (reply == null) {
            return Error.CommandFailed;
        }

        const reply_ptr: *c.redisReply = @ptrCast(@alignCast(reply.?));
        if (reply_ptr.*.type == c.REDIS_REPLY_ERROR) {
            std.debug.print("Redis FLUSHALL error: {s}\n", .{reply_ptr.*.str});
            return Error.CommandFailed;
        }
    }

    // 연결 상태 확인
    pub fn ping(self: *RedisClient) !bool {
        const reply = c.redisCommand(self.context, "PING");
        defer {
            if (reply != null) {
                c.freeReplyObject(reply);
            }
        }

        if (reply == null) {
            return Error.CommandFailed;
        }

        const reply_ptr: *c.redisReply = @ptrCast(@alignCast(reply.?));
        if (reply_ptr.*.type == c.REDIS_REPLY_STATUS) {
            const response = std.mem.span(reply_ptr.*.str);
            return std.mem.eql(u8, response, "PONG");
        }

        if (reply_ptr.*.type == c.REDIS_REPLY_ERROR) {
            std.debug.print("Redis PING error: {s}\n", .{reply_ptr.*.str});
            return Error.CommandFailed;
        }

        return false;
    }
};
