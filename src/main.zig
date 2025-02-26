// Zig version 0.14.0
const std = @import("std");
const fs = std.fs;
const thread = std.Thread;
const net = std.net;
const http = std.http;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
const server_ip = "0.0.0.0";
//change to port 80 on deployment
const server_port: comptime_int = 9090;
var running = true;

fn siginithandler() void {
    running = false;
}

const routing = struct {
    path: []u8,
    file: []u8,
};

const rootdir = "root";
pub var rootdirfiles: std.ArrayList(routing) = undefined;

pub fn main() !void {

    //parse address and returns an error if unable to parse given address
    rootdirfiles = std.ArrayList(routing).init(allocator);
    defer rootdirfiles.deinit();

    var cwd = std.fs.cwd();
    var dir = cwd.openDir(rootdir, .{ .iterate = true }) catch |err| {
        std.log.err("error {}", .{err});
        return;
    };
    defer dir.close();
    try dir.setAsCwd();
    try traversedir(dir, "/");
    defer freefiles();
    for (rootdirfiles.items) |item| {
        std.log.info("Path: {s}\n", .{item.path});
    }

    const addr = net.Address.parseIp4(server_ip, server_port) catch |err| {
        std.log.err("An error occurred while resolving the IP address: {}\n", .{err});
        return;
    };
    //bind server to addr and listen
    var server = try addr.listen(.{});
    defer server.deinit();

    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    start_server(&server, &pool);
}
fn traversedir(dir: std.fs.Dir, path: []const u8) !void {
    var iter = dir.iterate();
    while (true) {
        const maybeEntry = try iter.next();
        if (maybeEntry == null) break;
        const entry = maybeEntry.?;
        std.log.info("Found entry: {s}, {any}\n", .{ entry.name, entry.kind });

        // If the entry is a file, open and read it:
        if (entry.kind == .file) {
            var file = dir.openFile(entry.name, .{}) catch |err| {
                std.log.err("unable to open file {}", .{err});
                continue;
            };
            defer file.close();

            const buf = file.readToEndAlloc(allocator, 1048576) catch |err| {
                std.log.err("unable to read file {}", .{err});
                continue;
            };
            const pathrel = try std.fmt.allocPrint(allocator, "{s}{s}", .{ path, entry.name });
            const temp = routing{
                .path = pathrel,
                .file = buf,
            };
            try rootdirfiles.append(temp);
            //std.log.info("Content: {s}\n", .{buf});
        } else if (entry.kind == std.fs.File.Kind.directory) {
            var subdir = dir.openDir(entry.name, .{ .iterate = true }) catch |err| {
                std.log.err("error {}", .{err});
                return;
            };
            defer subdir.close();
            const pathrel = try std.fmt.allocPrint(allocator, "{s}{s}/", .{ path, entry.name });

            try traversedir(subdir, pathrel);
        }
    }
}

fn freefiles() void {
    for (rootdirfiles.items) |val| {
        allocator.free(val.file);
    }
}

fn start_server(server: *net.Server, pool: *std.Thread.Pool) void {
    //std.os.linux.sigaction(sig: u6, noalias act: ?*const Sigaction, noalias oact: ?*Sigaction)
    while (running) {
        const connection = server.*.accept() catch |err| {
            std.log.err("Connection to client interrupted: {}\n", .{err});
            continue;
        };
        std.log.info("Thread Spawning\n", .{});
        _ = pool.*.spawn(handle_connection, .{connection}) catch |err| {
            std.log.err("Failed to spawn thread: {}\n", .{err});
            continue;
        };
    }
}

fn respond(request: *http.Server.Request) !void {
    if (request.head.method == http.Method.GET) {
        for (rootdirfiles.items) |value| {
            if (std.mem.eql(u8, request.head.target, "/") and std.mem.eql(u8, value.path, "/index.html")) {
                try request.respond(value.file, .{});
                return;
            } else if (std.mem.eql(u8, request.head.target, value.path)) {
                try request.respond(value.file, .{});
                return;
            }
        }
        try request.respond("404 NOT FOUND", .{});
    }
}
fn handle_connection(connection: net.Server.Connection) void {
    defer connection.stream.close();

    var read_buffer: [4096]u8 = undefined;
    var http_server = http.Server.init(connection, &read_buffer);
    while (true) {
        var request = http_server.receiveHead() catch |err| {
            std.debug.print("Could not read head: {}\n", .{err});
            if (err == http.Server.ReceiveHeadError.HttpConnectionClosing) break;
            return;
        };

        std.log.info("Handling request {any} , {s} , {any} , {any}\n", .{ request.head.method, request.head.target, request.head.version, request.head.transfer_encoding });
        respond(&request) catch |err| {
            std.log.err("Unable to Respond: {}", .{err});
            break;
        };
        if (!request.head.keep_alive) break;
    }
    std.log.info("connection closed\n", .{});
}
