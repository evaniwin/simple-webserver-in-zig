// Zig version 0.14.0
const std = @import("std");
const fs = std.fs;
const thread = std.Thread;
const net = std.net;
const http = std.http;

const server_ip = "0.0.0.0";
//change to port 80 on deployment
const server_port: comptime_int = 8080;
const index_html = @embedFile("root/index.html");
const favicon = @embedFile("root/favicon.ico");
const css = @embedFile("root/style.css");
const script = @embedFile("root/script.js");
const REQUEST = enum {
    INDEX,
    CSS,
    SCRIPT,
    FAVICON,
    UNKNOWN,
};
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
        _ = pool.*.spawn(handle_connection, .{connection}) catch |err| {
            std.log.err("Failed to spawn thread: {}\n", .{err});
            continue;
        };
    }
}

fn loadfiles() !void {}

fn ParseRequest(req: *http.Server.Request) REQUEST {
    if (std.mem.eql(u8, req.head.target, "/")) {
        return REQUEST.INDEX;
    } else if (std.mem.eql(u8, req.head.target, "/favicon.ico")) {
        return REQUEST.FAVICON;
    } else if (std.mem.eql(u8, req.head.target, "/style.css")) {
        return REQUEST.CSS;
    } else if (std.mem.eql(u8, req.head.target, "/script.js")) {
        return REQUEST.SCRIPT;
    } else {
        return REQUEST.UNKNOWN;
    }
}
fn respond(request: *http.Server.Request) !void {
    switch (ParseRequest(request)) {
        REQUEST.INDEX => {
            try request.respond(index_html, .{});
        },
        REQUEST.CSS => {
            try request.respond(css, .{});
        },
        REQUEST.SCRIPT => {
            try request.respond(script, .{});
        },
        REQUEST.FAVICON => {
            try request.respond(favicon, .{});
        },
        REQUEST.UNKNOWN => {
            std.log.info("UNKNOWN REQUEST\n", .{});
        },
    }
}
fn handle_connection(connection: net.Server.Connection) void {
    defer connection.stream.close();

    var read_buffer: [4096]u8 = undefined;
    var http_server = http.Server.init(connection, &read_buffer);

    var request = http_server.receiveHead() catch |err| {
        std.debug.print("Could not read head: {}\n", .{err});
        return;
    };

    std.log.info("Handling request for {s}\n", .{request.head.target});
    respond(&request) catch |err| {
        std.log.err("Unable to Respond: {}", .{err});
    };
}
