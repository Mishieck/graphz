const std = @import("std");
const testing = std.testing;
const heap = std.heap;
const debug = std.debug;
const graphz = @import("graphz");
const Node = graphz.graph.Node(u8);

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var arena = heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const neighbor_1 = Node.default(aa, 1);
    const neighbor_2 = Node.default(aa, 2);
    var node = Node.default(aa, 0);
    try node.interface.neighbors.append(neighbor_1.interface);
    try node.interface.neighbors.append(neighbor_2.interface);

    try testing.expectEqual(2, node.interface.neighbors.items.len);
    var neighbors = try node.neighbors(allocator);
    defer Node.deinitNeighbors(allocator, &neighbors);
    try testing.expectEqual(2, neighbors.items.len);
}
