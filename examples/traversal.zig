const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const heap = std.heap;
const debug = std.debug;
const graphz = @import("graphz");
const Node = graphz.graph.Node(u8);
const Traversal = graphz.Traversal(u8);

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var arena = heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var root = Node.default(aa, 0);
    var left = Node.default(aa, 1);
    try root.interface.neighbors.append(left.interface);
    const right = Node.default(aa, 2);
    try root.interface.neighbors.append(right.interface);
    const left_of_left = Node.default(aa, 3);
    try left.interface.neighbors.append(left_of_left.interface);

    const expectations = [_]struct { Traversal.Method, []const u8 }{
        .{ .level_order, &.{ 0, 1, 2, 3 } },
        .{ .post_order, &.{ 3, 1, 2, 0 } },
        .{ .pre_order, &.{ 0, 1, 3, 2 } },
    };

    for (expectations) |e| try traverse(aa, &root, e.@"0", e.@"1");
}

fn traverse(
    arena: mem.Allocator,
    node: *Node,
    traversal: Traversal.Method,
    expectations: []const u8,
) !void {
    var it = try node.interface.traverse(node.interface, arena, traversal);
    for (expectations) |expected| {
        if (try it.next()) |actual| {
            try testing.expectEqual(expected, actual.data);
        } else return error.IsNull;
    }
}
