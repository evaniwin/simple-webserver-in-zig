// Zig version 0.14.0
const std = @import("std");
const fs = std.fs;
const thread = std.Thread;
const net = std.net;
const http = std.http;

const server_ip = "0.0.0.0";
//change to port 80 on deployment
const server_port: comptime_int = 8080;
const index_html = @embedFile("index.html");
const favicon = @embedFile("favicon.ico");
const css = @embedFile("style.css");
const script = @embedFile("script.js");
const REQUEST = enum {
    INDEX,
    CSS,
    SCRIPT,
    FAVICON,
    UNKNOWN,
};
pub fn main() !void {
    //parse address and returns an error if unable to parse given address

    const addr = net.Address.parseIp4(server_ip, server_port) catch |err| {
        std.debug.print("An error occurred while resolving the IP address: {}\n", .{err});
        return;
    };
    //bind server to addr and listen
    var server = try addr.listen(.{});

    start_server(&server);
}

fn start_server(server: *net.Server) void {
    while (true) {
        const connection = server.*.accept() catch |err| {
            std.debug.print("Connection to client interrupted: {}\n", .{err});
            continue;
        };
        const connectionthread = thread.spawn(.{}, handle_connection, .{connection}) catch |err| {
            std.debug.print("Failed to spawn thread: {}\n", .{err});
            continue;
        };
        connectionthread.detach();
    }
}

fn loadfiles() !void {}

fn parserequest(req: *http.Server.Request) REQUEST {
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

fn handle_connection(connection: net.Server.Connection) !void {
    defer connection.stream.close();

    var read_buffer: [4096]u8 = undefined;
    var http_server = http.Server.init(connection, &read_buffer);

    var request = http_server.receiveHead() catch |err| {
        std.debug.print("Could not read head: {}\n", .{err});
        return;
    };

    std.debug.print("Handling request for {s}\n", .{request.head.target});
    switch (parserequest(&request)) {
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
            std.debug.print("UNKNOWN REQUEST\n", .{});
        },
    }
}
