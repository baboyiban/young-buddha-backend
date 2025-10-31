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
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

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

    pub fn deinit(self: *RedisClient) void {
        if (self.context) |ctx| {
            c.redisFree(ctx);
            self.context = null;
        }
    }

    pub fn set(self: *RedisClient, key: []const u8, value: []const u8) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const key_c = try std.fmt.allocPrint(a, "{s}\x00", .{key});
        const value_c = try std.fmt.allocPrint(a, "{s}\x00", .{value});

        const reply = c.redisCommand(self.context, "SET %s %s", key_c.ptr, value_c.ptr);
        defer if (reply != null) c.freeReplyObject(reply);

        if (reply == null) return Error.CommandFailed;

        const r: *c.redisReply = @ptrCast(@alignCast(reply.?));
        if (r.*.type == c.REDIS_REPLY_ERROR) {
            std.debug.print("Redis SET error: {s}\n", .{r.*.str});
            return Error.CommandFailed;
        }
    }

    pub fn get(self: *RedisClient, key: []const u8) !?[]u8 {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const key_c = try std.fmt.allocPrint(a, "{s}\x00", .{key});

        const reply = c.redisCommand(self.context, "GET %s", key_c.ptr);
        defer if (reply != null) c.freeReplyObject(reply);

        if (reply == null) return Error.CommandFailed;

        const r: *c.redisReply = @ptrCast(@alignCast(reply.?));
        if (r.*.type == c.REDIS_REPLY_NIL) return null;
        if (r.*.type == c.REDIS_REPLY_STRING) {
            const len = @as(usize, r.*.len);
            const out_buf = try self.allocator.alloc(u8, len);

            const src_slice = std.mem.span(r.*.str)[0..len];
            var i: usize = 0;
            while (i < len) : (i += 1) {
                out_buf[i] = src_slice[i];
            }

            return out_buf[0..len];
        }
        if (r.*.type == c.REDIS_REPLY_ERROR) {
            std.debug.print("Redis GET error: {s}\n", .{r.*.str});
            return Error.CommandFailed;
        }
        return Error.InvalidReply;
    }

    pub fn del(self: *RedisClient, key: []const u8) !bool {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const key_c = try std.fmt.allocPrint(a, "{s}\x00", .{key});

        const reply = c.redisCommand(self.context, "DEL %s", key_c.ptr);
        defer if (reply != null) c.freeReplyObject(reply);

        if (reply == null) return Error.CommandFailed;

        const r: *c.redisReply = @ptrCast(@alignCast(reply.?));
        if (r.*.type == c.REDIS_REPLY_INTEGER) return r.*.integer > 0;
        if (r.*.type == c.REDIS_REPLY_ERROR) {
            std.debug.print("Redis DEL error: {s}\n", .{r.*.str});
            return Error.CommandFailed;
        }
        return Error.InvalidReply;
    }

    pub fn expire(self: *RedisClient, key: []const u8, seconds: u32) !bool {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const key_c = try std.fmt.allocPrint(a, "{s}\x00", .{key});
        const reply = c.redisCommand(self.context, "EXPIRE %s %d", key_c.ptr, @as(i32, seconds));
        defer if (reply != null) c.freeReplyObject(reply);

        if (reply == null) return Error.CommandFailed;

        const r: *c.redisReply = @ptrCast(@alignCast(reply.?));
        if (r.*.type == c.REDIS_REPLY_INTEGER) return r.*.integer == 1;
        if (r.*.type == c.REDIS_REPLY_ERROR) {
            std.debug.print("Redis EXPIRE error: {s}\n", .{r.*.str});
            return Error.CommandFailed;
        }
        return Error.InvalidReply;
    }

    pub fn exists(self: *RedisClient, key: []const u8) !bool {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const key_c = try std.fmt.allocPrint(a, "{s}\x00", .{key});
        const reply = c.redisCommand(self.context, "EXISTS %s", key_c.ptr);
        defer if (reply != null) c.freeReplyObject(reply);

        if (reply == null) return Error.CommandFailed;

        const r: *c.redisReply = @ptrCast(@alignCast(reply.?));
        if (r.*.type == c.REDIS_REPLY_INTEGER) return r.*.integer > 0;
        if (r.*.type == c.REDIS_REPLY_ERROR) {
            std.debug.print("Redis EXISTS error: {s}\n", .{r.*.str});
            return Error.CommandFailed;
        }
        return Error.InvalidReply;
    }

    pub fn flushAll(self: *RedisClient) !void {
        const reply = c.redisCommand(self.context, "FLUSHALL");
        defer if (reply != null) c.freeReplyObject(reply);

        if (reply == null) return Error.CommandFailed;

        const r: *c.redisReply = @ptrCast(@alignCast(reply.?));
        if (r.*.type == c.REDIS_REPLY_ERROR) {
            std.debug.print("Redis FLUSHALL error: {s}\n", .{r.*.str});
            return Error.CommandFailed;
        }
    }

    pub fn ping(self: *RedisClient) !bool {
        const reply = c.redisCommand(self.context, "PING");
        defer if (reply != null) c.freeReplyObject(reply);

        if (reply == null) return Error.CommandFailed;

        const r: *c.redisReply = @ptrCast(@alignCast(reply.?));
        if (r.*.type == c.REDIS_REPLY_STATUS) {
            const resp = std.mem.span(r.*.str);
            return std.mem.eql(u8, resp, "PONG");
        }
        if (r.*.type == c.REDIS_REPLY_ERROR) {
            std.debug.print("Redis PING error: {s}\n", .{r.*.str});
            return Error.CommandFailed;
        }
        return false;
    }
};
