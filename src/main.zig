// Zig version 0.14.0
const std = @import("std");
const fs = std.fs;
const thread = std.Thread;
const net = std.net;
const http = std.http;

const server_ip = "0.0.0.0";
//change to port 80 on deployment
const server_port: comptime_int = 9080;
const index_html = @embedFile("root/index.html");
const favicon = @embedFile("root/favicon.ico");
const css = @embedFile("root/style.css");
const script = @embedFile("root/script.js");
const icon = @embedFile("root/icon.jpeg");
var running = true;

fn siginithandler() void {
    running = false;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    //parse address and returns an error if unable to parse given address

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

fn loadfiles() !void {}

fn respond(request: *http.Server.Request) !void {
    if (request.head.method == http.Method.GET) {
        if (std.mem.eql(u8, request.head.target, "/")) {
            try request.respond(index_html, .{});
        } else if (std.mem.eql(u8, request.head.target, "/favicon.ico")) {
            try request.respond(favicon, .{});
        } else if (std.mem.eql(u8, request.head.target, "/style.css")) {
            try request.respond(css, .{});
        } else if (std.mem.eql(u8, request.head.target, "/script.js")) {
            try request.respond(script, .{});
        } else if (std.mem.eql(u8, request.head.target, "/icon.jpeg")) {
            try request.respond(icon, .{});
        } else {
            try request.respond("404 NOT FOUND", .{});
        }
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
