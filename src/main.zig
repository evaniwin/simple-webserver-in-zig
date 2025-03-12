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
const rootdir = "root";
var running = false;
var Tree: *TreeNode = undefined;

pub const TreeNode = struct {
    data: []u8 = undefined,
    isdir: bool = false,
    name: []const u8 = undefined,
    children: std.ArrayList(*TreeNode) = undefined,
    nodesize: u32 = 0,

    pub fn init(data: []u8, isdir: bool, name: []const u8) !*TreeNode {
        const node = try allocator.create(TreeNode);
        node.* = .{
            .data = data,
            .isdir = isdir,
            .name = name,
            .children = std.ArrayList(*TreeNode).init(allocator),
        };
        return node;
    }

    pub fn addChild(parent: *TreeNode, data: []u8, isdir: bool, name: []const u8) !void {
        const child = try TreeNode.init(data, isdir, name);
        try parent.children.append(child);
    }

    pub fn printTree(node: *TreeNode, level: usize) void {
        for (0..level) |_| std.debug.print("  ", .{}); // Indentation
        std.debug.print("{s}\n", .{node.name});

        for (node.children.items) |child| {
            child.printTree(level + 1);
        }
    }

    pub fn freeTree(node: *TreeNode) void {
        for (node.children.items) |child| {
            child.freeTree();
        }
        node.children.deinit();
        allocator.destroy(node);
    }
};

pub fn main() !void {
    //open root directory
    var cwd = std.fs.cwd();
    var directoryhandle = cwd.openDir(rootdir, .{ .iterate = true }) catch |err| {
        std.log.err("error {}", .{err});
        return;
    };
    defer directoryhandle.close();
    try directoryhandle.setAsCwd();

    Tree = try TreeNode.init(undefined, true, "/");
    defer Tree.*.freeTree();
    try traversedir(directoryhandle, Tree);
    Tree.*.printTree(0);
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

fn traversedir(dir: std.fs.Dir, tree: *TreeNode) !void {
    var iter = dir.iterate();
    while (true) {
        const entry = try iter.next();
        if (entry == null) break;
        std.log.info("Found entry: {s}, {any}\n", .{ entry.?.name, entry.?.kind });

        // If the entry is a file, open and read it:
        if (entry.?.kind == .file) {
            var file = dir.openFile(entry.?.name, .{}) catch |err| {
                std.log.err("unable to open file {}", .{err});
                continue;
            };
            defer file.close();

            const buf = file.readToEndAlloc(allocator, 1048576) catch |err| {
                std.log.err("unable to read file {}", .{err});
                continue;
            };
            tree.*.addChild(buf, false, entry.?.name) catch |err| {
                std.log.err("error:{}", .{err});
            };
            tree.*.nodesize += 1;
            //std.log.info("Content: {s}\n", .{buf});
        } else if (entry.?.kind == std.fs.File.Kind.directory) {
            var subdir = dir.openDir(entry.?.name, .{ .iterate = true }) catch |err| {
                std.log.err("error {}", .{err});
                return;
            };
            defer subdir.close();
            try tree.*.addChild("", true, entry.?.name);
            tree.*.nodesize += 1;
            try traversedir(subdir, tree.*.children.items[tree.*.nodesize - 1]);
        }
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
        for (Tree.children.items) |value| {
            if (std.mem.eql(u8, request.head.target, "/") and std.mem.eql(u8, value.name, "/index.html")) {
                try request.respond(value.data, .{});
                return;
            } else if (std.mem.eql(u8, request.head.target, value.name)) {
                try request.respond(value.data, .{});
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
