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

    var root = try TreeNode.init(aa, 0, null);
    var left = try TreeNode.init(aa, 1, &root);
    var center = try TreeNode.init(aa, 2, &root);
    var right = try TreeNode.init(aa, 3, &root);

    var root_children = root.children();
    _ = try root_children.append(&left);
    _ = try root_children.append(&center);
    _ = try root_children.append(&right);

    for (0..3) |i| {
        const actual = root_children.get(i);
        try testing.expectEqual(i + 1, actual.data());
    }

    var center_siblings = center.siblings();
    try testing.expectEqual(&left, center_siblings.previous());
    try testing.expectEqual(&right, center_siblings.next());

    var center_parent = center.parent();
    try testing.expectEqual(&root, center_parent.get());

    _ = try center_parent.remove();
    try testing.expectEqual(null, center_parent.get());
    try testing.expectEqual(null, center_siblings.previous());
    try testing.expectEqual(null, center_siblings.next());

    _ = try center_parent.set(&root);
    try testing.expectEqual(&root, center_parent.get());
}
