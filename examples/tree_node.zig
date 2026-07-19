const std = @import("std");
const testing = std.testing;
const heap = std.heap;
const debug = std.debug;
const graphz = @import("graphz");
const TreeNode = graphz.tree.Node(u8);

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var arena = heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var node = try TreeNode.init(aa, 0, null);
    var left = try TreeNode.init(aa, 1, &node);
    try node.interface.neighbors.append(&left.interface);
    var center = try TreeNode.init(aa, 2, &node);
    try node.interface.neighbors.append(&center.interface);
    var right = try TreeNode.init(aa, 3, &node);
    try node.interface.neighbors.append(&right.interface);
    var left_of_left = try TreeNode.init(aa, 4, &node);
    try left.interface.neighbors.append(&left_of_left.interface);

    try testing.expectEqual(&left.interface, &TreeNode.previousSibling(&center).?.interface);
    try testing.expectEqual(&right.interface, &TreeNode.nextSibling(&center).?.interface);

    var children = node.children();
    for ([_]u8{ 1, 2 }, 0..) |expected, i| {
        const actual = children.get(i);
        try testing.expectEqual(expected, actual.data());
    }
}
